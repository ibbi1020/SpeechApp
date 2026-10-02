import AVFoundation
import Foundation
import os
import SpeechAppKit

/// xAI Grok Voice (speech-to-speech) over a WebSocket. Never starts Reading's `MicAudioSource`.
///
/// Latency notes:
/// - The socket opens and the session is configured during the countdown (`prepare`), so
///   `connect` only unmutes the mic and reports `.ready`.
/// - The mic goes through the voice-processing IO unit (echo cancellation) and an
///   `AVAudioSinkNode`, so frames leave at the IO buffer size (~10–20 ms), not the ~100 ms a tap gives.
/// - Mic audio is sent as raw binary PCM frames. Partner audio is played as each delta arrives.
/// - `.responseDone` is held until the queued partner audio has played, because the server
///   finishes generating long before playback ends.
final class LiveConversationMouth: NSObject, ConversationMouth, @unchecked Sendable {
    static let model = "grok-voice-latest"
    static let voice = "eve"
    static let wireRate: Double = 24_000
    private static let endpoint = URL(string: "wss://api.x.ai/v1/realtime?model=\(model)")!
    private static let log = Logger(subsystem: "com.speechapp", category: "LiveConversationMouth")
    /// Mic frames are batched to this size before sending.
    private static let sendChunkFrames = 480  // 20 ms at 24 kHz

    let events: AsyncStream<MouthEvent>
    private let continuation: AsyncStream<MouthEvent>.Continuation
    private let apiKey: String
    private let lock = NSLock()
    private let ioQueue = DispatchQueue(label: "com.speechapp.conversation.io", qos: .userInteractive)

    // Socket
    private var urlSession: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var prepareTask: Task<Void, Error>?
    private var sessionReadyWaiter: CheckedContinuation<Bool, Never>?
    private var sessionReady = false

