import Foundation
import Testing
@testable import SpeechAppKit

@Suite("Language span detector")
struct LanguageSpanDetectorTests {
    @Test("sustained Spanish is a qualifying span")
    func spanishSpan() {
        let words = timed(
            "Pero", "a", "veces", "prefiero", "quedarme", "en", "casa"
        )
        let spans = LanguageSpanDetector.spans(in: words)
        #expect(spans.count == 1)
        #expect(spans[0].wordCount >= 3)
        #expect(spans[0].start == words.first?.start)
        #expect(spans[0].end == words.last?.end)
    }

    @Test("English answer has no span")
    func englishClean() {
        let words = timed("Usually", "I", "go", "hiking", "with", "my", "friends")
        #expect(LanguageSpanDetector.spans(in: words).isEmpty)
    }

    @Test("a single loanword is not a switch")
    func singleLoanword() {
        let words = timed("I", "had", "a", "taco", "yesterday")
        #expect(LanguageSpanDetector.spans(in: words).isEmpty)
    }

    @Test("Urdu script counts without NL")
    func urduScript() {
        let words = timed("میں", "گھر", "جانا", "چاہتا", "ہوں")
        let spans = LanguageSpanDetector.spans(in: words)
        #expect(spans.count == 1)
        #expect(spans[0].wordCount >= 3)
    }

    @Test("fillers alone are not a language switch")
    func fillersIgnored() {
        let words = [
            RecordedWord(surface: "um", start: 0, end: 0.3),
            RecordedWord(surface: "uh", start: 0.4, end: 0.7),
            RecordedWord(surface: "um", start: 0.8, end: 1.1),
        ]
        #expect(LanguageSpanDetector.spans(in: words).isEmpty)
    }

    @Test("romanised Urdu is a span even though NL cannot name the language")
    func romanisedUrdu() {
        // Grok writes Urdu in Latin letters when the stream is English-dominant.
        // NLLanguageRecognizer guesses Italian/Swedish/German here at low confidence,
        // so naming the language cannot be the test — only "this is not English" can.
        let words = timed("mujhe", "ghar", "par", "rehna", "pasand", "hai")
        let spans = LanguageSpanDetector.spans(in: words)
        #expect(spans.count == 1)
        #expect(spans.first?.wordCount ?? 0 >= 3)
    }

    @Test("romanised Urdu mid-answer after English is marked")
    func romanisedUrduMidAnswer() {
        let words = timed(
            "On", "Sunday", "I", "went", "out",
            "main", "soch", "raha", "tha", "ke",
            "with", "my", "sister"
        )
        #expect(!LanguageSpanDetector.spans(in: words).isEmpty)
    }

    @Test("a loanword inside an English answer is not a switch")
    func loanwordInEnglish() {
        // "we cook daal" reads as non-English on its own; the words around it do not.
        let words = timed("we", "cook", "daal", "and", "rice", "on", "Sunday")
        #expect(LanguageSpanDetector.spans(in: words).isEmpty)
    }

    @Test("learner English with grammar mistakes is not a switch")
    func accentedEnglishClean() {
        let words = timed("I", "am", "go", "to", "market", "yesterday", "I", "eating", "rice")
        #expect(LanguageSpanDetector.spans(in: words).isEmpty)
    }

    @Test("Spanish mid-answer after English is marked")
    func mixedAnswer() {
        let words = timed(
            "I", "work", "and",
            "pero", "a", "veces", "prefiero", "quedarme", "en", "casa",
            "near", "home"
        )
        let spans = LanguageSpanDetector.spans(in: words)
        #expect(spans.count >= 1)
        #expect(spans[0].wordCount >= 3)
    }

    private func timed(_ surfaces: String...) -> [RecordedWord] {
        surfaces.enumerated().map { index, surface in
            let start = Double(index) * 0.4
            return RecordedWord(surface: surface, start: start, end: start + 0.3)
        }
    }
}
