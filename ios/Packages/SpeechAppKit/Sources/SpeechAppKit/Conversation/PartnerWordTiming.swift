import Foundation

/// Lays a finished partner line across the seconds it actually played.
///
/// The realtime API sends one transcript and a PCM stream, not word times.
/// Character length is the stand-in: a longer word takes more of the turn.
public enum PartnerWordTiming {
    public static func words(text: String, start: TimeInterval, end: TimeInterval) -> [RecordedWord] {
        let parts = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let span = end - start
        guard !parts.isEmpty, span > 0 else { return [] }
        let total = parts.reduce(0) { $0 + $1.count }
        guard total > 0 else { return [] }

        var cursor = start
        var out: [RecordedWord] = []
        out.reserveCapacity(parts.count)
        for (index, surface) in parts.enumerated() {
            let isLast = index == parts.count - 1
            let next = isLast ? end : cursor + span * Double(surface.count) / Double(total)
            out.append(RecordedWord(surface: surface, start: cursor, end: next, isFiller: false))
            cursor = next
        }
        return out
    }
}
