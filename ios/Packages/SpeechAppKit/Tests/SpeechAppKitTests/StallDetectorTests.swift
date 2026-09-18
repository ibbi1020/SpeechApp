import Testing
@testable import SpeechAppKit

@Suite("StallDetector")
struct StallDetectorTests {
    private func loud(count: Int = 256) -> [Float] {
        Array(repeating: 0.2, count: count)
    }

    private func quiet(count: Int = 256) -> [Float] {
        Array(repeating: 0.0001, count: count)
    }

    @Test("does not stall before first speech when armAfterSpeech is true")
    func waitsForSpeech() {
        let detector = StallDetector(configuration: .init(silenceTimeout: 1.0, armAfterSpeech: true))
        let fired = detector.process(samples: quiet(), at: 5.0)
        #expect(fired == false)
        #expect(detector.isStalled == false)
    }

    @Test("fires once after silence timeout following speech")
    func firesAfterTimeout() {
        let detector = StallDetector(configuration: .init(silenceTimeout: 2.0, armAfterSpeech: true))
        _ = detector.process(samples: loud(), at: 0.0)
        #expect(detector.process(samples: quiet(), at: 1.0) == false)
        #expect(detector.process(samples: quiet(), at: 2.1) == true)
        #expect(detector.isStalled == true)
        // Edge-triggered: still stalled but does not fire again
        #expect(detector.process(samples: quiet(), at: 3.0) == false)
    }

    @Test("dismiss suppresses until speech returns")
    func dismissUntilSpeech() {
        let detector = StallDetector(configuration: .init(silenceTimeout: 1.0))
        _ = detector.process(samples: loud(), at: 0.0)
        #expect(detector.process(samples: quiet(), at: 1.5) == true)
        detector.dismiss()
        #expect(detector.isStalled == false)
        #expect(detector.process(samples: quiet(), at: 3.0) == false)
        _ = detector.process(samples: loud(), at: 3.5)
        #expect(detector.process(samples: quiet(), at: 5.0) == true)
    }

    @Test("speech clears stall")
    func speechClearsStall() {
        let detector = StallDetector(configuration: .init(silenceTimeout: 1.0))
        _ = detector.process(samples: loud(), at: 0.0)
        _ = detector.process(samples: quiet(), at: 1.5)
        #expect(detector.isStalled == true)
        _ = detector.process(samples: loud(), at: 2.0)
        #expect(detector.isStalled == false)
    }
}
