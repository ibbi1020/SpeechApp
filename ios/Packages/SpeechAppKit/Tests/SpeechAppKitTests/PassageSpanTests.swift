import Foundation
import Testing
@testable import SpeechAppKit

@Suite("PassageSpan")
struct PassageSpanTests {
    @Test("short one-liner with no punctuation is a single span")
    func shortOneLiner() {
        let passage = PassageCatalog.makePassage(
            id: "ship-sheep-1",
            family: "ship-sheep",
            length: .short,
            title: "Harbor Morning",
            text: "The ship and the sheep share the same shore this morning",
            tags: ["ɪ-i"],
            phones: ["ɪ", "i"],
            balanced: true
        )
        #expect(passage.spans.count == 1)
        #expect(passage.spans[0].wordIDs.count == passage.words.count)
        #expect(passage.spans[0].wordIDs == passage.words.map(\.id))
    }

    @Test("medium multi-sentence passage splits on periods")
    func multiSentence() {
        let passage = PassageCatalog.makePassage(
            id: "ship-sheep-2",
            family: "ship-sheep",
            length: .medium,
            title: "Harbor Morning",
            text: "The ship left the harbor before the sheep were led to the shore. She still hears the sheep bleat as the ship slips past the reef. If you say ship for sheep or sheep for ship a listener can lose the meaning of the story.",
            tags: ["ɪ-i"],
            phones: ["ɪ", "i"],
            balanced: false
        )
        #expect(passage.spans.count == 3)
        #expect(passage.spans[0].wordIDs.count == 13)
        #expect(passage.spans[1].wordIDs.count == 13)
        #expect(passage.spans[2].wordIDs.count == 19)
        // All word IDs covered exactly once, in order
        #expect(passage.spans.flatMap(\.wordIDs) == passage.words.map(\.id))
    }

    @Test("semicolon splits into separate spans")
    func semicolonSplit() {
        let passage = PassageCatalog.makePassage(
            id: "semi",
            family: "semi",
            length: .medium,
            title: "Semicolon",
            text: "On the left a large red lantern glowed; on the right a row of low houses reflected in the water.",
            tags: [],
            phones: [],
            balanced: false
        )
        #expect(passage.spans.count == 2)
        #expect(passage.spans[0].wordIDs.count == 8)
        #expect(passage.spans[1].wordIDs.count == 12)
    }

    @Test("long sentence over 14 words splits on commas")
    func longSentenceCommaSplit() {
        // 16 words with one comma mid-way — must split because > 14
        let text = "A child points at the sheep then at the ship and laughs, because the two words sound almost the same in her mind."
        let passage = PassageCatalog.makePassage(
            id: "long-comma",
            family: "long-comma",
            length: .long,
            title: "Long comma",
            text: text,
            tags: [],
            phones: [],
            balanced: false
        )
        #expect(passage.spans.count >= 2)
        #expect(passage.spans.allSatisfy { $0.wordIDs.count <= PassageSpan.maxWordsBeforeCommaSplit })
        #expect(passage.spans.flatMap(\.wordIDs) == passage.words.map(\.id))
    }

    @Test("spanIndex(forWordID:) maps words to spans")
    func spanIndexLookup() {
        let passage = PassageCatalog.makePassage(
            id: "two",
            family: "two",
            length: .medium,
            title: "Two",
            text: "First sentence here. Second sentence here.",
            tags: [],
            phones: [],
            balanced: false
        )
        #expect(passage.spans.count == 2)
        #expect(passage.spanIndex(forWordID: passage.words[0].id) == 0)
        #expect(passage.spanIndex(forWordID: passage.words.last!.id) == 1)
        #expect(passage.spanIndex(forWordID: "missing") == nil)
    }

    @Test("syllableCount sums word syllables in the span")
    func syllableSum() {
        let passage = Passage(
            id: "syl",
            title: "Syl",
            words: [
                ScriptWord(id: "a", surface: "the", syllableCount: 1),
                ScriptWord(id: "b", surface: "ship", syllableCount: 1),
                ScriptWord(id: "c", surface: "sails.", syllableCount: 1),
            ]
        )
        #expect(passage.spans.count == 1)
        #expect(passage.spans[0].syllableCount(in: passage) == 3)
    }
}
