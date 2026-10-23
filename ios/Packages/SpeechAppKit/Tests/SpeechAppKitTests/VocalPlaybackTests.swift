import Testing
@testable import SpeechAppKit

@Suite("Vocal playback")
struct VocalPlaybackTests {
    @Test("the played hum uses the full sample range")
    func fullScale() {
        #expect(VocalPlayback.peak == 1)
        // The old tone stopped at 0.85, so a strong moment stayed short of full.
        let strong = VocalPlayback.sample(shaped: 0.7, partial: 0.5, flutter: 1)
        #expect(strong > 0.85)
        #expect(strong <= 1)
    }
}
