import Foundation

/// Pairs live partner captions with audio when the API sends separate,
/// untimed transcript and PCM streams.
///
/// Reveal follows **heard** playback (`heardFrames`), including the buffer that
/// is playing now — not only buffers that have fully finished, and not a fraction
/// of audio still queued. Leftover words flush only when the caller forces it
/// (reply audio drained), never when the queue briefly catches up mid-reply.
public struct CaptionAudioLedger: Sendable {
    public private(set) var pendingText = ""
    public private(set) var queuedFrames = 0
    public private(set) var completedFrames = 0
    public private(set) var heardFrames = 0
    public private(set) var revealedWordCount = 0

    public init() {}

    public mutating func reset() {
        pendingText = ""
        queuedFrames = 0
        completedFrames = 0
        heardFrames = 0
        revealedWordCount = 0
    }

    public mutating func appendTranscript(_ delta: String) {
        guard !delta.isEmpty else { return }
        pendingText += delta
    }

    /// When the wire sent little or no live transcript, seed from `response.done`.
    public mutating func seedTranscriptIfEmpty(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if pendingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pendingText = trimmed
        }
    }

    public mutating func enqueueAudio(frames: Int) {
        guard frames > 0 else { return }
        queuedFrames += frames
    }

    /// Provisional playhead while a buffer is still sounding. Clamped to queued audio.
    public mutating func noteHeard(frames: Int) {
        guard frames > 0, queuedFrames > 0 else { return }
        heardFrames = min(queuedFrames, max(heardFrames, frames))
    }

    /// Call when a scheduled PCM buffer finishes playing.
    @discardableResult
    public mutating func completeAudio(frames: Int) -> String {
        if frames > 0 {
            completedFrames = min(completedFrames + frames, queuedFrames)
            heardFrames = min(queuedFrames, max(heardFrames, completedFrames))
        }
        return revealedCaption()
    }

    /// Caption for the words that should be on screen for the current playhead.
    public mutating func revealedCaption(forceFull: Bool = false) -> String {
        let words = Self.splitWords(pendingText)
        guard !words.isEmpty else { return "" }

        let unlocked = CaptionPlaybackSync.revealedWordCount(
            words: words,
            completedFrames: heardFrames,
            audioFinished: forceFull
        )
        // Never pull words back once shown.
        let count = min(words.count, max(unlocked, revealedWordCount))
        revealedWordCount = count
        return CaptionPlaybackSync.joinLeadingWords(words, count: count)
    }

    public var isFullyRevealed: Bool {
        let words = Self.splitWords(pendingText)
        let audioDone = completedFrames >= queuedFrames
        guard !words.isEmpty else { return audioDone }
        return revealedWordCount >= words.count && audioDone
    }

    public static func splitWords(_ transcript: String) -> [String] {
        CaptionPlaybackSync.splitWords(transcript)
    }
}

/// Maps heard partner audio to a short caption line when the API has no timestamps.
public enum CaptionPlaybackSync: Sendable {
    public static let sampleRate: Double = 24_000
    /// Spoken characters per second (spaces included). Live logs land around 17–19.
    public static let charactersPerSecond: Double = 18

    /// How many characters of transcript hearing `completedFrames` may unlock.
    public static func characterBudget(
        completedFrames: Int,
        sampleRate: Double = sampleRate,
        charactersPerSecond: Double = charactersPerSecond
    ) -> Int {
        guard completedFrames > 0, sampleRate > 0, charactersPerSecond > 0 else { return 0 }
        let seconds = Double(completedFrames) / sampleRate
        return max(1, Int(seconds * charactersPerSecond))
    }

    /// How many leading whole words to show for the current playhead.
    public static func revealedWordCount(
        words: [String],
        completedFrames: Int,
        audioFinished: Bool
    ) -> Int {
        guard !words.isEmpty else { return 0 }
        if audioFinished { return words.count }

        let budget = characterBudget(completedFrames: completedFrames)
        guard budget > 0 else { return 0 }

        var used = 0
        for (index, word) in words.enumerated() {
            // Spaces between words count toward the budget.
            let needed = index == 0 ? word.count : word.count + 1
            if used + needed > budget {
                // Any credit unlocks at least the first word.
                return index == 0 ? 1 : index
            }
            used += needed
        }
        return words.count
    }

    /// Leading words of `transcript` unlocked by heard audio.
    public static func revealedPrefix(
        transcript: String,
        completedFrames: Int,
        audioFinished: Bool = false
    ) -> String {
        let words = splitWords(transcript)
        let count = revealedWordCount(
            words: words,
            completedFrames: completedFrames,
            audioFinished: audioFinished
        )
        return joinLeadingWords(words, count: count)
    }

    public static func splitWords(_ transcript: String) -> [String] {
        transcript.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func joinLeadingWords(_ words: [String], count: Int) -> String {
        guard count > 0 else { return "" }
        return words.prefix(count).joined(separator: " ")
    }
}

/// Tracks which scheduled PCM buffer is sounding so captions can advance
/// during a buffer, not only when it finishes.
public struct CaptionPlayhead: Sendable {
    public private(set) var confirmedFrames = 0
    public private(set) var pendingBuffers: [Int] = []
    public private(set) var currentStartedAt: TimeInterval?

    public init() {}

    public mutating func reset() {
        confirmedFrames = 0
        pendingBuffers = []
        currentStartedAt = nil
    }

    public var isPlaying: Bool { currentStartedAt != nil }

    /// Queue a buffer. The clock starts immediately when nothing else is sounding.
    public mutating func enqueue(frames: Int, now: TimeInterval) {
        guard frames > 0 else { return }
        pendingBuffers.append(frames)
        if currentStartedAt == nil {
            currentStartedAt = now
        }
    }

    /// Finished frames plus how far into the current buffer `now` has reached.
    public func heardFrames(now: TimeInterval, sampleRate: Double) -> Int {
        guard let start = currentStartedAt, let current = pendingBuffers.first, sampleRate > 0 else {
            return confirmedFrames
        }
        let elapsed = max(0, now - start)
        let partial = min(current, Int(elapsed * sampleRate))
        return confirmedFrames + partial
    }

    /// Mark the sounding buffer finished and start the clock on the next one.
    @discardableResult
    public mutating func completeCurrent(now: TimeInterval) -> Int {
        guard let frames = pendingBuffers.first else { return 0 }
        pendingBuffers.removeFirst()
        confirmedFrames += frames
        currentStartedAt = pendingBuffers.isEmpty ? nil : now
        return frames
    }
}
