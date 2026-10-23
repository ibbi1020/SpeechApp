import Foundation

/// Filled pauses that Grok returns when `filler_words=true`.
/// Kept in review transcripts/markers; stripped before Reading alignment and
/// Monologue overlap / pace so existing report numbers stay stable.
public enum FillerWords {
    public static let surfaces: Set<String> = ["uh", "um", "er", "uhm", "umm", "ah"]

    public static func isFiller(_ surface: String) -> Bool {
        surfaces.contains(ScriptWord.normalize(surface))
    }

    public static func strippingTokens(_ tokens: [SpokenToken]) -> [SpokenToken] {
        tokens.filter { !isFiller($0.surface) }
    }

    /// Drop filler tokens from a whitespace-split transcript (keeps punctuation on other words).
    public static func strippingTranscript(_ text: String) -> String {
        text
            .split { $0.isWhitespace || $0.isNewline }
            .map(String.init)
            .filter { !isFiller($0) }
            .joined(separator: " ")
    }
}
