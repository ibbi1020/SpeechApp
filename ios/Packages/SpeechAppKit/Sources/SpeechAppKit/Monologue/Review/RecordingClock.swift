import Foundation

/// Maps Grok stream time onto the saved file timeline.
/// Audio (and therefore the file) advances only while the take clock is running;
/// pause gaps are cut out. Returns nil for times that fell inside a pause.
public struct RecordingClock: Sendable {
    private struct PauseGap: Sendable {
        let start: TimeInterval
        let end: TimeInterval
    }

    public private(set) var isRecording = false
    public private(set) var writtenSeconds: TimeInterval = 0

    private var takeStreamStart: TimeInterval?
    private var pauseGaps: [PauseGap] = []
    private var openPauseStart: TimeInterval?

    public init() {}

    public mutating func beginTake(atStreamTime stream: TimeInterval) {
        takeStreamStart = stream
        pauseGaps = []
        openPauseStart = nil
        writtenSeconds = 0
        isRecording = true
    }

    public mutating func pause(atStreamTime stream: TimeInterval) {
        guard isRecording, openPauseStart == nil else { return }
        openPauseStart = stream
        isRecording = false
    }

    public mutating func resume(atStreamTime stream: TimeInterval) {
        guard let pauseStart = openPauseStart else { return }
        pauseGaps.append(PauseGap(start: pauseStart, end: max(pauseStart, stream)))
        openPauseStart = nil
        isRecording = true
    }

    public mutating func appendAudio(duration: TimeInterval) {
        guard isRecording, duration > 0 else { return }
        writtenSeconds += duration
    }

    public func fileTime(forStreamTime stream: TimeInterval) -> TimeInterval? {
        guard let start = takeStreamStart else { return nil }
        if let pauseStart = openPauseStart, stream >= pauseStart {
            return nil
        }
        for gap in pauseGaps where stream >= gap.start && stream < gap.end {
            return nil
        }
        var offset = stream - start
        for gap in pauseGaps where gap.end <= stream {
            offset -= gap.end - gap.start
        }
        return max(0, offset)
    }

    /// Remap a stream-timed word onto the file timeline, or nil if it fell in a pause.
    public func recordedWord(
        surface: String,
        streamStart: TimeInterval,
        streamEnd: TimeInterval
    ) -> RecordedWord? {
        guard let start = fileTime(forStreamTime: streamStart),
              let end = fileTime(forStreamTime: streamEnd),
              end >= start
        else { return nil }
        return RecordedWord(surface: surface, start: start, end: end)
    }
}
