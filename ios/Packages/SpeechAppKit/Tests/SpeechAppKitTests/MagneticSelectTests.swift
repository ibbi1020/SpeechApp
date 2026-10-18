import CoreGraphics
import Foundation
import Testing
@testable import SpeechAppKit

@Suite("Exercise plates")
struct ExercisePlateTests {
    private let size = CGSize(width: 390, height: 800)

    @Test("each exercise keeps the prototype's placement")
    func placement() {
        let reading = ExercisePlate.plate(for: .reading)
        let monologue = ExercisePlate.plate(for: .monologue)
        let conversation = ExercisePlate.plate(for: .conversation)
        let warm = monologue.glows[0]
        let cool = conversation.glows[0]

        #expect(reading.glows[0].x == 0.50)
        #expect(warm.x < 0.5)
        #expect(cool.x > 0.5)
        // Further right than a mirror of the yellow glow, and lower, and wider.
        #expect(cool.x > 1 - warm.x)
        #expect(cool.y > warm.y)
        #expect(cool.radius > warm.radius)
        #expect(monologue.red > monologue.blue)
        #expect(conversation.blue > conversation.red)
    }

    @Test("the headline stays dark, and the blue field lives on the right")
    func sides() {
        let conversation = ExercisePlate.plate(for: .conversation).sources(in: size)
        let monologue = ExercisePlate.plate(for: .monologue).sources(in: size)
        let reading = ExercisePlate.plate(for: .reading).sources(in: size)

        let right = CGPoint(x: 370, y: 760)
        let left = CGPoint(x: 30, y: 740)
        let top = CGPoint(x: size.width / 2, y: 8)

        #expect(DitherHorizon.brightness(at: right, sources: conversation) > DitherHorizon.brightness(at: left, sources: conversation))
        #expect(DitherHorizon.brightness(at: left, sources: monologue) > DitherHorizon.brightness(at: right, sources: monologue))
        #expect(DitherHorizon.brightness(at: top, sources: conversation) == 0)
        #expect(DitherHorizon.brightness(at: top, sources: monologue) == 0)
        #expect(DitherHorizon.brightness(at: top, sources: reading) == 0)
    }
}

@Suite("Magnetic cluster")
struct MagneticClusterTests {
    @Test("the triangle is the prototype's scaled lattice")
    func lattice() {
        #expect(abs(MagneticCluster.size.width - 211.5) < 0.001)
        #expect(abs(MagneticCluster.size.height - 202.5) < 0.001)
        #expect(MagneticCluster.count == 3)
    }

    @Test("the chosen disc grows and the other two are pushed the same distance")
    func field() {
        let aims = MagneticCluster.aims(selected: 0, stagger: true)
        #expect(aims[0].pose.x == 0)
        #expect(aims[0].pose.y == 0)
        #expect(aims[0].pose.scaleX > 1)
        #expect(aims[0].delay == 0)

        let first = hypot(aims[1].pose.x, aims[1].pose.y)
        let second = hypot(aims[2].pose.x, aims[2].pose.y)
        #expect(abs(first - second) < 0.001)
        #expect(first > 15)
        #expect(aims[1].pose.scaleX < 1)
        #expect(aims[1].delay > 0)
        #expect(aims[2].delay > 0)
    }

    @Test("only a new choice staggers")
    func stagger() {
        let aims = MagneticCluster.aims(selected: 1, stagger: false)
        #expect(aims.allSatisfy { $0.delay == 0 })
        #expect(aims[1].pose.scaleX > 1)
        #expect(aims[0].pose.scaleX < 1)
    }

    @Test("lean is zero at the hub and points outward at the edge")
    func lean() {
        let hub = MagneticCluster.hub(selected: 0)
        #expect(MagneticCluster.lean(at: hub.center, selected: 0) == .zero)
        let edge = CGPoint(x: hub.center.x + hub.radius, y: hub.center.y)
        let lean = MagneticCluster.lean(at: edge, selected: 0)
        #expect(lean.width > 4)
        #expect(abs(lean.height) < 0.001)
    }
}

@Suite("Magnetic spring")
struct MagneticSpringTests {
    @Test("snap lands on the target with nothing left to do")
    func snap() {
        var spring = MagneticSpring(value: 0)
        spring.aim(target: 4, stiffness: 300, mass: 0.9, zeta: 0.6, delay: 1, snap: true)
        #expect(spring.value == 4)
        let moving = spring.step(dt: 1.0 / 60)
        #expect(moving == false)
    }

    @Test("a delay holds the value, then the spring arrives")
    func delayThenSettle() {
        var spring = MagneticSpring(value: 0)
        spring.aim(target: 10, stiffness: 300, mass: 0.9, zeta: 0.9, delay: 0.05, snap: false)
        let held = spring.step(dt: 1.0 / 60)
        #expect(held)
        #expect(spring.value == 0)
        for _ in 0 ..< 360 {
            _ = spring.step(dt: 1.0 / 60)
        }
        #expect(abs(spring.value - 10) < 0.05)
    }
}
