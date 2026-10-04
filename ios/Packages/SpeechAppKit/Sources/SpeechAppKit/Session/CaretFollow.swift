import Foundation

/// Where the aligner says the reader is, on the host clock.
public struct CaretAnchor: Equatable, Sendable {
    public var index: Int
    public var speechEnd: TimeInterval?
    public var hostTime: TimeInterval

    public init(index: Int, speechEnd: TimeInterval?, hostTime: TimeInterval) {
        self.index = index
        self.speechEnd = speechEnd
        self.hostTime = hostTime
    }
}

/// Display position for the live underline.
///
/// The aligner still owns the truth index. This only decides which word to paint,
/// so a burst of words sweeps through instead of teleporting, and the mark can
/// ease one word ahead while the mic is still hot.
public struct CaretFollow: Equatable, Sendable {
    /// How long the underline takes to travel one word during a catch-up sweep.
    public static let secondsPerWord: TimeInterval = 0.1
    /// Spoken lead past the last confirmed word. Grok interims arrive about every 500 ms.
    public static let maxLead: Double = 1

    public let wordCount: Int
    public private(set) var displayPosition: Double
    public private(set) var confirmedIndex: Int
    public private(set) var wordDuration: TimeInterval

    private var anchorHostTime: TimeInterval?
    private var lastTickHost: TimeInterval?
    private var paceIndex: Int
    private var paceSpeechEnd: TimeInterval?

    public init(wordCount: Int = .max) {
        self.wordCount = wordCount
        self.displayPosition = 0
        self.confirmedIndex = 0
        self.wordDuration = 0.32
        self.paceIndex = 0
    }

    /// Whole word the underline should sit on. Fractional progress stays inside the word.
    public var displayWordIndex: Int {
        let last = max(0, wordCount - 1)
        let raw = Int(displayPosition.rounded(.down))
        return min(last, max(0, raw))
    }

    /// Record a newer aligner index. A lower index is ignored so a revised hypothesis cannot rewind the mark.
    public mutating func noteAnchor(index: Int, speechEnd: TimeInterval?, hostNow: TimeInterval) {
        let index = min(max(0, index), max(0, wordCount - 1))
        guard index >= confirmedIndex else { return }
        if index == confirmedIndex {
            if paceSpeechEnd == nil, let speechEnd {
                paceSpeechEnd = speechEnd
                paceIndex = index
            }
            return
        }
        if let speechEnd, let paceSpeechEnd, index > paceIndex {
            let words = Double(index - paceIndex)
            let span = speechEnd - paceSpeechEnd
            if words > 0, span > 0 {
                let duration = span / words
                if (0.12...0.8).contains(duration) {
                    wordDuration = duration
                }
            }
        }
        if let speechEnd {
            paceSpeechEnd = speechEnd
            paceIndex = index
        }
        confirmedIndex = index
        // Coast starts when this packet arrives, not from the word's audio time.
        // The pipeline delay is already spent; crediting it again would jump the mark.
        anchorHostTime = hostNow
    }

    /// Move the display position toward the spoken target. Returns the position after this tick.
    @discardableResult
    public mutating func tick(hostNow: TimeInterval, speaking: Bool, reduceMotion: Bool = false) -> Double {
        if speaking, anchorHostTime == nil {
            anchorHostTime = hostNow
        }
        let target = targetPosition(hostNow: hostNow, speaking: speaking)
        if reduceMotion {
            if target > displayPosition {
                displayPosition = target
            }
            lastTickHost = hostNow
            return displayPosition
        }
        guard let lastTickHost else {
            self.lastTickHost = hostNow
            return displayPosition
        }
        let dt = max(0, hostNow - lastTickHost)
        self.lastTickHost = hostNow
        // Ahead of the confirmed word during a pause: hold. Do not rewind.
        guard displayPosition < target else { return displayPosition }
        let step = dt / Self.secondsPerWord
        displayPosition = min(target, displayPosition + step)
        return displayPosition
    }

    private func targetPosition(hostNow: TimeInterval, speaking: Bool) -> Double {
        let ceiling = Double(max(0, wordCount - 1))
        let confirmed = min(Double(confirmedIndex), ceiling)
        guard speaking else { return confirmed }
        let elapsed = max(0, hostNow - (anchorHostTime ?? hostNow))
        let coast = min(Self.maxLead, elapsed / wordDuration)
        return min(confirmed + coast, ceiling)
    }
}
