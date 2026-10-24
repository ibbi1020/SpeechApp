import CoreGraphics
import Foundation
import Testing
@testable import SpeechAppKit

@Suite("Tape layout")
struct TapeLayoutTests {
    private let long = TapeLayout(duration: 480, width: 280)

    @Test("the start of a long take sits under the needle")
    func startUnderNeedle() {
        let start = long.viewStart(time: 0)
        #expect(abs(start - -10.08) < 0.000_1)
        let x = long.x(for: 0, viewStart: start)
        #expect(abs(x - 100.8) < 0.001)
        #expect(abs(long.needleX(at: 0) - 100.8) < 0.001)
    }

    @Test("the end of a long take sits under the needle")
    func endUnderNeedle() {
        let start = long.viewStart(time: 480)
        #expect(abs(start - 469.92) < 0.000_1)
        let x = long.x(for: 480, viewStart: start)
        #expect(abs(x - long.needleX(at: 480)) < 0.001)
    }

    @Test("a finger moving right rewinds the tape")
    func dragRewinds() {
        let hold = long.dragged(from: 40, translation: 25)
        #expect(abs(hold.time - 37.5) < 0.000_1)
        #expect(hold.pull == 0)
    }

    @Test("dragging past the start rubber-bands and holds time at zero")
    func rubberAtStart() {
        let hold = long.dragged(from: 1, translation: 50)
        #expect(hold.time == 0)
        #expect(abs(hold.pull - 20.397_350_993) < 0.000_1)
    }

    @Test("dragging past the end rubber-bands the other way")
    func rubberAtEnd() {
        let hold = long.dragged(from: 479, translation: -50)
        #expect(hold.time == 480)
        #expect(abs(hold.pull - -20.397_350_993) < 0.000_1)
    }

    @Test("a coast step moves by velocity times the frame duration")
    func coastIncludesFrameTime() {
        let released = long.release(time: 10, pull: 0, velocity: 100, reduceMotion: false)
        let stepped = long.step(released, dt: 0.5)
        #expect(stepped.phase == .coast)
        #expect(abs(stepped.time - 8.479_617_844) < 0.000_1)
    }

    @Test("a coast that hits the end becomes a spring")
    func coastHitsEnd() {
        let released = long.release(time: 479, pull: 0, velocity: -400, reduceMotion: false)
        let stepped = long.step(released, dt: 0.5)
        #expect(stepped.phase == .spring)
        #expect(stepped.time == 480)
        #expect(abs(stepped.pull - -25.411_899_833) < 0.000_1)
    }

    @Test("one spring frame leaves the pull short of zero")
    func springFrame() {
        var motion = long.release(time: 10, pull: 10, velocity: 0, reduceMotion: false)
        motion.pullVelocity = 0
        let stepped = long.step(motion, dt: 0.016)
        #expect(stepped.phase == .spring)
        #expect(abs(stepped.pull - 9.174_981_640) < 0.000_1)
        #expect(abs(stepped.pullVelocity - -51.563_647_483) < 0.000_1)
    }

    @Test("reduce motion snaps the pull and does not coast")
    func reduceMotionSnaps() {
        let released = long.release(time: 12, pull: 30, velocity: 400, reduceMotion: true)
        #expect(released.phase == .settled)
        #expect(released.pull == 0)
        #expect(released.time == 12)
    }

    @Test("a tap reads the time under the finger")
    func tapTime() {
        let start = long.viewStart(time: 0)
        let time = long.time(at: 280, viewStart: start)
        #expect(abs(time - 17.92) < 0.000_1)
    }

    @Test("a short take fills the lane and the needle walks")
    func shortTake() {
        let layout = TapeLayout(duration: 10, width: 200)
        #expect(!layout.scrolls)
        #expect(layout.window == 10)
        #expect(layout.viewStart(time: 4) == 0)
        #expect(abs(layout.needleX(at: 4) - 80) < 0.001)
        #expect(abs(layout.x(for: 4, viewStart: 0) - 80) < 0.001)
    }

    @Test("a take of exactly 28 seconds does not scroll")
    func boundary() {
        let layout = TapeLayout(duration: 28, width: 280)
        #expect(!layout.scrolls)
        #expect(layout.viewStart(time: 14) == 0)
    }

    @Test("empty time before the take is silence, and time zero is the cached start")
    func sliceAtStart() {
        var cache = [Float](repeating: TapeLayout.silence, count: 1000)
        cache[0] = 0.2
        cache[1] = 0.4
        let layout = TapeLayout(duration: 280, width: 100)
        let slice = layout.slice(cache: cache, viewStart: layout.viewStart(time: 0), scale: 1)
        #expect(slice.offset == 0)
        #expect(slice.samples[35] == TapeLayout.silence)
        #expect(slice.samples[36] == 0.2)
        #expect(slice.samples[37] == 0.4)
        #expect(slice.samples.count == 100)
    }

    @Test("a fractional sample shifts the slice by less than one pixel")
    func sliceFraction() {
        var cache = [Float](repeating: TapeLayout.silence, count: 1000)
        cache[0] = 0.2
        let layout = TapeLayout(duration: 280, width: 100)
        let slice = layout.slice(cache: cache, viewStart: -9.94, scale: 2)
        #expect(abs(slice.offset - -0.25) < 0.000_1)
        #expect(slice.samples[36] == 0.2)
        #expect(slice.samples[35] == TapeLayout.silence)
        #expect(slice.samples.count == 200)
    }

    @Test("a wider lane keeps the needle sample on the needle")
    func widthBridge() {
        let bridge = TapeLayout.widthBridge(oldWidth: 100, newWidth: 200)
        #expect(bridge.scale == 2)
        #expect(abs(bridge.shift - 36) < 0.001)
    }

    @Test("ruler labels land on the quarter minutes inside the window")
    func ruler() {
        let marks = long.marks(viewStart: long.viewStart(time: 0), every: 15)
        #expect(marks == [0, 15])
    }
}
