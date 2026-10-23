import CoreGraphics
import Foundation
import Testing
@testable import SpeechAppKit

@Suite("Blur motion")
struct BlurMotionTests {
    @Test("a dissolve is a quarter second and a burst is half that again")
    func durations() {
        #expect(BlurMotion.dissolve == 0.28)
        #expect(BlurMotion.burst == 0.12)
        #expect(BlurMotion.backdrop == 0.30)
        #expect(BlurMotion.burst < BlurMotion.dissolve)
    }

    @Test("a burst blurs harder than a dissolve, and the backdrop sits between them")
    func depths() {
        #expect(BlurMotion.dissolveRadius == 20)
        #expect(BlurMotion.burstRadius == 30)
        #expect(BlurMotion.backdropRadius == 28)
        #expect(BlurMotion.dissolveRadius < BlurMotion.backdropRadius)
        #expect(BlurMotion.backdropRadius < BlurMotion.burstRadius)
    }

    @Test("text dissolves through four tenths of its own size")
    func textRadiusScales() {
        // The reference header is 51pt and dissolves through 20pt.
        #expect(abs(BlurMotion.textRadius(forSize: 51) - 20.4) < 0.001)
        #expect(abs(BlurMotion.textRadius(forSize: 40) - 16) < 0.001)
        #expect(abs(BlurMotion.textRadius(forSize: 16) - 6.4) < 0.001)
    }

    @Test("small text still blurs enough to read as gone")
    func textRadiusFloor() {
        // Four tenths of 10pt is 4pt, which still leaves the glyphs legible.
        #expect(BlurMotion.textRadius(forSize: 10) == BlurMotion.minimumTextRadius)
        #expect(BlurMotion.textRadius(forSize: 0) == BlurMotion.minimumTextRadius)
        #expect(BlurMotion.minimumTextRadius == 6)
    }

    @Test("a sharp phase is fully opaque and unblurred")
    func sharpPhase() {
        #expect(BlurPhase.sharp.radius == 0)
        #expect(BlurPhase.sharp.opacity == 1)
    }

    @Test("a dissolved phase is invisible and carries the blur it left on")
    func dissolvedPhase() {
        let phase = BlurPhase.dissolved(radius: 14)
        #expect(phase.radius == 14)
        #expect(phase.opacity == 0)
        #expect(BlurPhase.dissolved().radius == BlurMotion.dissolveRadius)
    }

    @Test("reduce motion drops the blur and keeps a short fade")
    func reduceMotionFlattens() {
        let phase = BlurPhase.dissolved(radius: 20, reduceMotion: true)
        #expect(phase.radius == 0)
        #expect(phase.opacity == 0)
        #expect(BlurMotion.reducedFade == 0.2)
        #expect(BlurMotion.reducedFade < BlurMotion.dissolve)
    }

    @Test("the backdrop dims to about a third of what it was")
    func backdropDim() {
        // Measured: the reference map drops from 89 to 28 mean brightness.
        #expect(BlurMotion.backdropDim == 0.55)
        #expect(BlurMotion.opaqueBackdropDim == 0.72)
        #expect(BlurMotion.backdropDim < BlurMotion.opaqueBackdropDim)
    }
}
