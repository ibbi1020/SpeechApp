import Foundation
import Testing
@testable import SpeechAppKit

@Suite("Reading markers")
struct ReadingMarkersTests {
    private func words(_ text: String) -> [RecordedWord] {
        text.split(separator: " ").enumerated().map { index, surface in
            let start = Double(index) * 0.4
            return RecordedWord(surface: String(surface), start: start, end: start + 0.3)
        }
    }

    @Test("low-load swaps are dropped; the rest rank by functional load")
    func functionalLoadRanking() {
        let passage = Passage(id: "p", title: "p", words: [
            ScriptWord(id: "0", surface: "the", flBand: .low),
            ScriptWord(id: "1", surface: "thin", flBand: .low),
            ScriptWord(id: "2", surface: "boat", flBand: .medium),
            ScriptWord(id: "3", surface: "passed", flBand: .medium),
            ScriptWord(id: "4", surface: "the", flBand: .medium),
            ScriptWord(id: "5", surface: "ship", flBand: .high),
        ])
        let heard = words("the fin boat passed the sheep")
        let candidates = ReadingMarkers.candidates(passage: passage, words: heard)
        let swaps = candidates.filter { $0.kind == .swappedWord }
        // "fin" for low-load "thin" is dropped; "sheep" for high-load "ship" stays.
        #expect(swaps.count == 1)
        #expect(swaps.first?.note.contains("“ship”") == true)
        #expect(swaps.first?.score == 3)
    }

    @Test("a 6 s read shows only the highest-load swap")
    func capKeepsHighLoad() {
        let passage = Passage(id: "p", title: "p", words: [
            ScriptWord(id: "0", surface: "thin", flBand: .low),
            ScriptWord(id: "1", surface: "boats", flBand: .medium),
            ScriptWord(id: "2", surface: "sail", flBand: .medium),
            ScriptWord(id: "3", surface: "past", flBand: .medium),
            ScriptWord(id: "4", surface: "the", flBand: .medium),
            ScriptWord(id: "5", surface: "ship", flBand: .high),
        ])
        let markers = ReadingMarkers.build(passage: passage, words: words("fin goats sail past the sheep"), durationSeconds: 6)
        #expect(markers.count == 1)
        #expect(markers.first?.note.contains("“ship”") == true)
    }

    @Test("swap marker sits on the spoken word")
    func swapTiming() {
        let passage = Passage.plain("I saw a ship today")
        let heard = words("I saw a sheep today")
        let marker = ReadingMarkers.candidates(passage: passage, words: heard).first
        #expect(marker?.kind == .swappedWord)
        #expect(marker?.start == heard[3].start)
    }

    @Test("skip marker sits in the gap where the word should be")
    func skipTiming() {
        let passage = Passage.plain("I saw a big ship today")
        let heard = words("I saw a ship today")
        let marker = ReadingMarkers.candidates(passage: passage, words: heard).first
        #expect(marker?.kind == .skippedWord)
        #expect(marker?.start == heard[2].end)
        // At least 0.3 s long so it stays tappable, and reaches the next word.
        #expect((marker?.end ?? 0) >= heard[3].start)
    }

    @Test("clipped endings and spelling variants are not swaps")
    func lenientCases() {
        #expect(ReadingMarkers.same("sailed", "sail"))
        #expect(ReadingMarkers.same("favourite", "favorite"))
        #expect(!ReadingMarkers.same("thin", "fin"))
        #expect(!ReadingMarkers.same("ship", "sheep"))
        #expect(!ReadingMarkers.same("the", "a"))
    }
}
