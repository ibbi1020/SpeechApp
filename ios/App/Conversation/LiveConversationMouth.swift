import AVFoundation
import Foundation
import os
import SpeechAppKit

/// Grok speech-to-speech over WebSocket. Never starts Reading's `MicAudioSource`.
final class LiveConversationMouth: NSObject, ConversationMouth, @unchecked Sendable {
    static let pinnedModel = "grok-voice-think-fast-2.0"
    private static let realtimeURL = URL(
        string: "wss://api.x.ai/v1/realtime?model=\(pinnedModel)"
    )!
    private static let sampleRate: Double = 24_000
    private static let log = Logger(subsystem: "com.speechapp", category: "LiveConversationMouth")

    let events: AsyncStream<MouthEvent>
    private let continuation: AsyncStream<MouthEvent>.Continuation
    private let lock = NSLock()

    /// Listen-back: when the partner's voice actually starts and stops coming out of the
    /// speaker. `finished` fires when the last queued buffer has played, not when Grok
    /// finishes generating, which can be seconds earlier.
    enum PartnerPlayback: Sendable {
        case started
        case finished(transcript: String)
    }

    /// Every microphone buffer, for the listen-back recorder. Gate it on the session phase.
    let micChunks: AsyncStream<AudioChunk>
    private let micContinuation: AsyncStream<AudioChunk>.Continuation
    let partnerPlayback: AsyncStream<PartnerPlayback>
    private let playbackContinuation: AsyncStream<PartnerPlayback>.Continuation
    private var partnerPlaying = false
    private var lastResponseTranscript = ""

    private var closed = false
    private var emittedFailed = false
    private var prepareTask: Task<Void, Error>?
    private var urlSession: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var socketReady = false
    private var micEnabled = false
    private var responseTranscript = ""
    private var captionLedger = CaptionAudioLedger()
    private var captionPlayhead = CaptionPlayhead()
    private var captionPlayheadTask: Task<Void, Never>?
    private var lastYieldedCaption = ""
    private var drainingAfterDone = false
    private var captionSync: CaptionSyncDiagnostics?
    private var pendingNullTurnDetection = false
    private var emittedPlaybackStart = false
    private var bargeIn = BargeInGate()
    private var bargeInPollTask: Task<Void, Never>?
    private var sessionUpdateAttempt = 0
    private var didEmitReady = false
    private var frames = PCM16FrameBuffer(rate: sampleRate)

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var playbackFormat: AVAudioFormat?
    private var inputLevel: Float = 0
    private var outputLevel: Float = 0

    var captionSyncLogURL: URL? {
        captionSync?.logFileURL
    }

    override init() {
        let pair = AsyncStream<MouthEvent>.makeStream(bufferingPolicy: .unbounded)
        events = pair.stream
        continuation = pair.continuation
        let mic = AsyncStream<AudioChunk>.makeStream(bufferingPolicy: .bufferingNewest(64))
        micChunks = mic.stream
        micContinuation = mic.continuation
        let playback = AsyncStream<PartnerPlayback>.makeStream(bufferingPolicy: .unbounded)
        partnerPlayback = playback.stream
        playbackContinuation = playback.continuation
        super.init()
    }

    /// Warm the audio session during the countdown. WebSocket opens in `connect(ephemeralKey:)`.
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

    func connect(ephemeralKey: String) async throws {
        try throwIfClosed()
        do {
            try await prepare()
            try throwIfClosed()
            try await openSocket(token: ephemeralKey)
            try await waitUntilSocketReady()
            try throwIfClosed()
            setMicEnabled(true)
            startCaptionSyncLog()
        } catch {
            teardown()
            throw MouthError.connectFailed
        }
    }

    func sendResponseCreate(instructions: String) async throws {
        try throwIfClosed()
        try sendEvent([
            "type": "response.create",
            "response": ["instructions": instructions],
        ])
    }

    func updateTurnDetectionNull() async throws {
        setMicEnabled(false)
        pendingNullTurnDetection = true
        try throwIfClosed()
        try sendEvent([
            "type": "session.update",
            "session": [
                "turn_detection": NSNull(),
            ],
        ])
    }

