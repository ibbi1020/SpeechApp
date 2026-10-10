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
}
