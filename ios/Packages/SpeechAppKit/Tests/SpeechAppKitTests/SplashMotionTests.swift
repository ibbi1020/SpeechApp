import CoreGraphics
import Foundation
import Testing
@testable import SpeechAppKit

@Suite("Splash motion")
struct SplashMotionTests {
    @Test("the splash holds the mark, then Home appears")
    func holdIsShort() {
        #expect(SplashMotion.hold == 0.35)
        #expect(SplashMotion.hold < 0.5)
    }

    @Test("the mark stays icon-sized")
    func markStaysIconSized() {
        #expect(SplashMotion.markSize == 96)
    }
}