    func cancelResponse() async throws {
        try throwIfClosed()
        interruptPlaybackAndCaptions(reason: .cancel)
        try sendEvent(["type": "response.cancel"])
    }

    func close() async {
        teardown()
    }

    func currentInputLevel() async -> Float {
        lock.withLock { inputLevel }
    }

    func currentOutputLevel() async -> Float {
        lock.withLock { outputLevel }
    }

    private func runPrepare() async throws {
        try configureAudioSession()
        try startEngineIfNeeded()
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetoothHFP]
        )
        try session.setActive(true)
    }

    private func startEngineIfNeeded() throws {
        if engine.isRunning { return }
        if player.engine == nil {
            engine.attach(player)
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Self.sampleRate,
                channels: 1,
                interleaved: false
            )
            guard let format else { throw MouthError.connectFailed }
            playbackFormat = format
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }

        let input = engine.inputNode
        do {
            try input.setVoiceProcessingEnabled(true)
        } catch {
            Self.log.error("voice processing unavailable: \(error.localizedDescription, privacy: .public)")
        }
        let hwFormat = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2_400, format: hwFormat) { [weak self] buffer, _ in
            self?.handleMicBuffer(buffer)
        }
        engine.prepare()
        try engine.start()
        if !player.isPlaying {
            player.play()
        }
        setMicEnabled(false)
    }

    private func openSocket(token: String) async throws {
        var request = URLRequest(url: Self.realtimeURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)
        lock.withLock {
            urlSession = session
            socket = task
            socketReady = false
            sessionUpdateAttempt = 0
        }
        task.resume()
        receiveNext(task)
    }

    private func waitUntilSocketReady() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                guard let self else { return }
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    self.lock.withLock {
                        if self.socketReady {
                            continuation.resume()
                        } else if self.closed {
                            continuation.resume(throwing: MouthError.connectFailed)
                        } else {
                            self.readyContinuation = continuation
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(12))
                throw MouthError.connectFailed
            }
            try await group.next()
            group.cancelAll()
        }
    }

    private func markSocketReady() {
        let waiter = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            socketReady = true
            let waiter = readyContinuation
            readyContinuation = nil
            return waiter
        }
        waiter?.resume()
    }

    private func failReady(_ error: Error) {
        let waiter = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            let waiter = readyContinuation
            readyContinuation = nil
            return waiter
        }
        waiter?.resume(throwing: error)
    }

    private func receiveNext(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleServerText(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleServerText(text)
                    }
                @unknown default:
                    break
                }
                if !self.lock.withLock({ self.closed }) {
                    self.receiveNext(task)
                }
            case .failure:
                self.emitFailed()
                self.failReady(MouthError.connectFailed)
            }
        }
    }

    private func handleServerText(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else {
            return
        }
        handleServerEvent(type: type, json: json)
    }

    private func handleServerEvent(type: String, json: [String: Any]) {
        switch type {
        case "session.created":
            let model = ((json["session"] as? [String: Any])?["model"] as? String) ?? ""
            Self.log.info("session.created model=\(model, privacy: .public)")
            if !model.isEmpty, !Self.modelIsPinned(model) {
                continuation.yield(.configDrift)
                failReady(MouthError.connectFailed)
                return
            }
            sessionUpdateAttempt = 0
            sendInitialSessionUpdate(includeClientTurnFlags: true)
        case "session.updated":
            if pendingNullTurnDetection {
                pendingNullTurnDetection = false
                try? sendEvent(["type": "input_audio_buffer.clear"])
            }
            markSocketReady()
            emitReadyOnce()
            continuation.yield(.sessionUpdated)
        case "error":
            let message = (json["error"] as? [String: Any])?["message"] as? String
                ?? (json["message"] as? String)
                ?? "unknown"
            Self.log.error("realtime error: \(message, privacy: .public)")
            let (attempt, ready) = lock.withLock { (sessionUpdateAttempt, socketReady) }
            if !ready {
                if attempt == 1 {
                    // Retry without create_response / interrupt_response.
                    sendInitialSessionUpdate(includeClientTurnFlags: false)
                } else {
                    failReady(MouthError.connectFailed)
                    emitFailed()
                }
            }
        case "input_audio_buffer.speech_started":
            handleSpeechStarted()
        case "input_audio_buffer.speech_stopped":
            handleSpeechStopped()
        case "response.created":
            beginPartnerResponse()
            mutateBargeIn { $0.noteAgentAudio() }
            continuation.yield(.responseStarted)
        case "response.audio.delta", "response.output_audio.delta", "conversation.output_audio.delta":
            if let delta = json["delta"] as? String {
                playBase64PCM16(delta)
            }
            notePartnerPlaybackStarted()
            mutateBargeIn { $0.noteAgentAudio() }
        case "response.audio_transcript.delta", "response.output_audio_transcript.delta":
            if let delta = json["delta"] as? String {
                responseTranscript += delta
                let heard = lock.withLock { () -> Bool in
                    captionLedger.appendTranscript(delta)
                    return captionLedger.heardFrames > 0
                }
                logTranscriptDelta(deltaChars: delta.count)
                // If audio is already playing, catch the caption up to the playhead.
                if heard {
                    publishCaptionFromLedger(forceFull: false)
                }
            }
        case "response.audio_transcript.done", "response.output_audio_transcript.done":
            if let transcript = json["transcript"] as? String, !transcript.isEmpty {
                responseTranscript = transcript
                let heard = lock.withLock { () -> Bool in
                    captionLedger.seedTranscriptIfEmpty(transcript)
                    return captionLedger.heardFrames > 0
                }
                logTranscriptDone()
                if heard {
                    publishCaptionFromLedger(forceFull: false)
                }
            }
        case "response.done":
            stopBargeInPoll()
            let release = mutateBargeIn { $0.noteResponseDone() }
            let full = outputTranscript(from: json)
            lock.withLock { lastResponseTranscript = full }
            continuation.yield(.responseDone(transcript: full))
            finishPartnerResponseAudio(seedTranscript: full)
            if release == .passThrough {
                continuation.yield(.speechStarted)
            }
        default:
            break
        }
    }

    private func emitReadyOnce() {
        let should = lock.withLock { () -> Bool in
            guard !didEmitReady else { return false }
            didEmitReady = true
            return true
        }
        if should {
            continuation.yield(.ready)
        }
    }

    private func sendInitialSessionUpdate(includeClientTurnFlags: Bool) {
        sessionUpdateAttempt += 1
        var turnDetection: [String: Any] = ["type": "server_vad"]
        if includeClientTurnFlags {
            turnDetection["create_response"] = false
            turnDetection["interrupt_response"] = false
        }
        let pcmFormat: [String: Any] = ["type": "audio/pcm", "rate": Int(Self.sampleRate)]
        try? sendEvent([
            "type": "session.update",
            "session": [
                "voice": "eve",
                "tools": [],
                "reasoning": ["effort": "none"],
                "turn_detection": turnDetection,
                "audio": [
                    "input": ["format": pcmFormat],
                    "output": ["format": pcmFormat],
                ],
            ],
        ])
    }

    private func handleMicBuffer(_ buffer: AVAudioPCMBuffer) {
        let samples = FileReplayAudioSource.floatSamples(from: buffer)
        let rms = Self.rms(samples)
        let rate = buffer.format.sampleRate
        micContinuation.yield(AudioChunk(samples: samples, sampleRate: rate, hostTime: 0))
        let enabled = lock.withLock { () -> Bool in
            inputLevel = rms
            return micEnabled && !closed
        }
        guard enabled else { return }
        let chunks: [Data] = lock.withLock {
            frames.append(samples: samples, sampleRate: rate)
        }
        for chunk in chunks {
            sendAudioAppend(chunk)
        }
    }

    private func sendAudioAppend(_ pcm: Data) {
        let b64 = pcm.base64EncodedString()
        try? sendEvent([
            "type": "input_audio_buffer.append",
            "audio": b64,
        ])
    }

    private func playBase64PCM16(_ b64: String) {
        guard let data = Data(base64Encoded: b64), !data.isEmpty else { return }
        guard let format = playbackFormat else { return }
        let frameCount = data.count / MemoryLayout<Int16>.size
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))
        else {
            return
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard let channel = buffer.floatChannelData?[0] else { return }
        data.withUnsafeBytes { raw in
            guard let source = raw.bindMemory(to: Int16.self).baseAddress else { return }
            var sum: Float = 0
            for i in 0..<frameCount {
                let sample = Float(Int16(littleEndian: source[i])) / 32_768
                channel[i] = sample
                sum += sample * sample
            }
            let level = sqrt(sum / Float(frameCount))
            lock.withLock { outputLevel = level }
        }
        lock.withLock {
            captionLedger.enqueueAudio(frames: frameCount)
            captionPlayhead.enqueue(frames: frameCount, now: ProcessInfo.processInfo.systemUptime)
        }
        startCaptionPlayhead()
        logAudioDelta(deltaFrames: frameCount)
        player.scheduleBuffer(buffer) { [weak self] in
            self?.noteAudioBufferFinished(frames: frameCount)
        }
    }

    private func startCaptionPlayhead() {
        lock.withLock {
            guard captionPlayheadTask == nil else { return }
            captionPlayheadTask = Task { [weak self] in
                while !Task.isCancelled {
                    self?.tickCaptionPlayhead()
                    try? await Task.sleep(for: .milliseconds(40))
                }
            }
        }
    }

    private func stopCaptionPlayhead() {
        let task = lock.withLock { () -> Task<Void, Never>? in
            let task = captionPlayheadTask
            captionPlayheadTask = nil
            return task
        }
        task?.cancel()
    }

    /// Advance captions by how far the current buffer has actually played.
    private func tickCaptionPlayhead() {
        let caption: String? = lock.withLock {
            guard captionPlayhead.isPlaying else { return nil }
            let heard = captionPlayhead.heardFrames(
                now: ProcessInfo.processInfo.systemUptime,
                sampleRate: Self.sampleRate
            )
            captionLedger.noteHeard(frames: heard)
            return captionLedger.revealedCaption()
        }
        if let caption {
            yieldCaptionIfChanged(caption)
        }
    }

    private func beginPartnerResponse() {
        clearCaptionSyncState()
        captionSync?.noteResponseCreated()
    }

    private func finishPartnerResponseAudio(seedTranscript: String) {
        responseTranscript = ""
        let idle: Bool = lock.withLock {
            outputLevel = 0
            captionLedger.seedTranscriptIfEmpty(seedTranscript)
            drainingAfterDone = true
            return captionLedger.queuedFrames == 0
        }
        logResponseDone(draining: !idle)
        // Remaining buffers keep advancing the caption as they finish.
        // If nothing is queued, show the seeded line once.
        if idle {
            publishCaptionFromLedger(forceFull: true)
            clearCaptionSyncState()
            notePartnerPlaybackFinished()
        } else {
            publishCaptionFromLedger(forceFull: false)
        }
    }

    private func clearCaptionSyncState() {
        let task: Task<Void, Never>? = lock.withLock {
            responseTranscript = ""
            captionLedger.reset()
            captionPlayhead.reset()
            let task = captionPlayheadTask
            captionPlayheadTask = nil
            lastYieldedCaption = ""
            drainingAfterDone = false
            emittedPlaybackStart = false
            return task
        }
        task?.cancel()
    }

    private func noteAudioBufferFinished(frames: Int) {
        let snapshot = lock.withLock { () -> (before: Int, after: Int, caption: String, pending: Int, queued: Int, completed: Int) in
            let before = captionLedger.revealedWordCount
            let pendingBefore = CaptionAudioLedger.splitWords(captionLedger.pendingText).count
            captionPlayhead.completeCurrent(now: ProcessInfo.processInfo.systemUptime)
            _ = captionLedger.completeAudio(frames: frames)
            let caption = captionLedger.revealedCaption()
            return (
                before,
                captionLedger.revealedWordCount,
                caption,
                pendingBefore,
                captionLedger.queuedFrames,
                captionLedger.completedFrames
            )
        }
        let previousYield = lock.withLock { lastYieldedCaption }
        yieldCaptionIfChanged(snapshot.caption)
        let didYield = lock.withLock { lastYieldedCaption != previousYield }
        captionSync?.noteAudioComplete(
            deltaFrames: frames,
            queuedFrames: snapshot.queued,
            completedFrames: snapshot.completed,
            pendingWords: snapshot.pending,
            revealedWordsBefore: snapshot.before,
            revealedWordsAfter: snapshot.after,
            yielded: didYield,
            preview: CaptionSyncDiagnostics.preview(snapshot.caption)
        )

        let finish = lock.withLock { () -> (clear: Bool, stopClock: Bool) in
            let clear = drainingAfterDone
                && captionLedger.queuedFrames > 0
                && captionLedger.completedFrames >= captionLedger.queuedFrames
            return (clear, !clear && !captionPlayhead.isPlaying)
        }
        if finish.clear {
            publishCaptionFromLedger(forceFull: true)
            clearCaptionSyncState()
            notePartnerPlaybackFinished()
        } else if finish.stopClock {
            stopCaptionPlayhead()
        }
    }

    private func publishCaptionFromLedger(forceFull: Bool) {
        let caption: String = lock.withLock {
            if forceFull {
                let remaining = captionLedger.queuedFrames - captionLedger.completedFrames
                if remaining > 0 {
                    _ = captionLedger.completeAudio(frames: remaining)
                }
                return captionLedger.revealedCaption(forceFull: true)
            }
            return captionLedger.revealedCaption()
        }
        yieldCaptionIfChanged(caption)
    }

    /// Yields at most one phrase-sized line per change; never rewinds.
    private func yieldCaptionIfChanged(_ caption: String) {
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldYield = lock.withLock { () -> Bool in
            guard trimmed != lastYieldedCaption else { return false }
            lastYieldedCaption = trimmed
            return !trimmed.isEmpty
        }
        guard shouldYield else { return }

        let wordCount = CaptionAudioLedger.splitWords(trimmed).count
        logCaptionYield(revealedWords: wordCount, preview: trimmed)
        continuation.yield(.partnerCaption(trimmed))
    }

    private enum InterruptReason { case cancel, teardown }

    /// Drop unheard audio and freeze caption sync on barge-in / cancel.
    private func interruptPlaybackAndCaptions(reason: InterruptReason) {
        if reason == .cancel {
            let snap = ledgerLogSnapshot()
            captionSync?.noteCancel(
                queuedFrames: snap.queued,
                completedFrames: snap.completed,
                pendingWords: snap.pendingWords,
                revealedWords: snap.revealedWords
            )
        }
        player.stop()
        if engine.isRunning { player.play() }
        clearCaptionSyncState()
        lock.withLock { outputLevel = 0 }
        notePartnerPlaybackFinished()
    }

    private func notePartnerPlaybackFinished() {
        let transcript: String? = lock.withLock {
            guard partnerPlaying else { return nil }
            partnerPlaying = false
            return lastResponseTranscript
        }
        if let transcript {
            playbackContinuation.yield(.finished(transcript: transcript))
        }
    }

    private func startCaptionSyncLog() {
        guard captionSync == nil else { return }
        captionSync = CaptionSyncDiagnostics(conversationID: UUID().uuidString)
    }

    private func ledgerLogSnapshot() -> (
        queued: Int,
        completed: Int,
        pendingWords: Int,
        revealedWords: Int
    ) {
        lock.withLock {
            (
                captionLedger.queuedFrames,
                captionLedger.completedFrames,
                CaptionAudioLedger.splitWords(captionLedger.pendingText).count,
                captionLedger.revealedWordCount
            )
        }
    }

    private func logAudioDelta(deltaFrames: Int) {
        let snap = ledgerLogSnapshot()
        captionSync?.noteAudioDelta(
            deltaFrames: deltaFrames,
            queuedFrames: snap.queued,
            completedFrames: snap.completed,
            pendingWords: snap.pendingWords,
            revealedWords: snap.revealedWords
        )
    }

    private func logTranscriptDelta(deltaChars: Int) {
        let snap = ledgerLogSnapshot()
        captionSync?.noteTranscriptDelta(
            deltaChars: deltaChars,
            queuedFrames: snap.queued,
            completedFrames: snap.completed,
            pendingWords: snap.pendingWords,
            revealedWords: snap.revealedWords
        )
    }

    private func logTranscriptDone() {
        let snap = ledgerLogSnapshot()
        captionSync?.noteTranscriptDone(
            queuedFrames: snap.queued,
            completedFrames: snap.completed,
            pendingWords: snap.pendingWords,
            revealedWords: snap.revealedWords
        )
    }

    private func logResponseDone(draining: Bool) {
        let snap = ledgerLogSnapshot()
        captionSync?.noteResponseDone(
            queuedFrames: snap.queued,
            completedFrames: snap.completed,
            pendingWords: snap.pendingWords,
            revealedWords: snap.revealedWords,
            draining: draining
        )
    }

    private func logCaptionYield(revealedWords: Int, preview: String) {
        let snap = ledgerLogSnapshot()
        captionSync?.noteCaptionYield(
            revealedWords: revealedWords,
            pendingWords: snap.pendingWords,
            queuedFrames: snap.queued,
            completedFrames: snap.completed,
            preview: CaptionSyncDiagnostics.preview(preview)
        )
    }

    private func notePartnerPlaybackStarted() {
        let firstForTurn: Bool = lock.withLock {
            guard !partnerPlaying else { return false }
            partnerPlaying = true
            lastResponseTranscript = ""
            return true
        }
        if firstForTurn {
            playbackContinuation.yield(.started)
        }
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

    private static func modelIsPinned(_ model: String) -> Bool {
        model == pinnedModel || model.hasPrefix("\(pinnedModel)-")
    }

    private func outputTranscript(from json: [String: Any]) -> String {
        if !responseTranscript.isEmpty { return responseTranscript }
        guard let response = json["response"] as? [String: Any] else { return "" }
        if let t = response["output_audio_transcript"] as? String { return t }
        guard let output = response["output"] as? [[String: Any]] else { return "" }
        var parts: [String] = []
        for item in output {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for part in content {
                if let t = part["transcript"] as? String { parts.append(t) }
                else if let t = part["text"] as? String { parts.append(t) }
            }
        }
        return parts.joined()
    }

    private func sendEvent(_ body: [String: Any]) throws {
        let task = lock.withLock { socket }
        guard let task, task.state == .running else {
            throw MouthError.connectFailed
        }
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body),
              let text = String(data: data, encoding: .utf8)
        else {
            throw MouthError.connectFailed
        }
        task.send(.string(text)) { [weak self] error in
            if error != nil {
                self?.emitFailed()
            }
        }
    }

    private func setMicEnabled(_ enabled: Bool) {
        lock.withLock { micEnabled = enabled }
    }

    private func emitFailed() {
        let should = lock.withLock { () -> Bool in
            guard !emittedFailed else { return false }
            emittedFailed = true
            return true
        }
        if should {
            continuation.yield(.failed)
        }
    }

    private func throwIfClosed() throws {
        if lock.withLock({ closed }) { throw MouthError.connectFailed }
    }

    private func teardown() {
        stopBargeInPoll()
        interruptPlaybackAndCaptions(reason: .teardown)
        captionSync?.finish()
        let (task, session, waiter) = lock.withLock { () -> (URLSessionWebSocketTask?, URLSession?, CheckedContinuation<Void, Error>?) in
            closed = true
            micEnabled = false
            let task = socket
            let session = urlSession
            let waiter = readyContinuation
            socket = nil
            urlSession = nil
            readyContinuation = nil
            prepareTask = nil
            return (task, session, waiter)
        }
        waiter?.resume(throwing: MouthError.connectFailed)
        task?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
        engine.inputNode.removeTap(onBus: 0)
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        continuation.yield(.disconnected)
        continuation.finish()
        notePartnerPlaybackFinished()
        micContinuation.finish()
        playbackContinuation.finish()
    }

    private static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        return sqrt(sum / Float(samples.count))
    }
}
