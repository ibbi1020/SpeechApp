import AVFoundation
import Foundation
import os
import SpeechAppKit
@preconcurrency import WebRTC

/// OpenAI Realtime over WebRTC. Never starts Reading's `MicAudioSource`.
final class LiveConversationMouth: NSObject, ConversationMouth, @unchecked Sendable {
    static let pinnedModel = "gpt-realtime-2.1-mini"
    private static let callsURL = URL(string: "https://api.openai.com/v1/realtime/calls")!
    private static let stun = "stun:stun.l.google.com:19302"
    private static let log = Logger(subsystem: "com.speechapp", category: "LiveConversationMouth")

    /// Audio-only factory. Video codecs would hit the GPU next to the orb WebGL canvas.
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory()
    }()

    let events: AsyncStream<MouthEvent>
    private let continuation: AsyncStream<MouthEvent>.Continuation
    private let lock = NSLock()

    private var peer: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var localAudioTrack: RTCAudioTrack?
    private var closed = false
    private var emittedFailed = false
    private var iceReady = false
    private var dataChannelIsOpen = false
    private var dataChannelOpened: CheckedContinuation<Void, Never>?
    private var iceReadyWaiter: CheckedContinuation<Void, Never>?
    private var iceWaitID = 0
    private var prepareTask: Task<Void, Error>?
    private var preparedOfferSDP: String?
    private var disconnectGraceTask: Task<Void, Never>?
    private var iceWasConnected = false
    private var responseTranscript = ""
    private var pendingNullTurnDetection = false
    private var emittedPlaybackStart = false
    private var bargeIn = BargeInGate()
    private var bargeInPollTask: Task<Void, Never>?

    override init() {
        let pair = AsyncStream<MouthEvent>.makeStream(bufferingPolicy: .unbounded)
        events = pair.stream
        continuation = pair.continuation
        super.init()
    }

    /// Audio session, peer, offer, and ICE during the countdown. Local mic stays muted.
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
            guard let peer, let offerSDP = preparedOfferSDP else {
                throw MouthError.connectFailed
            }
            localAudioTrack?.isEnabled = true
            let answerSDP = try await postSDP(offerSDP, ephemeralKey: ephemeralKey)
            try throwIfClosed()
            try await setRemoteDescription(
                RTCSessionDescription(type: .answer, sdp: answerSDP),
                peer: peer
            )
            lock.withLock { iceReady = true }
        } catch {
            teardown()
            throw MouthError.connectFailed
        }
    }

    private func runPrepare() async throws {
        try configureAudioSession()
        let peer = try makePeerConnection()
        self.peer = peer
        let offer = try await createOffer(peer: peer)
        try await setLocalDescription(offer, peer: peer)
        // Countdown must stay send-muted until connect posts the SDP.
        localAudioTrack?.isEnabled = false
        preparedOfferSDP = offer.sdp
        await waitForICEReady(peer: peer)
        try throwIfClosed()
        // Prefer post-gather SDP when candidates were appended.
        if let local = peer.localDescription?.sdp, !local.isEmpty {
            preparedOfferSDP = local
        }
    }

    func sendResponseCreate(instructions: String) async throws {
        try await waitForDataChannel()
        try sendEvent([
            "type": "response.create",
            "response": ["instructions": instructions],
        ])
    }

    func updateTurnDetectionNull() async throws {
        localAudioTrack?.isEnabled = false
        pendingNullTurnDetection = true
        try await waitForDataChannel()
        try sendEvent([
            "type": "session.update",
            "session": [
                "type": "realtime",
                "audio": [
                    "input": [
                        "turn_detection": NSNull(),
                    ],
                ],
            ],
        ])
    }

    func cancelResponse() async throws {
        try await waitForDataChannel()
        try sendEvent(["type": "response.cancel"])
    }

    func close() async {
        teardown()
    }

    func currentInputLevel() async -> Float {
        await audioLevel(ConversationAudioLevels.input)
    }

    func currentOutputLevel() async -> Float {
        await audioLevel(ConversationAudioLevels.output)
    }

    private func audioLevel(
        _ extract: @escaping @Sendable ([ConversationAudioStat]) -> Float
    ) async -> Float {
        let connection: RTCPeerConnection? = lock.withLock { closed ? nil : peer }
        guard let connection else { return 0 }
        return await withCheckedContinuation { continuation in
            connection.statistics { report in
                continuation.resume(returning: extract(Self.samples(from: report)))
            }
        }
    }

    private static func samples(from report: RTCStatisticsReport) -> [ConversationAudioStat] {
        report.statistics.values.map { stat in
            let values = stat.values
            let remote: Bool? = (values["remoteSource"] as? NSNumber).map(\.boolValue)
            return ConversationAudioStat(
                type: stat.type,
                kind: values["kind"] as? String,
                remoteSource: remote,
                audioLevel: floatValue(values["audioLevel"])
            )
        }
    }

    private static func floatValue(_ value: NSObject?) -> Float {
        (value as? NSNumber)?.floatValue ?? 0
    }

    private func throwIfClosed() throws {
        try lock.withLock {
            if closed { throw MouthError.connectFailed }
        }
    }

    private func configureAudioSession() throws {
        // WebRTC reapplies its own configuration when the audio unit starts.
        // That default is voice-chat to the receiver and drops `.defaultToSpeaker`,
        // so the partner plays from the earpiece.
        let preferred = RTCAudioSessionConfiguration.webRTC()
        preferred.categoryOptions = [.defaultToSpeaker, .allowBluetoothHFP]
        RTCAudioSessionConfiguration.setWebRTC(preferred)

        let rtc = RTCAudioSession.sharedInstance()
        rtc.useManualAudio = true
        rtc.ignoresPreferredAttributeConfigurationErrors = true
        rtc.add(self)
        rtc.lockForConfiguration()
        defer { rtc.unlockForConfiguration() }
        try rtc.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetoothHFP]
        )
        try rtc.setActive(true)
        rtc.isAudioEnabled = true
        try? rtc.overrideOutputAudioPort(.speaker)
    }

    /// Loudspeaker when the route is the built-in receiver. Leaves headphones and Bluetooth alone.
    private func preferLoudspeaker() {
        let closedNow = lock.withLock { closed }
        guard !closedNow else { return }
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        guard outputs.contains(where: { $0.portType == .builtInReceiver }) else { return }
        guard !outputs.contains(where: Self.isExternalPlayback) else { return }
        let rtc = RTCAudioSession.sharedInstance()
        rtc.lockForConfiguration()
        defer { rtc.unlockForConfiguration() }
        try? rtc.overrideOutputAudioPort(.speaker)
    }

    private static func isExternalPlayback(_ port: AVAudioSessionPortDescription) -> Bool {
        switch port.portType {
        case .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .airPlay, .carAudio:
            return true
        default:
            return false
        }
    }

    private func makePeerConnection() throws -> RTCPeerConnection {
        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: [Self.stun])]
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherOnce
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let peer = Self.factory.peerConnection(
            with: config,
            constraints: constraints,
            delegate: self
        ) else {
            throw MouthError.connectFailed
        }
        let audioSource = Self.factory.audioSource(with: constraints)
        let audioTrack = Self.factory.audioTrack(with: audioSource, trackId: "speechapp-audio")
        localAudioTrack = audioTrack
        peer.add(audioTrack, streamIds: ["speechapp-conversation"])
        let channelConfig = RTCDataChannelConfiguration()
        channelConfig.isOrdered = true
        guard let channel = peer.dataChannel(forLabel: "oai-events", configuration: channelConfig) else {
            throw MouthError.connectFailed
        }
        channel.delegate = self
        dataChannel = channel
        return peer
    }

    private func createOffer(peer: RTCPeerConnection) async throws -> RTCSessionDescription {
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": "false",
            ],
            optionalConstraints: nil
        )
        return try await withCheckedThrowingContinuation { cont in
            peer.offer(for: constraints) { sdp, error in
                if let sdp {
                    cont.resume(returning: sdp)
                } else {
                    cont.resume(throwing: error ?? MouthError.connectFailed)
                }
            }
        }
    }

    private func setLocalDescription(_ sdp: RTCSessionDescription, peer: RTCPeerConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            peer.setLocalDescription(sdp) { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }
    }

    private func setRemoteDescription(_ sdp: RTCSessionDescription, peer: RTCPeerConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            peer.setRemoteDescription(sdp) { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }
    }

    /// Proceed once we have a server-reflexive candidate, or after 1s / gather-complete.
    private func waitForICEReady(peer: RTCPeerConnection) async {
        if Self.isICEOfferReady(peer) { return }
        iceWaitID += 1
        let id = iceWaitID
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            iceReadyWaiter = cont
            if Self.isICEOfferReady(peer) {
                finishICEWait(expectedID: id)
                return
            }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.finishICEWait(expectedID: id)
            }
        }
    }

    private func finishICEWait(expectedID: Int? = nil) {
        if let expectedID, expectedID != iceWaitID { return }
        iceReadyWaiter?.resume()
        iceReadyWaiter = nil
        iceWaitID += 1
    }

    private static func isICEOfferReady(_ peer: RTCPeerConnection) -> Bool {
        offerHasSrflx(peer.localDescription?.sdp) || peer.iceGatheringState == .complete
    }

    private static func offerHasSrflx(_ sdp: String?) -> Bool {
        guard let sdp else { return false }
        return sdp.contains(" typ srflx ")
    }

    private func postSDP(_ sdp: String, ephemeralKey: String) async throws -> String {
        var lastError: Error = MouthError.connectFailed
        for _ in 0..<2 {
            do {
                return try await postSDPOnce(sdp, ephemeralKey: ephemeralKey)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func postSDPOnce(_ sdp: String, ephemeralKey: String) async throws -> String {
        var req = URLRequest(url: Self.callsURL)
        req.httpMethod = "POST"
        req.setValue("Bearer \(ephemeralKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
        req.httpBody = sdp.data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code), let answer = String(data: data, encoding: .utf8), !answer.isEmpty else {
            throw MouthError.connectFailed
        }
        return answer
    }

    private func waitForDataChannel() async throws {
        try throwIfClosed()
        if dataChannel?.readyState == .open { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let alreadyOpen = lock.withLock { () -> Bool in
                if dataChannel?.readyState == .open { return true }
                dataChannelOpened = cont
                return false
            }
            if alreadyOpen { cont.resume() }
        }
        try throwIfClosed()
        guard dataChannel?.readyState == .open else { throw MouthError.connectFailed }
    }

    private func noteDataChannelOpen() {
        let waiter = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            dataChannelIsOpen = true
            let waiter = dataChannelOpened
            dataChannelOpened = nil
            return waiter
        }
        waiter?.resume()
    }

    private func sendEvent(_ body: [String: Any]) throws {
        guard let channel = dataChannel, channel.readyState == .open else {
            throw MouthError.connectFailed
        }
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body) else {
            throw MouthError.connectFailed
        }
        channel.sendData(RTCDataBuffer(data: data, isBinary: false))
    }

    private func sendInitialSessionUpdate() {
        let body: [String: Any] = [
            "type": "session.update",
            "session": [
                "type": "realtime",
                "audio": [
                    "input": [
                        "turn_detection": [
                            "type": "semantic_vad",
                            "eagerness": "low",
                            "create_response": false,
                            // Client owns barge-in via BargeInGate + response.cancel.
                            // Server interrupt cancels on echo / cough before any filter runs.
                            "interrupt_response": false,
                        ],
                        "noise_reduction": [
                            "type": "near_field",
                        ],
                    ],
                ],
            ],
        ]
        try? sendEvent(body)
    }

    private func handleServerEvent(_ json: [String: Any]) {
        guard let type = json["type"] as? String else { return }
        switch type {
        case "session.created":
            let model = ((json["session"] as? [String: Any])?["model"] as? String) ?? ""
            Self.log.info("session.created model=\(model, privacy: .public)")
            if !Self.modelIsPinned(model) {
                continuation.yield(.configDrift)
                return
            }
            sendInitialSessionUpdate()
            continuation.yield(.ready)
        case "session.updated":
            if pendingNullTurnDetection {
                pendingNullTurnDetection = false
                try? sendEvent(["type": "input_audio_buffer.clear"])
            }
            continuation.yield(.sessionUpdated)
        case "input_audio_buffer.speech_started":
            handleSpeechStarted()
        case "input_audio_buffer.speech_stopped":
            handleSpeechStopped()
        case "response.created":
            responseTranscript = ""
            emittedPlaybackStart = false
            // Arm barge-in before first audio frame — closes the race where mic
            // echo of the open is treated as a user turn before noteAgentAudio.
            mutateBargeIn { $0.noteAgentAudio() }
            continuation.yield(.responseStarted)
        case "response.audio.delta", "response.output_audio.delta", "conversation.output_audio.delta",
             "output_audio_buffer.started":
            notePartnerPlaybackStarted()
            mutateBargeIn { $0.noteAgentAudio() }
        case "output_audio_buffer.stopped":
            break
        case "response.audio_transcript.delta", "response.output_audio_transcript.delta":
            if let delta = json["delta"] as? String {
                responseTranscript += delta
                let trimmed = responseTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    continuation.yield(.partnerCaption(trimmed))
                }
            }
        case "response.done":
            stopBargeInPoll()
            let release = mutateBargeIn { $0.noteResponseDone() }
            continuation.yield(.responseDone(transcript: outputTranscript(from: json)))
            responseTranscript = ""
            if release == .passThrough {
                continuation.yield(.speechStarted)
            }
        default:
            break
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

    private func handleICEConnection(_ state: RTCIceConnectionState) {
        let isReady = lock.withLock { iceReady && !closed }
        guard isReady else { return }
        switch state {
        case .connected, .completed:
            iceWasConnected = true
            disconnectGraceTask?.cancel()
            disconnectGraceTask = nil
        case .disconnected:
            guard iceWasConnected else { return }
            continuation.yield(.disconnected)
            disconnectGraceTask?.cancel()
            disconnectGraceTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled else { return }
                self.emitFailed()
            }
        case .failed, .closed:
            emitFailed()
        default:
            break
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
            return false
        }
        if alreadyClosed { return }

        stopBargeInPoll()
        disconnectGraceTask?.cancel()
        disconnectGraceTask = nil
        prepareTask?.cancel()
        prepareTask = nil
        preparedOfferSDP = nil
        finishICEWait()
        let waiter = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            let waiter = dataChannelOpened
            dataChannelOpened = nil
            return waiter
        }
        waiter?.resume()

        dataChannel?.delegate = nil
        dataChannel?.close()
        dataChannel = nil
        peer?.delegate = nil
        peer?.close()
        peer = nil
        localAudioTrack = nil

        let rtc = RTCAudioSession.sharedInstance()
        rtc.remove(self)
        rtc.lockForConfiguration()
        try? rtc.setActive(false)
        rtc.unlockForConfiguration()
        rtc.isAudioEnabled = false

        continuation.finish()
    }
}

