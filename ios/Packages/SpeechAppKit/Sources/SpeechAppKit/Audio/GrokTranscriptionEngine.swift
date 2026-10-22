import Foundation

public enum GrokTranscriptionError: Error, LocalizedError, Equatable {
    case relayNotConfigured
    case failed(String)
    case timedOut

    public var errorDescription: String? {
        UserFacingFailure.practiceDidNotStart
    }
}

/// Where the speech-to-text socket opens.
public enum GrokEndpoint: Sendable {
    /// Mint relay. The server adds the model and keeps the xAI key.
    case relay(URL)
    /// `wss://api.x.ai/v1/stt`. The bearer token is the xAI key.
    case direct
}

/// Streaming Grok speech-to-text.
public final class GrokTranscriptionEngine: TranscriptionEngine, @unchecked Sendable {
    public private(set) var engineKind: LiveTranscriptionEngine.EngineKind = .grokVoiceTranscribe

    private let endpoint: GrokEndpoint
    private let bearerToken: String
    private let lock = NSLock()
    private var contextualPhrases: [String] = []
    private var updateContinuation: AsyncStream<TranscriptionUpdate>.Continuation?
    private var socket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var stitcher = GrokTranscriptStitcher()
    /// 40 ms frames: a 100 ms frame held each word back up to 100 ms before it was sent.
    public static let liveFrameSeconds: Double = 0.04
    private var frames = PCM16FrameBuffer(frameSeconds: GrokTranscriptionEngine.liveFrameSeconds)
    private var queuedFrames: [Data] = []
    private var ready = false
    private var connectStarted = false
    private var stopped = false
    private var transcriptFinished = false
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var doneContinuation: CheckedContinuation<Void, Never>?

    public init(endpoint: GrokEndpoint, bearerToken: String) {
        self.endpoint = endpoint
        self.bearerToken = bearerToken
    }

    /// Relay socket. Eval and the mint server use this. The app uses `.direct` until launch.
    public convenience init(relayBase: URL, bearerToken: String) {
        self.init(endpoint: .relay(relayBase), bearerToken: bearerToken)
    }

    public func setContextualPhrases(_ phrases: [String]) {
        lock.withLock { contextualPhrases = phrases }
    }

    public var updates: AsyncStream<TranscriptionUpdate> {
        let pair = AsyncStream<TranscriptionUpdate>.makeStream(bufferingPolicy: .bufferingNewest(64))
        lock.withLock { updateContinuation = pair.continuation }
        return pair.stream
    }

    public func prepareIfNeeded(locale: Locale) async throws {
        _ = locale
        try await connectIfNeeded()
    }

    public func start(
        locale: Locale,
        preference: LiveTranscriptionEngine.EnginePreference
    ) async throws {
        _ = locale
        _ = preference
        try await connectIfNeeded()
        engineKind = .grokVoiceTranscribe
    }

    public func append(_ chunk: AudioChunk) {
        let outgoing: (frames: [Data], task: URLSessionWebSocketTask?)? = lock.withLock {
            if stopped { return nil }
            let next = frames.append(samples: chunk.samples, sampleRate: chunk.sampleRate)
            if ready {
                return (next, socket)
            }
            queuedFrames.append(contentsOf: next)
            return nil
        }
        if let outgoing {
            send(outgoing.frames, on: outgoing.task)
        }
    }

    public func stop() async {
        let (task, tail, wasReady): (URLSessionWebSocketTask?, [Data], Bool) = lock.withLock {
            stopped = true
            let flushed = frames.flush() + queuedFrames
            queuedFrames = []
            return (socket, flushed, ready)
        }

        guard let task, wasReady else {
            task?.cancel(with: .goingAway, reason: nil)
            finishUpdates()
            return
        }
        send(tail, on: task)
        task.send(.string(#"{"type":"audio.done"}"#)) { _ in }
        await waitForDone(timeoutSeconds: 4)
        task.cancel(with: .normalClosure, reason: nil)
        finishUpdates()
    }

    /// `http` base from `CONVERSATION_API_BASE` becomes `ws://…/v1/stt`.
    public static func webSocketURL(httpBase: URL, keyterms: [String]) -> URL? {
        guard var parts = URLComponents(url: httpBase, resolvingAgainstBaseURL: false) else {
            return nil
        }
        switch parts.scheme?.lowercased() {
        case "https":
            parts.scheme = "wss"
        case "http":
            parts.scheme = "ws"
        default:
            return nil
        }
        parts.path = "/v1/stt"
        let terms = keytermItems(keyterms)
        parts.queryItems = terms.isEmpty ? nil : terms
        return parts.url
    }

    /// Same query the mint relay adds before it opens xAI. The phone sends this itself until launch.
    public static func directWebSocketURL(keyterms: [String]) -> URL? {
        var parts = URLComponents()
        parts.scheme = "wss"
        parts.host = "api.x.ai"
        parts.path = "/v1/stt"
        parts.queryItems = [
            URLQueryItem(name: "model", value: "grok-voice-transcribe-2.0"),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "encoding", value: "pcm"),
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "smart_turn", value: "0.7"),
            URLQueryItem(name: "smart_turn_timeout", value: "3000"),
            URLQueryItem(name: "filler_words", value: "true"),
        ] + keytermItems(keyterms)
        return parts.url
    }

