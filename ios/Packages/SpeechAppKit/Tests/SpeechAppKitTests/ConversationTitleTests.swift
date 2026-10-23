import Testing
@testable import SpeechAppKit

@Suite("Conversation title")
struct ConversationTitleTests {
    @Test("empty words become Conversation")
    func empty() {
        #expect(ConversationTitle.make(userWords: []) == "Conversation")
    }

    @Test("whitespace-only words become Conversation")
    func whitespace() {
        #expect(ConversationTitle.make(userWords: ["   ", "\n", "\t"]) == "Conversation")
    }

    @Test("keeps three words")
    func keepsThreeWords() {
        #expect(ConversationTitle.make(userWords: ["I", "went", "home"]) == "I went home")
    }

    @Test("drops the seventh word")
    func dropsSeventhWord() {
        #expect(
            ConversationTitle.make(userWords: ["one", "two", "three", "four", "five", "six", "seven"])
                == "one two three four five six"
        )
    }

    @Test("stops on a word boundary past 48 characters")
    func stopsOnWordBoundary() {
        // Four words are 43 characters. A fifth word would be 54, so it is dropped whole.
        let words = ["aaaaabbbbb", "cccccddddd", "eeeeeefggg", "hhhhhhiiii", "jjjjjjkkkk", "llllllmmmm"]
        let title = ConversationTitle.make(userWords: words)
        #expect(title == "aaaaabbbbb cccccddddd eeeeeefggg hhhhhhiiii")
        #expect(title.count == 43)
        #expect(!title.contains("jjjjjj"))
    }

    @Test("keeps a single long word whole")
    func keepsSingleLongWord() {
        let word = String(repeating: "z", count: 60)
        #expect(ConversationTitle.make(userWords: [word]) == word)
        #expect(ConversationTitle.make(userWords: [word, "more"]) == word)
    }

    @Test("collapses double spaces")
    func collapsesDoubleSpaces() {
        #expect(ConversationTitle.make(userWords: ["I  went", "  home"]) == "I went home")
    }
}
