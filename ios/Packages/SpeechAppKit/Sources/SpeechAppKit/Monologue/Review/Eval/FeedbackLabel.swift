import Foundation

/// A moment a person marked by hand (or a script planted) in a test clip.
public struct FeedbackLabel: Codable, Equatable, Sendable {
    public enum Expectation: String, Codable, Sendable {
        /// Should be one of the markers the player shows.
        case marker
        /// Should be detected, but the cap or spacing may hide it.
        case candidate
        /// Should not be flagged (for example a natural breath pause).
        case none
    }

    public let kind: ReviewMarker.Kind
    public let start: TimeInterval
    public let end: TimeInterval
    public let expect: Expectation
    public let note: String?

    public init(
        kind: ReviewMarker.Kind,
        start: TimeInterval,
        end: TimeInterval,
        expect: Expectation = .marker,
        note: String? = nil
    ) {
        self.kind = kind
        self.start = start
        self.end = end
        self.expect = expect
        self.note = note
    }

    private enum CodingKeys: String, CodingKey {
        case kind, start, end, expect, note
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(ReviewMarker.Kind.self, forKey: .kind)
        start = try container.decode(TimeInterval.self, forKey: .start)
        end = try container.decode(TimeInterval.self, forKey: .end)
        expect = try container.decodeIfPresent(Expectation.self, forKey: .expect) ?? .marker
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }
}

extension FeedbackLabel {
    /// Audacity label track export: `start<TAB>end<TAB>text`, one per line.
    /// Text is `pause`, `fillers`, or `restart`. Add ` maybe` for "fine if the cap hides it";
    /// start with `not ` for "should not be flagged" (`not pause`).
    public static func parseAudacity(_ text: String) -> [FeedbackLabel] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count >= 3,
                  let start = TimeInterval(parts[0]),
                  let end = TimeInterval(parts[1])
            else { return nil }
            var words = parts[2].lowercased().split(separator: " ").map(String.init)
            var expect = Expectation.marker
            if words.first == "not" {
                expect = .none
                words.removeFirst()
            }
            if words.last == "maybe" {
                expect = .candidate
                words.removeLast()
            }
            guard let kindWord = words.first, let kind = kindFromWord(kindWord) else { return nil }
            let note = parts.count > 3 ? parts[3] : nil
            return FeedbackLabel(kind: kind, start: start, end: end, expect: expect, note: note)
        }
    }

    static func kindFromWord(_ word: String) -> ReviewMarker.Kind? {
        switch word {
        case "pause", "silence": .pause
        case "fillers", "filler", "fillercluster": .fillerCluster
        case "restart", "repeat": .restart
        case "skip", "skipped": .skippedWord
        case "swap", "swapped": .swappedWord
        case "slowstart", "slow-start", "turnstart": .slowStart
        default: nil
        }
    }
}
