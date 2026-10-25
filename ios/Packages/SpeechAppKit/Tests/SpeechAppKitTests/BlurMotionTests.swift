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

    @Test("the pause wash is gray and climbs three quarters of the screen")
    func pauseWash() {
        #expect(PauseVeilMotion.reach == 0.75)
        #expect(abs(PauseVeilMotion.washWhite - (CGFloat(0x0E) / 255)) < 0.0001)
        #expect(PauseVeilMotion.labelWhite < 1)
        #expect(PauseVeilMotion.labelWhite > 0.5)
        #expect(PauseVeilMotion.veil > PauseVeilMotion.mark)
        let total = PauseVeilMotion.veil + PauseVeilMotion.mark
        #expect(abs(total - 0.33) < 0.001)
        #expect(abs(PauseVeilMotion.blurRadius - BlurMotion.backdropRadius * 0.1) < 0.001)

        let stops = PauseVeilMotion.stops(bottomOpacity: PauseVeilMotion.washOpacity)
        #expect(stops.first?.opacity == 0)
        #expect(stops.first?.location == 0)
        #expect(stops.last?.opacity == PauseVeilMotion.washOpacity)
        #expect(stops.last?.location == 1)
        let opacities = stops.map(\.opacity)
        #expect(opacities == opacities.sorted())
        // Halfway up the wash is still mid-fade. Nearly solid here is the slab.
        let midway = stops.first { $0.location >= 0.5 }
        #expect((midway?.opacity ?? 1) < PauseVeilMotion.washOpacity * 0.7)
    }

    @Test("the rising edge stays a fade from the first moment to the last")
    func pauseWashRisesAsAGradient() {
        #expect(PauseVeilMotion.reveal(at: 0.5, progress: 0) == 0)
        #expect(PauseVeilMotion.reveal(at: 0, progress: 1) == 1)
        #expect(PauseVeilMotion.reveal(at: 1, progress: 1) == 1)
        // Partway up, the bottom is ahead of the top, and something is still feathering.
        let progress = 0.45
        let top = PauseVeilMotion.reveal(at: 0, progress: progress)
        let bottom = PauseVeilMotion.reveal(at: 1, progress: progress)
        #expect(bottom > top)
        let samples = PauseVeilMotion.revealStops(progress: progress).map(\.opacity)
        #expect(samples.contains { $0 > 0 && $0 < 1 })
    }

    @Test("the backdrop dims to about a third of what it was")
    func backdropDim() {
        // Measured: the reference map drops from 89 to 28 mean brightness.
        #expect(BlurMotion.backdropDim == 0.55)
        #expect(BlurMotion.opaqueBackdropDim == 0.72)
        #expect(BlurMotion.backdropDim < BlurMotion.opaqueBackdropDim)
    }
}