    private static func keytermItems(_ keyterms: [String]) -> [URLQueryItem] {
        keyterms.prefix(100).compactMap { phrase in
            let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return URLQueryItem(name: "keyterm", value: String(trimmed.prefix(50)))
        }
    }

    private func connectIfNeeded() async throws {
        let already: Bool? = lock.withLock {
            if ready { return nil }
            let started = connectStarted
            if !started { connectStarted = true }
            return started
        }
        guard let already else { return }
        if already {
            try await waitUntilReady()
            return
        }
        try await openAndWait()
    }

    private func openAndWait() async throws {
        let phrases = lock.withLock { contextualPhrases }
        let url: URL?
        switch endpoint {
        case .relay(let base):
            url = Self.webSocketURL(httpBase: base, keyterms: phrases)
        case .direct:
            url = Self.directWebSocketURL(keyterms: phrases)
        }
        guard let url else {
            throw GrokTranscriptionError.relayNotConfigured
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)
        lock.withLock {
            self.session = session
            self.socket = task
        }
        task.resume()
        receiveNext(task)
        try await waitUntilReady()
    }

    private func waitUntilReady() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                guard let self else { return }
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    self.lock.withLock {
                        if self.ready {
                            continuation.resume()
                        } else {
                            self.readyContinuation = continuation
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(ConnectionWaitPolicy.hangLimit))
                throw GrokTranscriptionError.timedOut
            }
            try await group.next()
            group.cancelAll()
        }
    }

    private func waitForDone(timeoutSeconds: Double) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                guard let self else { return }
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    self.lock.withLock {
                        if self.transcriptFinished {
                            continuation.resume()
                        } else {
                            self.doneContinuation = continuation
                        }
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
            }
            await group.next()
            group.cancelAll()
        }
    }

    private func receiveNext(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                let text: String?
                switch message {
                case .string(let value):
                    text = value
                case .data(let data):
                    text = String(data: data, encoding: .utf8)
                @unknown default:
                    text = nil
                }
                if let text {
                    self.handle(text)
                }
                let keepListening = self.lock.withLock { !self.transcriptFinished }
                if keepListening {
                    self.receiveNext(task)
                }
            case .failure(let error):
                self.fail(GrokTranscriptionError.failed(error.localizedDescription))
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            return
        }
        switch type {
        case "transcript.created":
            markReady()
        case "transcript.partial":
            let segmentStart = object["start"] as? Double ?? 0
            let event = GrokPartialEvent(
                text: object["text"] as? String ?? "",
                isFinal: object["is_final"] as? Bool ?? false,
                speechFinal: object["speech_final"] as? Bool ?? false,
                words: GrokTranscriptStitcher.absoluteWords(
                    Self.timedWords(object["words"]),
                    segmentStart: segmentStart
                )
            )
            let (update, continuation) = lock.withLock {
                (stitcher.apply(event), updateContinuation)
            }
            if let update {
                continuation?.yield(update)
            }
        case "transcript.done":
            markDone()
        case "error":
            let message = object["message"] as? String ?? "Grok transcription failed."
            fail(GrokTranscriptionError.failed(message))
        default:
            break
        }
    }

    private static func timedWords(_ value: Any?) -> [GrokTimedWord] {
        guard let rows = value as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let text = row["text"] as? String else { return nil }
            let start = row["start"] as? Double ?? 0
            let end = row["end"] as? Double ?? start
            return GrokTimedWord(text: text, start: start, end: end)
        }
    }

    private func markReady() {
        let (continuation, backlog, task) = lock.withLock { () -> (CheckedContinuation<Void, Error>?, [Data], URLSessionWebSocketTask?) in
            ready = true
            let continuation = readyContinuation
            readyContinuation = nil
            let backlog = queuedFrames
            queuedFrames = []
            return (continuation, backlog, socket)
        }
        send(backlog, on: task)
        continuation?.resume()
    }

    private func markDone() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            transcriptFinished = true
            let continuation = doneContinuation
            doneContinuation = nil
            return continuation
        }
        continuation?.resume()
    }

    private func fail(_ error: Error) {
        UserFacingFailure.log(error, context: "transcription")
        let (readyWait, doneWait) = lock.withLock { () -> (CheckedContinuation<Void, Error>?, CheckedContinuation<Void, Never>?) in
            transcriptFinished = true
            stopped = true
            let readyWait = readyContinuation
            readyContinuation = nil
            let doneWait = doneContinuation
            doneContinuation = nil
            return (readyWait, doneWait)
        }
        readyWait?.resume(throwing: error)
        doneWait?.resume()
        finishUpdates()
    }

    private func send(_ frames: [Data], on task: URLSessionWebSocketTask?) {
        guard let task else { return }
        for frame in frames {
            task.send(.data(frame)) { _ in }
        }
    }

    private func finishUpdates() {
        let continuation = lock.withLock { () -> AsyncStream<TranscriptionUpdate>.Continuation? in
            let continuation = updateContinuation
            updateContinuation = nil
            return continuation
        }
        continuation?.finish()
    }
}
