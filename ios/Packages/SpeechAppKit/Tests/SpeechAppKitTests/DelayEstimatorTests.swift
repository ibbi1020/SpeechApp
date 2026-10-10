import Testing
@testable import SpeechAppKit

@Suite("Delay estimator")
struct DelayEstimatorTests {
    @Test("finds a known lag in a delayed signal")
    func findsLag() {
        let rate = 16_000.0
        let lagSamples = 960 // 60 ms
        var reference = [Float](repeating: 0, count: 16_000)
        // A burst of energy in the middle.
        for i in 4_000..<5_000 {
            reference[i] = Float(i % 2 == 0 ? 0.8 : -0.8)
        }
        var delayed = [Float](repeating: 0, count: reference.count + lagSamples)
        for i in 0..<reference.count {
            delayed[i + lagSamples] = reference[i]
        }
        let estimated = DelayEstimator.delaySeconds(
            reference: reference,
            delayed: delayed,
            sampleRate: rate
        )
        #expect(abs(estimated - 0.06) < 0.02)
    }
}
