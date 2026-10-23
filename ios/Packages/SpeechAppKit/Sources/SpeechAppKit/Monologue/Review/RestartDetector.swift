import Foundation

/// Same 1–3 words said again right away ("I went, I went to").
public enum RestartDetector {
    /// Single words that English repeats on purpose: emphasis ("very very good",
    /// "no no") and grammar ("that that", "had had"). Repeating one of these is not a restart.
    public static let intendedDoubles: Set<String> = [
        "very", "really", "so", "much", "many", "more", "too", "far", "way", "long",
        "big", "little", "bye", "no", "yes", "yeah", "okay", "ok", "ha", "hey", "please",
        "that", "had",
    ]

    public struct Candidate: Equatable, Sendable {
        public let start: TimeInterval
        public let end: TimeInterval
        public let score: TimeInterval
        public let repeatedSurfaces: [String]

        public init(start: TimeInterval, end: TimeInterval, score: TimeInterval, repeatedSurfaces: [String]) {
            self.start = start
            self.end = end
            self.score = score
            self.repeatedSurfaces = repeatedSurfaces
        }
    }

    public static func find(in words: [RecordedWord]) -> [Candidate] {
        let content = words.filter { !$0.isFiller }
        guard content.count >= 2 else { return [] }
        var found: [Candidate] = []
        var i = 0
        while i < content.count {
            var matched = false
            for n in [3, 2, 1] {
                guard i + 2 * n <= content.count else { continue }
                let first = Array(content[i..<(i + n)])
                let second = Array(content[(i + n)..<(i + 2 * n)])
                let a = first.map { ScriptWord.normalize($0.surface) }
                let b = second.map { ScriptWord.normalize($0.surface) }
                guard a == b, a.allSatisfy({ !$0.isEmpty }) else { continue }
                if n == 1, intendedDoubles.contains(a[0]) { continue }
                // "Right away": gap between the two copies under 1.5s.
                let gap = second.first!.start - first.last!.end
                guard gap >= 0, gap <= 1.5 else { continue }
                let start = first.first!.start
                let end = second.last!.end
                found.append(
                    Candidate(
                        start: start,
                        end: end,
                        score: max(0, end - start),
                        repeatedSurfaces: first.map(\.surface)
                    )
                )
                i += 2 * n
                matched = true
                break
            }
            if !matched { i += 1 }
        }
        return found
    }
}
