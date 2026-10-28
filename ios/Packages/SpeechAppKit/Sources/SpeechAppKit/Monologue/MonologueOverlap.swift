import Foundation

/// How much of this take repeats a stretch already said in the previous take.
/// A stretch is three or more words in the same order. Shared word types in a
/// new order do not count.
public enum MonologueOverlap {
    public static func verbatimPercent(previous: String, current: String) -> Double? {
        let earlier = tokens(previous)
        let later = tokens(current)
        if earlier.isEmpty || later.isEmpty { return nil }
        guard earlier.count >= 3, later.count >= 3 else { return 0 }

        var reused = Array(repeating: false, count: later.count)
        var index = 0
        while index < later.count {
            let matched = longestRepeat(of: later, from: index, in: earlier)
            if matched >= 3 {
                for offset in 0..<matched {
                    reused[index + offset] = true
                }
                index += matched
            } else {
                index += 1
            }
        }
        return 100.0 * Double(reused.filter { $0 }.count) / Double(later.count)
    }

    public static func tokens(_ text: String) -> [String] {
        FillerWords.strippingTranscript(text)
            .lowercased()
            .split { $0.isWhitespace || $0.isNewline }
            .map { ScriptWord.normalize(String($0)) }
            .filter { !$0.isEmpty }
    }

    private static func longestRepeat(of later: [String], from index: Int, in earlier: [String]) -> Int {
        let room = min(later.count - index, earlier.count)
        guard room >= 3 else { return 0 }
        for length in stride(from: room, through: 3, by: -1) {
            let needle = Array(later[index..<(index + length)])
            if contains(needle, in: earlier) { return length }
        }
        return 0
    }

    private static func contains(_ needle: [String], in haystack: [String]) -> Bool {
        guard needle.count <= haystack.count else { return false }
        let last = haystack.count - needle.count
        for start in 0...last {
            if Array(haystack[start..<(start + needle.count)]) == needle { return true }
        }
        return false
    }
}
