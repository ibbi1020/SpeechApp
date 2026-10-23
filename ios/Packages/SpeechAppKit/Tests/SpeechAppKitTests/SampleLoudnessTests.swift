import Testing
@testable import SpeechAppKit

@Suite("Sample loudness")
struct SampleLoudnessTests {
    @Test("silence is 0")
    func silence() {
        let rms = SampleLoudness.rms(floatSamples: [Float](repeating: 0, count: 8))
        #expect(rms == 0)
    }

    @Test("a steady float buffer is its own loudness")
    func steadyFloat() {
        let rms = SampleLoudness.rms(floatSamples: [Float](repeating: 0.2, count: 16))
        #expect(abs(rms - 0.2) < 0.000_1)
    }

    @Test("int16 of the same loudness matches")
    func steadyInt16() {
        let sample = Int16(0.2 * 32_767)
        let rms = SampleLoudness.rms(int16Samples: [Int16](repeating: sample, count: 16))
        #expect(abs(rms - 0.2) < 0.001)
    }

    @Test("an empty buffer is 0")
    func empty() {
        #expect(SampleLoudness.rms(floatSamples: [Float]()) == 0)
        #expect(SampleLoudness.rms(int16Samples: [Int16]()) == 0)
    }
}