extension LiveConversationMouth: RTCAudioSessionDelegate {
    func audioSessionDidStartPlayOrRecord(_ session: RTCAudioSession) {
        DispatchQueue.main.async { [weak self] in
            self?.preferLoudspeaker()
        }
    }

    func audioSessionDidChangeRoute(
        _ session: RTCAudioSession,
        reason: AVAudioSession.RouteChangeReason,
        previousRoute: AVAudioSessionRouteDescription
    ) {
        // `.override` is the notification from our own speaker switch. Handling it would loop.
        guard reason != .override else { return }
        DispatchQueue.main.async { [weak self] in
            self?.preferLoudspeaker()
        }
    }
}

extension LiveConversationMouth: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        handleICEConnection(newState)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        if newState == .complete {
            finishICEWait()
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        if Self.isICEOfferReady(peerConnection) {
            finishICEWait()
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        dataChannel.delegate = self
        self.dataChannel = dataChannel
        if dataChannel.readyState == .open {
            noteDataChannelOpen()
        }
    }
}

extension LiveConversationMouth: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        if dataChannel.readyState == .open {
            noteDataChannelOpen()
        }
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        guard let json = try? JSONSerialization.jsonObject(with: buffer.data) as? [String: Any] else {
            return
        }
        handleServerEvent(json)
    }
}
