import Foundation
import Testing
@testable import SpeechAppKit

@Suite("Partner word timing")
struct PartnerWordTimingTests {
    @Test("words cover the turn and a longer word takes more time")
    func characterLength() {
        let words = PartnerWordTiming.words(text: "Hi there", start: 0, end: 7)
        #expect(words.map(\.surface) == ["Hi", "there"])
        #expect(words[0].start == 0)
        #expect(words[0].end == 2)
        #expect(words[1].start == 2)
        #expect(words[1].end == 7)
        #expect(words[1].duration > words[0].duration)
    }

    @Test("empty text yields nothing")
    func empty() {
        #expect(PartnerWordTiming.words(text: "", start: 0, end: 2).isEmpty)
        #expect(PartnerWordTiming.words(text: "   ", start: 0, end: 2).isEmpty)
        #expect(PartnerWordTiming.words(text: "Hi", start: 1, end: 1).isEmpty)
    }

    @Test("old partner turns without word times still decode")
    func oldTurnDecodes() throws {
        let json = #"{"text":"Hi","start":0,"end":1}"#
        let turn = try JSONDecoder().decode(PartnerTurn.self, from: Data(json.utf8))
        #expect(turn.text == "Hi")
        #expect(turn.words == nil)
    }

    @Test("partner words timed onto the turn are not user speech")
    func partnerWordsAreNotUserSpeech() {
        let timed = PartnerWordTiming.words(text: "Where do you work", start: 0, end: 2)
        let turn = PartnerTurn(text: "Where do you work", start: 0, end: 2, words: timed)
        let user = [RecordedWord(surface: "At", start: 2.6, end: 2.8)]
        let mixed = timed + user
        let kept = ConversationMarkers.userWords(mixed, partnerTurns: [turn])
        #expect(kept.map(\.surface) == ["At"])
        let markers = ConversationMarkers.candidates(
            words: user,
            partnerTurns: [turn],
            durationSeconds: 10
        )
        #expect(markers.allSatisfy { $0.start >= 2 })
    }
}
