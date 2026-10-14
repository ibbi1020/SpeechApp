import CoreGraphics
import Foundation
import Testing
@testable import SpeechAppKit

@Suite("Dithered horizon")
struct DitherHorizonTests {
    @Test("the glow sits below the bottom edge, and only the lower field lights")
    func horizon() {
        let size = CGSize(width: 200, height: 400)
        let field = DitherHorizon.field(size: size, level: 0, gain: DitherHorizon.humGain)
        #expect(abs(field.center.x - size.width / 2) < 0.001)
        #expect(abs(field.center.y - size.height * 1.10) < 0.001)
        #expect(abs(field.radius - size.height * 0.46 * 0.78) < 0.001)

        let cell = DitherHorizon.cell(forWidth: size.width)
        let middle = Int((size.width / cell) / 2)
        let rows = Int(ceil(size.height / cell))
        let top = DitherHorizon.dotSide(column: middle, row: 0, cell: cell, field: field)
        let bottom = DitherHorizon.dotSide(column: middle, row: rows - 1, cell: cell, field: field)
        #expect(top == 0)
        #expect(bottom > 0)
    }

    @Test("dots are larger than the first prototype pitch")
    func pitch() {
        let width: CGFloat = 390
        let cell = DitherHorizon.cell(forWidth: width)
        let firstPitch = max(2, (width / 112).rounded())
        #expect(cell > firstPitch)
    }

    @Test("silence stays low and a voice lifts the field")
    func drive() {
        #expect(DitherHorizon.voiceLevel(rms: 0.005) == 0)
        #expect(DitherHorizon.voiceLevel(rms: 0.08) > 0.5)
        let quiet = DitherHorizon.level(voice: 0, reduceMotion: false)
        let loud = DitherHorizon.level(voice: 1, reduceMotion: false)
        #expect(quiet < 0.2)
        #expect(loud == 1)
        #expect(DitherHorizon.level(voice: 1, reduceMotion: true) == quiet)
    }

    @Test("brightness falls as inverse square, so the crown is thinner than the base")
    func falloff() {
        let near = DitherHorizon.brightness(distance: 0.25, peak: 1)
        let far = DitherHorizon.brightness(distance: 0.85, peak: 1)
        #expect(near > far * 3)
    }
}
