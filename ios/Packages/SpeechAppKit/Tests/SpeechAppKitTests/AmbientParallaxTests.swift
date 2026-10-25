import Testing
@testable import SpeechAppKit

@Suite("Ambient picture tilt")
struct AmbientParallaxTests {
    private let rest = AmbientParallax.Pose(roll: 0, pitch: 0, yaw: 0)

    @Test("holding still keeps the picture centered")
    func stillIsCentered() {
        let held = AmbientParallax.Pose(roll: 0.4, pitch: -0.8, yaw: 1.1)
        #expect(AmbientParallax.shift(from: held, to: held) == .centered)
    }

    @Test("tilting toward an edge reveals that edge, and no further")
    func tiltClamps() {
        let full = AmbientParallax.Pose(roll: AmbientParallax.tiltSpan, pitch: 0, yaw: 0)
        let past = AmbientParallax.Pose(roll: 2, pitch: 0, yaw: 0)
        #expect(AmbientParallax.shift(from: rest, to: full).x == -AmbientParallax.maxSlide)
        #expect(AmbientParallax.shift(from: rest, to: past).x == -AmbientParallax.maxSlide)
        #expect(AmbientParallax.shift(from: rest, to: full).y == 0)
    }

    @Test("the slide is measured from the pose where the picture appeared")
    func relativeToTheHold() {
        let held = AmbientParallax.Pose(roll: 0.4, pitch: -0.8, yaw: 1.2)
        let tilted = AmbientParallax.Pose(
            roll: held.roll + AmbientParallax.tiltSpan,
            pitch: held.pitch,
            yaw: held.yaw
        )
        #expect(AmbientParallax.shift(from: held, to: tilted).x == -AmbientParallax.maxSlide)
    }

    @Test("a twist turns the picture a small amount")
    func twist() {
        let turned = AmbientParallax.Pose(roll: 0, pitch: 0, yaw: AmbientParallax.tiltSpan)
        #expect(AmbientParallax.shift(from: rest, to: turned).degrees == AmbientParallax.maxTwist)
    }

    @Test("smoothing moves part of the way toward the tilt")
    func smooths() {
        let target = AmbientParallax.Shift(x: 10, y: -4, degrees: 1)
        let step = AmbientParallax.smooth(previous: .centered, target: target, factor: 0.5)
        #expect(step.x == 5)
        #expect(step.y == -2)
        #expect(step.degrees == 0.5)
    }

    @Test("the zoom hides the tilt and leaves the loose edges of the picture")
    func zoomCoversTheSlide() {
        let phone = (width: 393.0, height: 852.0)
        let summer = AmbientParallax.zoom(
            viewWidth: phone.width,
            viewHeight: phone.height,
            imageWidth: 736,
            imageHeight: 1308
        )
        let room = AmbientParallax.zoom(
            viewWidth: phone.width,
            viewHeight: phone.height,
            imageWidth: 928,
            imageHeight: 1231
        )
        #expect(summer > 1)
        #expect(summer < 1.08)
        #expect(room < 1.08)
        let verticalRoom = (summer * phone.height - phone.height) / 2
        #expect(verticalRoom > AmbientParallax.maxSlide)
    }
}
