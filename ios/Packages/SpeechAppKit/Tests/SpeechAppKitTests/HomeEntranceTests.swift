import CoreGraphics
import Testing
@testable import SpeechAppKit

@Suite("Home entrance")
struct HomeEntranceTests {
    @Test("gallery lands before progress, and the fade outlasts both slides")
    func order() {
        #expect(HomeEntrance.galleryDuration == 0.184)
        #expect(HomeEntrance.progressDuration == 0.284)
        #expect(HomeEntrance.fadeDuration == 0.48)
        #expect(HomeEntrance.galleryDuration < HomeEntrance.progressDuration)
        #expect(HomeEntrance.progressDuration < HomeEntrance.fadeDuration)
    }

    @Test("greeting, begin, and both sheets start together")
    func sameStart() {
        #expect(HomeEntrance.startDelay == 0)
    }

    @Test("both cards start on one line 32pt below the screen")
    func travel() {
        #expect(HomeEntrance.startPastEdge == 32)
        // Gallery peek is 88, so 88 + 32.
        #expect(HomeEntrance.travel(cardHeight: 88) == 120)
        // Progress rests at lip 56 + gallery peek 88, so 144 + 32.
        #expect(HomeEntrance.travel(cardHeight: 144) == 176)
        #expect(HomeEntrance.travel(cardHeight: 88) < HomeEntrance.travel(cardHeight: 144))
    }

    @Test("fade and slide use the prototype curves")
    func curves() {
        #expect(HomeEntrance.fadeCurve == HomeEntrance.Curve(x1: 0.23, y1: 1, x2: 0.32, y2: 1))
        #expect(HomeEntrance.slideCurve == HomeEntrance.Curve(x1: 0, y1: 0, x2: 0.58, y2: 1))
    }
}
