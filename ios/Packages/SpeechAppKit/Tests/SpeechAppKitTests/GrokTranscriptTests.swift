import Foundation
import Testing
@testable import SpeechAppKit

@Suite("Grok transcript stitch")
struct GrokTranscriptTests {
    @Test("chunk finals stay when the utterance final is only the tail")
    func appendsWhenSpeechFinalDropsChunks() {
        var stitcher = GrokTranscriptStitcher()
        let chunk = stitcher.apply(
            GrokPartialEvent(text: "the ship", isFinal: true, speechFinal: false)
        )
        #expect(chunk?.tokens.filter(\.isFinal).map(\.surface) == ["the", "ship"])

        let utterance = stitcher.apply(
            GrokPartialEvent(text: "sailed", isFinal: true, speechFinal: true)
        )
        #expect(utterance?.tokens.filter(\.isFinal).map(\.surface) == ["sailed"])
        #expect(utterance?.rawText == "the ship sailed")
    }

    @Test("utterance final that already includes chunks emits only the new words")
    func suffixOnlyWhenSpeechFinalIncludesChunks() {
        var stitcher = GrokTranscriptStitcher()
        _ = stitcher.apply(GrokPartialEvent(text: "the ship", isFinal: true, speechFinal: false))
        let utterance = stitcher.apply(
            GrokPartialEvent(
                text: "the ship sailed",
                isFinal: true,
                speechFinal: true,
                words: [
                    GrokTimedWord(text: "the", start: 0.0, end: 0.2),
                    GrokTimedWord(text: "ship", start: 0.2, end: 0.5),
                    GrokTimedWord(text: "sailed", start: 0.5, end: 0.9),
                ]
            )
        )
        let finals = utterance?.tokens.filter(\.isFinal) ?? []
        #expect(finals.map(\.surface) == ["sailed"])
        #expect(finals.first?.startTime == 0.5)
        #expect(finals.first?.endTime == 0.9)
        #expect(utterance?.rawText == "the ship sailed")
    }

    @Test("chunk-relative word times shift onto the stream clock")
    func shiftsRelativeWordTimes() {
        let words = [
            GrokTimedWord(text: "ship", start: 1, end: 1.5)
        ]
        let shifted = GrokTranscriptStitcher.absoluteWords(words, segmentStart: 12)
        #expect(shifted.first?.start == 13)
        #expect(shifted.first?.end == 13.5)
        let already = GrokTranscriptStitcher.absoluteWords(words, segmentStart: 0)
        #expect(already.first?.start == 1)
    }

    @Test("interim text is volatile and can change")
    func interimIsVolatile() {
        var stitcher = GrokTranscriptStitcher()
        let first = stitcher.apply(
            GrokPartialEvent(text: "the sheep", isFinal: false, speechFinal: false)
        )
        #expect(first?.tokens.allSatisfy { !$0.isFinal } == true)
        #expect(first?.rawText == "the sheep")

        let second = stitcher.apply(
            GrokPartialEvent(text: "the ship", isFinal: false, speechFinal: false)
        )
        #expect(second?.tokens.map(\.surface) == ["the", "ship"])
        #expect(second?.tokens.allSatisfy { !$0.isFinal } == true)
        #expect(second?.rawText == "the ship")
    }
}

@Suite("PCM16 frames")
struct PCM16FrameBufferTests {
    @Test("100 ms at 16 kHz is 3200 bytes")
    func nativeRateFrame() {
        var buffer = PCM16FrameBuffer()
        let frames = buffer.append(samples: Array(repeating: 0.5, count: 1_600), sampleRate: 16_000)
        #expect(frames.count == 1)
        #expect(frames[0].count == PCM16FrameBuffer.bytesPerFrame)
    }

    @Test("shorter than 100 ms waits until flush")
    func holdsPartialFrame() {
        var buffer = PCM16FrameBuffer()
        let early = buffer.append(samples: Array(repeating: 0.25, count: 800), sampleRate: 16_000)
        #expect(early.isEmpty)
        let tail = buffer.flush()
        #expect(tail.count == 1)
        #expect(tail[0].count == 1_600)
    }
}

@Suite("Grok relay URL")
struct GrokRelayURLTests {
    @Test("http base becomes the local stt socket with keyterms")
    func buildsWebSocketURL() {
        let base = URL(string: "http://mac.local:8787")!
        let url = GrokTranscriptionEngine.webSocketURL(httpBase: base, keyterms: ["ship", "sheep"])
        let parts = URLComponents(url: url!, resolvingAgainstBaseURL: false)
        #expect(parts?.scheme == "ws")
        #expect(parts?.host == "mac.local")
        #expect(parts?.port == 8787)
        #expect(parts?.path == "/v1/stt")
        #expect(parts?.queryItems?.map(\.value) == ["ship", "sheep"])
    }
}
