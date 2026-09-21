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

    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
    }()

    let events: AsyncStream<MouthEvent>
    private let continuation: AsyncStream<MouthEvent>.Continuation
    private let lock = NSLock()

    private var peer: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var localAudioTrack: RTCAudioTrack?
    private var closed = false
    private var emittedFailed = false
    private var ready = false
    private var dataChannelIsOpen = false
    private var dataChannelOpened: CheckedContinuation<Void, Never>?
    private var iceCompleteWaiter: CheckedContinuation<Void, Never>?
    private var iceWaitID = 0
    private var disconnectGraceTask: Task<Void, Never>?
    private var iceWasConnected = false
    private var responseTranscript = ""
    private var pendingNullTurnDetection = false

    override init() {
        let pair = AsyncStream<MouthEvent>.makeStream(bufferingPolicy: .unbounded)
        events = pair.stream
        continuation = pair.continuation
        super.init()
    }

    func connect(ephemeralKey: String) async throws {
        try lock.withLock {
            if closed { throw MouthError.connectFailed }
        }
        do {
            try configureAudioSession()
            let peer = try makePeerConnection()
            self.peer = peer
            let offer = try await createOffer(peer: peer)
            try await setLocalDescription(offer, peer: peer)
            await waitForICEComplete(peer: peer)
            try throwIfClosed()
            let answerSDP = try await postSDP(offer.sdp, ephemeralKey: ephemeralKey)
            try throwIfClosed()
            try await setRemoteDescription(
                RTCSessionDescription(type: .answer, sdp: answerSDP),
                peer: peer
            )
            lock.withLock { ready = true }
        } catch {
            teardown()
            throw MouthError.connectFailed
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

    func close() async {
        teardown()
    }

    private func throwIfClosed() throws {
        try lock.withLock {
            if closed { throw MouthError.connectFailed }
        }
    }

    private func configureAudioSession() throws {
        let rtc = RTCAudioSession.sharedInstance()
        rtc.useManualAudio = true
        rtc.ignoresPreferredAttributeConfigurationErrors = true
        rtc.lockForConfiguration()
        defer { rtc.unlockForConfiguration() }
        try rtc.setCategory(.playAndRecord, with: .defaultToSpeaker)
        try rtc.setMode(.voiceChat)
        try rtc.setActive(true)
        rtc.isAudioEnabled = true
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

    private func waitForICEComplete(peer: RTCPeerConnection) async {
        if peer.iceGatheringState == .complete { return }
        iceWaitID += 1
        let id = iceWaitID
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            iceCompleteWaiter = cont
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                self?.finishICEWait(expectedID: id)
            }
        }
    }

    private func finishICEWait(expectedID: Int? = nil) {
        if let expectedID, expectedID != iceWaitID { return }
        iceCompleteWaiter?.resume()
        iceCompleteWaiter = nil
        iceWaitID += 1
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
                            "interrupt_response": true,
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
        case "session.updated":
            if pendingNullTurnDetection {
                pendingNullTurnDetection = false
                try? sendEvent(["type": "input_audio_buffer.clear"])
            }
            continuation.yield(.sessionUpdated)
        case "input_audio_buffer.speech_started":
            continuation.yield(.speechStarted)
        case "input_audio_buffer.speech_stopped":
            continuation.yield(.speechStopped)
        case "response.created":
            responseTranscript = ""
        case "response.audio.delta", "response.output_audio.delta", "conversation.output_audio.delta":
            continuation.yield(.audioDelta)
        case "response.audio_transcript.delta", "response.output_audio_transcript.delta":
            if let delta = json["delta"] as? String {
                responseTranscript += delta
            }
        case "response.done":
            continuation.yield(.responseDone(transcript: outputTranscript(from: json)))
            responseTranscript = ""
        default:
            break
        }
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
        let isReady = lock.withLock { ready && !closed }
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

        disconnectGraceTask?.cancel()
        disconnectGraceTask = nil
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
        rtc.lockForConfiguration()
        try? rtc.setActive(false)
        rtc.unlockForConfiguration()
        rtc.isAudioEnabled = false

        continuation.finish()
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

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}

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
