import Foundation

/// One live place-marker chunk (sentence or clause) within a passage.
public struct PassageSpan: Equatable, Sendable, Codable, Identifiable {
    public let id: String
    public let wordIDs: [String]
    public let index: Int

    /// Soft clauses longer than this split further on commas.
    public static let maxWordsBeforeCommaSplit = 14

    public init(id: String, wordIDs: [String], index: Int) {
        self.id = id
        self.wordIDs = wordIDs
        self.index = index
    }

    public func syllableCount(in passage: Passage) -> Int {
        let lookup = Dictionary(uniqueKeysWithValues: passage.words.map { ($0.id, $0.syllableCount) })
        return wordIDs.reduce(0) { $0 + (lookup[$1] ?? 1) }
    }

    public func contains(wordID: String) -> Bool {
        wordIDs.contains(wordID)
    }
}

/// Pure splitter: sentence → semicolon → long-sentence commas.
public enum PassageSpanSplitter {
    private static let sentenceTerminators: Set<Character> = [".", "!", "?"]
    private static let semicolon: Character = ";"
    private static let comma: Character = ","

    public static func split(words: [ScriptWord], passageID: String) -> [PassageSpan] {
        guard !words.isEmpty else { return [] }

        let afterSentence = splitKeepingDelimiter(words) { surface in
            endsWithAny(surface, of: sentenceTerminators)
        }
        let afterSemicolon = afterSentence.flatMap { chunk in
            splitKeepingDelimiter(chunk) { surface in
                endsWith(surface, semicolon)
            }
        }
        let afterComma = afterSemicolon.flatMap { chunk in
            if chunk.count > PassageSpan.maxWordsBeforeCommaSplit {
                return splitKeepingDelimiter(chunk) { surface in
                    endsWith(surface, comma)
                }
            }
            return [chunk]
        }

        return afterComma.enumerated().map { index, chunk in
            PassageSpan(
                id: "\(passageID)-span-\(index)",
                wordIDs: chunk.map(\.id),
                index: index
            )
        }
    }

    /// Split after words whose surface ends with the delimiter; delimiter word stays in the left chunk.
    private static func splitKeepingDelimiter(
        _ words: [ScriptWord],
        endsWith: (String) -> Bool
    ) -> [[ScriptWord]] {
        var result: [[ScriptWord]] = []
        var current: [ScriptWord] = []
        for word in words {
            current.append(word)
            if endsWith(word.surface) {
                result.append(current)
                current = []
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result.isEmpty ? [words] : result
    }

    private static func endsWithAny(_ surface: String, of chars: Set<Character>) -> Bool {
        guard let last = surface.last else { return false }
        return chars.contains(last)
    }

    private static func endsWith(_ surface: String, _ char: Character) -> Bool {
        surface.last == char
    }
}
