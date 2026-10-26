import CoreGraphics
import Foundation
import Testing
@testable import SpeechAppKit

@Suite("Exercise plates")
struct ExercisePlateTests {
    @Test("each exercise keeps its colour")
    func colors() {
        let reading = ExercisePlate.plate(for: .reading)
        let monologue = ExercisePlate.plate(for: .monologue)
        let conversation = ExercisePlate.plate(for: .conversation)

        #expect(reading.red > 0.9)
        #expect(reading.green > 0.9)
        #expect(monologue.red > monologue.blue)
        #expect(conversation.blue > conversation.red)
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
