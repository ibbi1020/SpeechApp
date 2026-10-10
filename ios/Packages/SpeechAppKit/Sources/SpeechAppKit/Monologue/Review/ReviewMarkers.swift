import Foundation

public struct ReviewMarker: Equatable, Hashable, Sendable, Codable, Identifiable {
    public enum Kind: String, Equatable, Hashable, Sendable, Codable {
        case pause
        case fillerCluster
        case restart
    }

    public let id: UUID
    public let kind: Kind
    public let start: TimeInterval
    public let end: TimeInterval
    public let score: TimeInterval
    public let note: String

    public init(
        id: UUID = UUID(),
        kind: Kind,
        start: TimeInterval,
        end: TimeInterval,
        score: TimeInterval,
        note: String
    ) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.score = score
        self.note = note
    }
}

public enum ReviewMarkers {
    public static let minimumPause: TimeInterval = 1.5
    /// Grok word edges sit inside the sound, so the gap between two words reads
    /// about 0.2 s longer than the real silence (eval: 1.0 s → 1.2 s, 1.3 s → 1.51 s).
    public static let wordEdgePadding: TimeInterval = 0.2
    /// Gap between two words that means a real 1.5 s silence.
    public static var minimumWordGap: TimeInterval { minimumPause + wordEdgePadding }
    /// Word times are hundredths; subtraction like 2.9 − 1.2 lands just under 1.7.
    static let timeSlack: TimeInterval = 0.001
    public static let fillerClusterWindow: TimeInterval = 6.0
    public static let minimumFillerCount = 2
    /// Markers closer than this fraction of take length collide; keep the higher score.
    public static let spacingFraction: Double = 0.13

    public static func maxMarkers(durationSeconds: TimeInterval) -> Int {
        let minutes = max(0, durationSeconds) / 60.0
        let raw = (3.0 * sqrt(minutes)).rounded()
        return max(0, min(7, Int(raw)))
    }

    public static func build(
        words: [RecordedWord],
        durationSeconds: TimeInterval
    ) -> [ReviewMarker] {
        let cap = maxMarkers(durationSeconds: durationSeconds)
        guard cap > 0, durationSeconds > 0 else { return [] }

        var candidates = candidates(words: words, durationSeconds: durationSeconds)
        candidates.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.start < rhs.start
        }

        let minSpacing = durationSeconds * spacingFraction
        var selected: [ReviewMarker] = []
        for candidate in candidates {
            if selected.count >= cap { break }
            let collides = selected.contains { abs($0.start - candidate.start) < minSpacing }
            if !collides {
                selected.append(candidate)
            }
        }
        return selected.sorted { $0.start < $1.start }
    }

    /// Every detected moment before the cap and spacing pick which ones to show.
    public static func candidates(
        words: [RecordedWord],
        durationSeconds: TimeInterval
    ) -> [ReviewMarker] {
        var found: [ReviewMarker] = []
        found.append(contentsOf: pauseMarkers(words: words, durationSeconds: durationSeconds))
        found.append(contentsOf: fillerClusterMarkers(words: words))
        for restart in RestartDetector.find(in: words) {
            found.append(
                ReviewMarker(
                    kind: .restart,
                    start: restart.start,
                    end: restart.end,
                    score: restart.score,
                    note: note(for: .restart, score: restart.score, end: restart.end, start: restart.start)
                )
            )
        }
        return found.sorted { $0.start < $1.start }
    }

    // MARK: - Pauses

    private static func pauseMarkers(words: [RecordedWord], durationSeconds: TimeInterval) -> [ReviewMarker] {
        _ = durationSeconds
        let ordered = words.sorted { $0.start < $1.start }
        var markers: [ReviewMarker] = []

        // Leading silence (before first word) can be a marker.
        if let first = ordered.first, first.start >= minimumPause - timeSlack {
            markers.append(
                ReviewMarker(
                    kind: .pause,
                    start: 0,
                    end: first.start,
                    score: first.start,
                    note: note(for: .pause, score: first.start, end: first.start, start: 0)
                )
            )
        }

        // Between words only — trailing silence after the last word does not count.
        for index in 0..<(max(0, ordered.count - 1)) {
            let gapStart = ordered[index].end
            let gapEnd = ordered[index + 1].start
            let length = gapEnd - gapStart
            guard length >= minimumWordGap - timeSlack else { continue }
            // Score and wording use the real silence, not the padded word gap.
            let silence = length - wordEdgePadding
            markers.append(
                ReviewMarker(
                    kind: .pause,
                    start: gapStart,
                    end: gapEnd,
                    score: silence,
                    note: note(for: .pause, score: silence, end: gapEnd, start: gapStart)
                )
            )
        }
        return markers
    }

    // MARK: - Filler clusters

    private static func fillerClusterMarkers(words: [RecordedWord]) -> [ReviewMarker] {
        let fillers = words.filter(\.isFiller).sorted { $0.start < $1.start }
        guard fillers.count >= minimumFillerCount else { return [] }

        var markers: [ReviewMarker] = []
        var i = 0
        while i < fillers.count {
            var j = i
            while j + 1 < fillers.count,
                  fillers[j + 1].start - fillers[i].start <= fillerClusterWindow + timeSlack
            {
                j += 1
            }
            let count = j - i + 1
            if count >= minimumFillerCount {
                let start = fillers[i].start
                let end = fillers[j].end
                let score = max(0, end - start)
                markers.append(
                    ReviewMarker(
                        kind: .fillerCluster,
                        start: start,
                        end: end,
                        score: score,
                        note: fillerNote(count: count, seconds: score)
                    )
                )
                i = j + 1
            } else {
                i += 1
            }
        }
        return markers
    }

    // MARK: - Copy

    public static func note(
        for kind: ReviewMarker.Kind,
        score: TimeInterval,
        end: TimeInterval,
        start: TimeInterval
    ) -> String {
        switch kind {
        case .pause:
            let seconds = Int(score.rounded())
            return "A \(seconds)-second pause. Listen: were you looking for a word, or your next point?"
        case .fillerCluster:
            return fillerNote(count: 2, seconds: score)
        case .restart:
            return "You started this part again. Listen: did the second try say it better?"
        }
    }

    private static func fillerNote(count: Int, seconds: TimeInterval) -> String {
        let secs = max(1, Int(seconds.rounded()))
        return "\(count) fillers in \(secs) seconds. Listen: what were you about to say?"
    }
}
