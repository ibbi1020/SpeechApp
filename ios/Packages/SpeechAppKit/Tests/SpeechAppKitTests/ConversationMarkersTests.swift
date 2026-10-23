import Foundation
import Testing
@testable import SpeechAppKit

@Suite("Conversation markers")
struct ConversationMarkersTests {
    @Test("words heard while the partner plays are echo, not the user")
    func echoDropped() {
        let turns = [PartnerTurn(text: "Where do you work?", start: 0, end: 2)]
        let words = [
            RecordedWord(surface: "work", start: 1.2, end: 1.5),
            RecordedWord(surface: "At", start: 2.6, end: 2.8),
            RecordedWord(surface: "home", start: 2.9, end: 3.2),
        ]
        #expect(ConversationMarkers.userWords(words, partnerTurns: turns).map(\.surface) == ["At", "home"])
    }

    @Test("slow start sits between the partner's end and the first word")
    func slowStartSpan() {
        let turns = [PartnerTurn(text: "Where do you work?", start: 0, end: 2)]
        let words = [RecordedWord(surface: "At", start: 5, end: 5.2)]
        let marker = ConversationMarkers.candidates(words: words, partnerTurns: turns, durationSeconds: 60).first
        #expect(marker?.kind == .slowStart)
        #expect(marker?.start == 2)
        #expect(marker?.end == 5)
    }

    @Test("long questions are shortened in the note")
    func longQuestion() {
        let question = String(repeating: "word ", count: 30)
        let note = ConversationMarkers.slowStartNote(seconds: 3, question: question)
        #expect(note.contains("…"))
        #expect(note.contains("3 seconds"))
    }

    @Test("other-language span becomes a candidate with the ask note")
    func otherLanguageCandidate() {
        let turns = [PartnerTurn(text: "What do you do?", start: 0, end: 2)]
        var words: [RecordedWord] = []
        let spanish = ["Pero", "a", "veces", "prefiero", "quedarme", "en", "casa"]
        for (index, surface) in spanish.enumerated() {
            let start = 2.5 + Double(index) * 0.4
            words.append(RecordedWord(surface: surface, start: start, end: start + 0.3))
        }
        let found = ConversationMarkers.candidates(words: words, partnerTurns: turns, durationSeconds: 60)
        let slip = found.first { $0.kind == .otherLanguage }
        #expect(slip != nil)
        #expect(slip?.note == ConversationMarkers.otherLanguageNote)
        #expect(slip?.score ?? 0 > 1)
    }

    @Test("live slips still count when STT arrives after the partner has already replied")
    func liveSlipAfterPartnerReply() {
        // Open (0–2), user Spanish (2.5–5), partner continue (5.5–10). Finals land late.
        let turns = [
            PartnerTurn(text: "What do you do?", start: 0, end: 2),
            PartnerTurn(text: "Nice.", start: 5.5, end: 10),
        ]
        var words: [RecordedWord] = []
        let spanish = ["Pero", "a", "veces", "prefiero", "quedarme", "en", "casa"]
        for (index, surface) in spanish.enumerated() {
            let start = 2.5 + Double(index) * 0.4
            words.append(RecordedWord(surface: surface, start: start, end: start + 0.3))
        }
        let slips = ConversationMarkers.liveOtherLanguageSlips(
            words: words,
            partnerTurns: turns,
            alreadyNotified: []
        )
        #expect(slips.count == 1)
        #expect(slips[0].index == 1)
        #expect(slips[0].end > 2.5)

        let again = ConversationMarkers.liveOtherLanguageSlips(
            words: words,
            partnerTurns: turns,
            alreadyNotified: [slips[0].index]
        )
        #expect(again.isEmpty)
    }
}
