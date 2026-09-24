import Foundation

/// Token-set Jaccard × 100. Descriptive overlap, not originality.
public enum MonologueOverlap {
    public static func tokenPercent(previous: String, current: String) -> Double? {
        let a = Set(tokens(previous))
        let b = Set(tokens(current))
        if a.isEmpty && b.isEmpty { return nil }
        let union = a.union(b)
        guard !union.isEmpty else { return nil }
        return 100.0 * Double(a.intersection(b).count) / Double(union.count)
    }

    public static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .split { $0.isWhitespace || $0.isNewline }
            .map(String.init)
    }
}
