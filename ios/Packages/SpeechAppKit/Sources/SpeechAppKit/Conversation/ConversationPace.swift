import Foundation

/// Raw conversational pace from a grapheme vowel-nucleus count.
///
/// Heuristic (English letters only, not a pronunciation dictionary):
/// - Split the transcript on whitespace into tokens.
/// - In each token, a **nucleus** is a run of `aeiouy` (case-insensitive).
///   Consecutive vowels count as one nucleus, so "boat" is 1 not 2.
/// - A trailing `e` is treated as silent when the token already has a nucleus
///   ("make" = 1). Tokens with no vowel letters still count as 1 so hummed
///   fragments are not dropped.
/// - Pace = (nuclei × 60) / speechSeconds. Speech time is the union of user
///   speech ranges, not wall-clock including pauses.
///
/// This returns a number only. There is no target rate and no "too fast" /
/// "too slow" judgment.
public enum ConversationPace {
    public static func syllablesPerMinute(
        transcript: String,
        speechSeconds: TimeInterval
    ) -> Double? {
        guard speechSeconds > 0 else { return nil }
        let syllables = syllableCount(transcript)
        guard syllables > 0 else { return nil }
        return Double(syllables) * 60.0 / speechSeconds
    }

    public static func syllableCount(_ transcript: String) -> Int {
        let words = transcript.split { $0.isWhitespace || $0.isNewline }
        return words.reduce(0) { $0 + nuclei(in: $1) }
    }

    private static let vowels = Set("aeiouy")

    private static func nuclei(in token: Substring) -> Int {
        let letters = token.lowercased().filter(\.isLetter)
        guard !letters.isEmpty else { return 0 }
        var count = 0
        var previousWasVowel = false
        let chars = Array(letters)
        for (index, char) in chars.enumerated() {
            let isVowel = vowels.contains(char)
            if isVowel && !previousWasVowel {
                let trailingSilentE = char == "e" && index == chars.count - 1 && count > 0
                if !trailingSilentE {
                    count += 1
                }
            }
            previousWasVowel = isVowel
        }
        return max(count, 1)
    }
}
