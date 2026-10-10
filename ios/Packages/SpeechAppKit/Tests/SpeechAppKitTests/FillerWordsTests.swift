import Testing
@testable import SpeechAppKit

@Suite("Filler words")
struct FillerWordsTests {
    @Test("detects uh um er with punctuation")
    func detects() {
        #expect(FillerWords.isFiller("um"))
        #expect(FillerWords.isFiller("Um,"))
        #expect(FillerWords.isFiller("UH"))
        #expect(FillerWords.isFiller("er."))
        #expect(FillerWords.isFiller("ah"))
        #expect(!FillerWords.isFiller("umbrella"))
        #expect(!FillerWords.isFiller("went"))
    }

    @Test("strips fillers from transcript text")
    func stripsTranscript() {
        let cleaned = FillerWords.strippingTranscript("I um went uh to the store")
        #expect(cleaned == "I went to the store")
    }

    @Test("strips fillers from spoken tokens")
    func stripsTokens() {
        let tokens = [
            SpokenToken(surface: "I"),
            SpokenToken(surface: "um"),
            SpokenToken(surface: "went"),
        ]
        let kept = FillerWords.strippingTokens(tokens).map(\.surface)
        #expect(kept == ["I", "went"])
    }
}
