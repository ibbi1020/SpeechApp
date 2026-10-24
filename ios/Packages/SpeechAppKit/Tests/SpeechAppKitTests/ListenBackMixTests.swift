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

    /// A float prefix of squares drifts by the end of a long take and would
    /// paste the partner over a late barge-in. This locks the window sum.
    @Test("a three minute take keeps the same quiet decisions")
    func longTakeMatchesWindowSum() {
        let rate = 48_000.0
        let count = Int(rate * 180)
        var mic = [Float](repeating: 0.4, count: count)
        let quietAt = Int(rate * 170)
        let loudAt = Int(rate * 175)
        let stretch = 4_000
        for index in quietAt ..< (quietAt + stretch) { mic[index] = 0.13 }
        for index in loudAt ..< (loudAt + stretch) { mic[index] = 0.15 }

        let span = PartnerAudioSpan(
            start: 170,
            sampleRate: rate,
            samples: [Float](repeating: 0.9, count: Int(rate * 8))
        )
        let mixed = ListenBackMix.mix(mic: mic, micRate: rate, spans: [span], timelineShift: 0)
        let threshold = max(ListenBackMix.speechLevel(mic) * 0.35, 0.0001)
        #expect(abs(threshold - 0.14) < 0.001)

        let quietCenter = quietAt + stretch / 2
        let loudCenter = loudAt + stretch / 2
        #expect(windowRMS(mic, index: quietCenter, rate: rate) < threshold - 0.005)
        #expect(windowRMS(mic, index: loudCenter, rate: rate) > threshold + 0.005)

        let start = Int((span.start * rate).rounded(.down))
        let end = min(count, start + span.samples.count)
        var flips = 0
        for index in start ..< end {
            let quiet = windowIsQuiet(mic, index: index, rate: rate, threshold: threshold)
            let becamePartner = mixed[index] == 0.9
            if quiet != becamePartner { flips += 1 }
        }
        #expect(flips == 0)
        #expect(mixed[quietCenter] == 0.9)
        #expect(mixed[loudCenter] == 0.15)
    }

    /// The quiet test before the prefix sum: a fresh Float sum of the window.
    private func windowIsQuiet(_ mic: [Float], index: Int, rate: Double, threshold: Float) -> Bool {
        windowRMS(mic, index: index, rate: rate) < threshold
    }

    private func windowRMS(_ mic: [Float], index: Int, rate: Double) -> Float {
        let radius = max(0, Int((ListenBackMix.quietWindowSeconds * rate / 2).rounded(.down)))
        let lo = max(0, index - radius)
        let hi = min(mic.count, index + radius + 1)
        guard hi > lo else { return 0 }
        var sum: Float = 0
        for sampleIndex in lo ..< hi {
            let sample = mic[sampleIndex]
            sum += sample * sample
        }
        return sqrt(sum / Float(hi - lo))
    }
}