    // Audio
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var sink: AVAudioSinkNode?
    private var usingTap = false
    private var micCallbacks = 0
    private var micRate: Double = 48_000
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?
    private var pendingMic = Data()
    private let wireFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: LiveConversationMouth.wireRate, channels: 1, interleaved: true
    )!
    private let playFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: LiveConversationMouth.wireRate, channels: 1, interleaved: false
    )!
    private var observers: [NSObjectProtocol] = []

    // State (guarded by `lock`)
    private var closed = false
    private var emittedFailed = false
    private var micLive = false
    private var inputLevel: Float = 0
    private var outputLevel: Float = 0
    private var queuedBuffers = 0
    /// Bumped on flush so callbacks from dropped buffers are ignored.
    private var playGeneration = 0
    private var responseDonePending: String?
    private var cancelledResponses: Set<String> = []
    private var activeResponseID: String?

    // Event-handling state (receive task only)
    private var responseTranscript = ""
    private var pendingNullTurnDetection = false
    private var emittedPlaybackStart = false
    private var bargeIn = BargeInGate()
    private var bargeInPollTask: Task<Void, Never>?

    init(apiKey: String) {
        self.apiKey = apiKey
        let pair = AsyncStream<MouthEvent>.makeStream(bufferingPolicy: .unbounded)
        events = pair.stream
        continuation = pair.continuation
        super.init()
    }

    // MARK: - ConversationMouth

    /// Audio session, engine, socket, and session config during the countdown. Mic stays unsent.
    func prepare() async throws {
        try throwIfClosed()
        if let prepareTask {
            try await prepareTask.value
            return
        }
        let task = Task { try await self.runPrepare() }
        lock.withLock { prepareTask = task }
        do {
            try await task.value
        } catch {
            lock.withLock { prepareTask = nil }
            throw error
        }
    }

    /// The key is the one the mouth was built with; the argument is kept for the protocol.
    func connect(ephemeralKey: String) async throws {
        try throwIfClosed()
        do {
            try await prepare()
            try throwIfClosed()
        } catch {
            teardown()
            throw MouthError.connectFailed
        }
        lock.withLock { micLive = true }
        continuation.yield(.ready)
    }

    func sendResponseCreate(instructions: String) async throws {
        try throwIfClosed()
        let response: [String: Any] = ["instructions": instructions]
        send(["type": "response.create", "response": response])
    }

    func updateTurnDetectionNull() async throws {
        lock.withLock { micLive = false }
        pendingNullTurnDetection = true
        let session: [String: Any] = ["turn_detection": NSNull()]
        send(["type": "session.update", "session": session])
    }

    func cancelResponse() async throws {
        let id = lock.withLock { () -> String? in
            if let id = activeResponseID { cancelledResponses.insert(id) }
            return activeResponseID
        }
        send(["type": "response.cancel"])
        flushPlayback()
        Self.log.info("barge-in cancel \(id ?? "-", privacy: .public)")
    }

    func close() async {
        teardown()
    }

    func currentInputLevel() async -> Float {
        lock.withLock { closed ? 0 : inputLevel }
    }

    func currentOutputLevel() async -> Float {
        lock.withLock { closed ? 0 : outputLevel }
    }

    // MARK: - Prepare

    private func runPrepare() async throws {
        try configureAudioSession()
        try startEngine()
        try openSocket()
        let ready = await waitForSessionReady(timeout: 10)
        try throwIfClosed()
        guard ready else { throw MouthError.connectFailed }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetoothHFP]
        )
        try? session.setPreferredIOBufferDuration(0.01)
        try session.setActive(true)
        preferLoudspeaker()
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            // `.override` is our own speaker switch. Handling it would loop.
            if raw == AVAudioSession.RouteChangeReason.override.rawValue { return }
            self?.preferLoudspeaker()
        })
        observers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.restartEngineAfterConfigChange()
        })
    }

    /// Loudspeaker when the route is the built-in receiver. Leaves headphones and Bluetooth alone.
    private func preferLoudspeaker() {
        guard !lock.withLock({ closed }) else { return }
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
        guard outputs.contains(where: { $0.portType == .builtInReceiver }) else { return }
        guard !outputs.contains(where: Self.isExternalPlayback) else { return }
        try? session.overrideOutputAudioPort(.speaker)
    }

    private static func isExternalPlayback(_ port: AVAudioSessionPortDescription) -> Bool {
        switch port.portType {
        case .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .airPlay, .carAudio:
            return true
        default:
            return false
        }
    }

    private func startEngine() throws {
        let input = engine.inputNode
        // Echo cancellation + noise suppression for loudspeaker conversation.
        try input.setVoiceProcessingEnabled(true)
        let micFormat = input.outputFormat(forBus: 0)
        micRate = micFormat.sampleRate

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playFormat)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            self?.noteOutputLevel(buffer)
        }

        let sinkNode = AVAudioSinkNode { [weak self] _, frameCount, bufferList in
            self?.captureMic(frameCount: frameCount, bufferList: bufferList)
            return noErr
        }
        sink = sinkNode
        engine.attach(sinkNode)
        engine.connect(input, to: sinkNode, format: micFormat)

        engine.prepare()
        try engine.start()
        player.play()
        scheduleSinkWatchdog()
    }

    /// Some routes never call the sink block. Fall back to a tap after 1 s of nothing.
    private func scheduleSinkWatchdog() {
        ioQueue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            let silent = self.lock.withLock { !self.closed && self.micCallbacks == 0 && !self.usingTap }
            guard silent else { return }
            Self.log.error("sink node silent; using input tap")
            DispatchQueue.main.async { self.switchToTap() }
        }
    }

    private func switchToTap() {
        guard !lock.withLock({ closed }) else { return }
        lock.withLock { usingTap = true }
        engine.stop()
        if let sink {
            engine.disconnectNodeInput(sink)
            engine.detach(sink)
            self.sink = nil
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        micRate = format.sampleRate
        input.installTap(onBus: 0, bufferSize: 256, format: format) { [weak self] buffer, _ in
            guard let self, let data = buffer.floatChannelData else { return }
            let samples = Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
            self.ingestMic(samples, rate: format.sampleRate)
        }
        engine.prepare()
        try? engine.start()
        player.play()
    }

    private func restartEngineAfterConfigChange() {
        guard !lock.withLock({ closed }) else { return }
        guard !engine.isRunning else { return }
        engine.prepare()
        try? engine.start()
        player.play()
    }

    // MARK: - Mic path

    /// Real-time thread: copy channel 0 and hop off.
    private func captureMic(frameCount: AVAudioFrameCount, bufferList: UnsafePointer<AudioBufferList>) {
        let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        guard let first = list.first, let raw = first.mData else { return }
        let stride = max(1, Int(first.mNumberChannels))
        let frames = Int(frameCount)
        let floats = raw.assumingMemoryBound(to: Float.self)
        var samples = [Float](repeating: 0, count: frames)
        for i in 0..<frames {
            samples[i] = floats[i * stride]
        }
        ingestMic(samples, rate: micRate)
    }

    private func ingestMic(_ samples: [Float], rate: Double) {
        ioQueue.async { [weak self] in
            self?.processMic(samples, rate: rate)
        }
    }

    private func processMic(_ samples: [Float], rate: Double) {
        guard !samples.isEmpty else { return }
        var sum: Float = 0
        for s in samples { sum += s * s }
        let rms = (sum / Float(samples.count)).squareRoot()
        let live = lock.withLock { () -> Bool in
            micCallbacks += 1
            inputLevel = min(1, rms)
            return micLive && !closed
        }
        guard live, let pcm = convertToWire(samples, rate: rate) else { return }
        pendingMic.append(pcm)
        let chunkBytes = Self.sendChunkFrames * 2
        if pendingMic.count >= chunkBytes {
            let out = pendingMic
            pendingMic = Data()
            socket?.send(.data(out)) { _ in }
        }
    }

    private func convertToWire(_ samples: [Float], rate: Double) -> Data? {
        guard let inFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false
        ),
            let source = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(samples.count))
        else { return nil }
        source.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { ptr in
            source.floatChannelData?[0].update(from: ptr.baseAddress!, count: samples.count)
        }
        if converter == nil || converterInputFormat?.sampleRate != rate {
            converter = AVAudioConverter(from: inFormat, to: wireFormat)
            converterInputFormat = inFormat
        }
        guard let converter else { return nil }
        let capacity = AVAudioFrameCount(Double(samples.count) * Self.wireRate / rate) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: wireFormat, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        // `.noDataNow` (not end of stream) keeps resampler state between callbacks.
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return source
        }
        guard error == nil, out.frameLength > 0, let data = out.int16ChannelData else { return nil }
        return Data(bytes: data[0], count: Int(out.frameLength) * 2)
    }

    // MARK: - Partner playback

    private func playDelta(_ base64: String, responseID: String?) {
        if let responseID, lock.withLock({ cancelledResponses.contains(responseID) }) { return }
        guard let pcm = Data(base64Encoded: base64), pcm.count >= 2 else { return }
        let frames = pcm.count / 2
        guard let buffer = AVAudioPCMBuffer(pcmFormat: playFormat, frameCapacity: AVAudioFrameCount(frames)),
              let out = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(frames)
        pcm.withUnsafeBytes { raw in
            let ints = raw.bindMemory(to: Int16.self)
            for i in 0..<frames {
                out[i] = Float(Int16(littleEndian: ints[i])) / 32768
            }
        }
        let generation = lock.withLock { () -> Int in
            queuedBuffers += 1
            return playGeneration
        }
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            self?.bufferPlayed(generation: generation)
        }
        if !player.isPlaying { player.play() }
    }

    private func bufferPlayed(generation: Int) {
        let done = lock.withLock { () -> String? in
            guard generation == playGeneration else { return nil }
            queuedBuffers = max(0, queuedBuffers - 1)
            guard queuedBuffers == 0, let pending = responseDonePending else { return nil }
            responseDonePending = nil
            return pending
        }
        if let done { finishResponse(transcript: done) }
    }

    private func flushPlayback() {
        let done = lock.withLock { () -> String? in
            playGeneration += 1
            queuedBuffers = 0
            let pending = responseDonePending
            responseDonePending = nil
            return pending
        }
        player.stop()  // drops scheduled buffers; their callbacks carry the old generation
        player.play()
        if let done { finishResponse(transcript: done) }
    }

    private func noteOutputLevel(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += data[0][i] * data[0][i] }
        let rms = (sum / Float(n)).squareRoot()
        lock.withLock { outputLevel = min(1, rms) }
    }

    // MARK: - Socket

    private func openSocket() throws {
        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: config)
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = 16 * 1024 * 1024
        urlSession = session
        socket = task
        task.resume()
        receiveTask = Task { [weak self] in
            await self?.receiveLoop(task)
        }
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await task.receive()
            } catch {
                if !lock.withLock({ closed }) {
                    Self.log.error("socket receive failed: \(error.localizedDescription, privacy: .public)")
                    resolveSessionReady(false)
                    continuation.yield(.disconnected)
                    emitFailed()
                }
                return
            }
            switch message {
            case .string(let text):
                guard let data = text.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                handleServerEvent(json)
            case .data:
                continue
            @unknown default:
                continue
            }
        }
    }

    /// Ordered sends: every send goes through the IO queue so control events and mic frames stay in order.
    private func send(_ body: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body),
              let text = String(data: data, encoding: .utf8) else { return }
        ioQueue.async { [weak self] in
            guard let self, let socket = self.socket else { return }
            // Flush buffered mic first so the server sees audio before the control event.
            if !self.pendingMic.isEmpty {
                let out = self.pendingMic
                self.pendingMic = Data()
                socket.send(.data(out)) { _ in }
            }
            socket.send(.string(text)) { error in
                if let error {
                    Self.log.error("send failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func sendInitialSessionUpdate() {
        // Server VAD at its defaults: in the bench, setting silence_duration_ms (even 200)
        // made end-of-speech detection slower (~550–900 ms) than the default (~350 ms).
        // The session owns turns: it sends response.create with per-turn instructions.
        let turnDetection: [String: Any] = [
            "type": "server_vad",
            "create_response": false,
        ]
        let format: [String: Any] = ["type": "audio/pcm", "rate": Int(Self.wireRate)]
        let input: [String: Any] = ["format": format, "transport": "binary"]
        let output: [String: Any] = ["format": format]
        let audio: [String: Any] = ["input": input, "output": output]
        let reasoning: [String: Any] = ["effort": "none"]
        let session: [String: Any] = [
            "voice": Self.voice,
            "instructions": "You are a friendly English conversation partner. Keep replies short and spoken.",
            "reasoning": reasoning,
            "turn_detection": turnDetection,
            "audio": audio,
        ]
        send(["type": "session.update", "session": session])
    }

    private func waitForSessionReady(timeout: TimeInterval) async -> Bool {
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            self?.resolveSessionReady(false)
        }
        defer { timeoutTask.cancel() }
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let immediate = lock.withLock { () -> Bool? in
                if sessionReady { return true }
                if closed { return false }
                sessionReadyWaiter = cont
                return nil
            }
            if let immediate { cont.resume(returning: immediate) }
        }
    }

    private func resolveSessionReady(_ ok: Bool) {
        let waiter = lock.withLock { () -> CheckedContinuation<Bool, Never>? in
            if ok { sessionReady = true }
            let w = sessionReadyWaiter
            sessionReadyWaiter = nil
            return w
        }
        waiter?.resume(returning: ok)
    }

    // MARK: - Server events

    private func handleServerEvent(_ json: [String: Any]) {
        guard let type = json["type"] as? String else { return }
        switch type {
        case "session.created":
            let model = ((json["session"] as? [String: Any])?["model"] as? String) ?? ""
            Self.log.info("session.created model=\(model, privacy: .public)")
            sendInitialSessionUpdate()
        case "session.updated":
            if !lock.withLock({ sessionReady }) {
                resolveSessionReady(true)
                return
            }
            if pendingNullTurnDetection {
                pendingNullTurnDetection = false
                send(["type": "input_audio_buffer.clear"])
            }
            continuation.yield(.sessionUpdated)
        case "input_audio_buffer.speech_started":
            handleSpeechStarted()
        case "input_audio_buffer.speech_stopped":
            handleSpeechStopped()
        case "response.created":
            let id = (json["response"] as? [String: Any])?["id"] as? String
            lock.withLock {
                activeResponseID = id
                responseDonePending = nil
            }
            responseTranscript = ""
            emittedPlaybackStart = false
            // Arm barge-in before the first audio frame so echo of the open is not a user turn.
            mutateBargeIn { $0.noteAgentAudio() }
            continuation.yield(.responseStarted)
        case "response.output_audio.delta", "response.audio.delta":
            let id = json["response_id"] as? String
            if let id, lock.withLock({ cancelledResponses.contains(id) }) { return }
            if let delta = json["delta"] as? String {
                playDelta(delta, responseID: id)
            }
            notePartnerPlaybackStarted()
            mutateBargeIn { $0.noteAgentAudio() }
        case "response.output_audio_transcript.delta", "response.audio_transcript.delta":
            let id = json["response_id"] as? String
            if let id, lock.withLock({ cancelledResponses.contains(id) }) { return }
            if let delta = json["delta"] as? String {
                responseTranscript += delta
                let trimmed = responseTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    continuation.yield(.partnerCaption(trimmed))
                }
            }
        case "response.done":
            let transcript = outputTranscript(from: json)
            responseTranscript = ""
            // Report the turn as done only once the queued audio has played out.
            let playNow = lock.withLock { () -> Bool in
                activeResponseID = nil
                if queuedBuffers == 0 { return true }
                responseDonePending = transcript
                return false
            }
            if playNow { finishResponse(transcript: transcript) }
        case "error":
            let message = ((json["error"] as? [String: Any])?["message"] as? String) ?? ""
            Self.log.error("server error: \(message, privacy: .public)")
        default:
            break
        }
    }

    private func finishResponse(transcript: String) {
        stopBargeInPoll()
        let release = mutateBargeIn { $0.noteResponseDone() }
        continuation.yield(.responseDone(transcript: transcript))
        if release == .passThrough {
            continuation.yield(.speechStarted)
        }
    }

    private func notePartnerPlaybackStarted() {
        guard !emittedPlaybackStart else { return }
        emittedPlaybackStart = true
        continuation.yield(.audioDelta)
    }

    private func handleSpeechStarted() {
        switch mutateBargeIn({ $0.onSpeechStarted() }) {
        case .passThrough:
            continuation.yield(.speechStarted)
        case .hold:
            continuation.yield(.interruptHeard)
            startBargeInPoll()
        case .commitCancel, .swallow:
            break
        }
    }

    private func handleSpeechStopped() {
        stopBargeInPoll()
        switch mutateBargeIn({ $0.onSpeechStopped() }) {
        case .passThrough:
            continuation.yield(.speechStopped)
        case .swallow:
            continuation.yield(.interruptDropped)
        case .hold, .commitCancel:
            break
        }
    }

    private func startBargeInPoll() {
        stopBargeInPoll()
        bargeInPollTask = Task { [weak self] in
            guard let self else { return }
            var now = Date().timeIntervalSince1970
            while !Task.isCancelled {
                let level = await self.currentInputLevel()
                if Task.isCancelled { return }
                let action = self.mutateBargeIn { $0.tick(now: now, level: level) }
                if action == .commitCancel {
                    try? await self.cancelResponse()
                    self.continuation.yield(.speechStarted)
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
                now = Date().timeIntervalSince1970
            }
        }
    }

    private func stopBargeInPoll() {
        bargeInPollTask?.cancel()
        bargeInPollTask = nil
    }

    private func mutateBargeIn<T>(_ body: (inout BargeInGate) -> T) -> T {
        lock.withLock { body(&bargeIn) }
    }

    private func outputTranscript(from json: [String: Any]) -> String {
        if !responseTranscript.isEmpty { return responseTranscript }
        guard let response = json["response"] as? [String: Any],
              let output = response["output"] as? [[String: Any]] else { return "" }
        var parts: [String] = []
        for item in output {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for part in content {
                if let t = part["transcript"] as? String {
                    parts.append(t)
                } else if let t = part["text"] as? String {
                    parts.append(t)
                }
            }
        }
        return parts.joined()
    }

    // MARK: - Teardown

    private func throwIfClosed() throws {
        try lock.withLock {
            if closed { throw MouthError.connectFailed }
        }
    }

    private func emitFailed() {
        let shouldEmit = lock.withLock { () -> Bool in
            guard !closed, !emittedFailed else { return false }
            emittedFailed = true
            return true
        }
        if shouldEmit {
            continuation.yield(.failed)
        }
    }

    private func teardown() {
        let alreadyClosed = lock.withLock { () -> Bool in
            if closed { return true }
            closed = true
            micLive = false
            return false
        }
        if alreadyClosed { return }

        stopBargeInPoll()
        prepareTask?.cancel()
        prepareTask = nil
        resolveSessionReady(false)
        receiveTask?.cancel()
        receiveTask = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil

        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        player.stop()
        engine.mainMixerNode.removeTap(onBus: 0)
        if usingTap { engine.inputNode.removeTap(onBus: 0) }
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        continuation.finish()
    }
}
