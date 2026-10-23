import Foundation
import Testing
@testable import SpeechAppKit

@Suite("Listen-back mix")
struct ListenBackMixTests {
    @Test("quiet mic under the partner becomes the partner tone")
    func quietStretchTakesPartner() {
        let mic = [Float](repeating: 0, count: 100)
        let span = PartnerAudioSpan(
            start: 0.25,
            sampleRate: 100,
            samples: [Float](repeating: 0.5, count: 50)
        )
        let mixed = ListenBackMix.mix(mic: mic, micRate: 100, spans: [span], timelineShift: 0)
        #expect(mixed[0..<25].allSatisfy { $0 == 0 })
        #expect(mixed[25..<75].allSatisfy { $0 == 0.5 })
        #expect(mixed[75..<100].allSatisfy { $0 == 0 })
    }

    @Test("a loud mic stretch stays the speaker")
    func loudMicStays() {
        let mic = [Float](repeating: 0.8, count: 100)
        let span = PartnerAudioSpan(
            start: 0.2,
            sampleRate: 100,
            samples: [Float](repeating: 0.2, count: 40)
        )
        let mixed = ListenBackMix.mix(mic: mic, micRate: 100, spans: [span], timelineShift: 0)
        #expect(mixed.allSatisfy { abs($0 - 0.8) < 0.0001 })
    }

    @Test("a loud burst inside a partner stretch stays the mic")
    func bargeInStays() {
        var mic = [Float](repeating: 0, count: 100)
        for i in 40..<70 { mic[i] = 0.8 }
        let span = PartnerAudioSpan(
            start: 0.1,
            sampleRate: 100,
            samples: [Float](repeating: 0.4, count: 80)
        )
        let mixed = ListenBackMix.mix(mic: mic, micRate: 100, spans: [span], timelineShift: 0)
        #expect(mixed[0..<10].allSatisfy { $0 == 0 })
        #expect(mixed[15..<35].allSatisfy { abs($0 - 0.4) < 0.0001 })
        #expect(mixed[50..<60].allSatisfy { abs($0 - 0.8) < 0.0001 })
        #expect(mixed[75..<85].allSatisfy { abs($0 - 0.4) < 0.0001 })
        #expect(mixed[90..<100].allSatisfy { $0 == 0 })
    }

    @Test("a 24 kHz partner span lands on the 48 kHz mic clock")
    func resamplesOntoMicClock() {
        let mic = [Float](repeating: 0, count: 48)
        let span = PartnerAudioSpan(
            start: 0.5,
            sampleRate: 24,
            samples: [Float](repeating: 0.4, count: 12)
        )
        let mixed = ListenBackMix.mix(mic: mic, micRate: 48, spans: [span], timelineShift: 0)
        #expect(mixed.count == 48)
        #expect(mixed[0..<24].allSatisfy { $0 == 0 })
        #expect(mixed[24..<48].allSatisfy { abs($0 - 0.4) < 0.0001 })
    }

    @Test("denoise trim shifts partner audio earlier by the same delay")
    func shiftFollowsTrim() {
        let mic = [Float](repeating: 0, count: 100)
        let span = PartnerAudioSpan(
            start: 0.5,
            sampleRate: 100,
            samples: [Float](repeating: 0.3, count: 20)
        )
        let mixed = ListenBackMix.mix(mic: mic, micRate: 100, spans: [span], timelineShift: 0.2)
        #expect(mixed[0..<30].allSatisfy { $0 == 0 })
        #expect(mixed[30..<50].allSatisfy { abs($0 - 0.3) < 0.0001 })
        #expect(mixed[50..<100].allSatisfy { $0 == 0 })
    }

    @Test("voice-processing residual under the partner becomes the partner tone")
    func residualIsQuietNextToSpeech() {
        var mic = [Float](repeating: 0.03, count: 100)
        for i in 90..<100 { mic[i] = 0.4 }
        let span = PartnerAudioSpan(
            start: 0,
            sampleRate: 100,
            samples: [Float](repeating: 0.5, count: 80)
        )
        let mixed = ListenBackMix.mix(mic: mic, micRate: 100, spans: [span], timelineShift: 0)
        #expect(mixed[10..<70].allSatisfy { abs($0 - 0.5) < 0.0001 })
        #expect(mixed[90..<100].allSatisfy { abs($0 - 0.4) < 0.0001 })
    }

    @Test("audio scheduled past an interrupt is dropped")
    func trimUnheard() {
        let spans = [
            PartnerAudioSpan(start: 0, sampleRate: 10, samples: [Float](repeating: 0.2, count: 10)),
            PartnerAudioSpan(start: 1, sampleRate: 10, samples: [Float](repeating: 0.4, count: 10)),
        ]
        let kept = ListenBackMix.trimming(spans, heardThrough: 1.5)
        #expect(kept.count == 2)
        #expect(kept[0].samples.count == 10)
        #expect(kept[1].samples.count == 5)
    }

    @Test("no partner audio leaves the mic take unchanged")
    func emptySpans() {
        let mic: [Float] = [0.2, -0.3]
        #expect(ListenBackMix.mix(mic: mic, micRate: 100, spans: [], timelineShift: 0) == mic)
    }
}
