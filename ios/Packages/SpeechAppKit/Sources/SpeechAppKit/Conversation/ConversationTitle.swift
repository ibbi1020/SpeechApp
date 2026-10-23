import Foundation

/// Gallery title for a saved conversation, from the person's own words.
public enum ConversationTitle {
    /// First six words, cut on a word boundary at 48 characters.
    /// A first word longer than 48 stays whole. No words means "Conversation".
    public static func make(userWords: [String]) -> String {
        let words = userWords.flatMap { token in
            token.split(whereSeparator: \.isWhitespace).map(String.init)
        }
        guard let first = words.first else { return "Conversation" }

        var kept = [first]
        for word in words.dropFirst().prefix(5) {
            let next = (kept + [word]).joined(separator: " ")
            if next.count > 48 { break }
            kept.append(word)
        }
        return kept.joined(separator: " ")
    }
}
