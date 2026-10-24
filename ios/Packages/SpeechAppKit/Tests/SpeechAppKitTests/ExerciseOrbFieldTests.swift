import Foundation
import Testing
@testable import SpeechAppKit

@Suite("Exercise orb field")
struct ExerciseOrbFieldTests {
    @Test("a chosen disc churns like the orb while someone is speaking")
    func agitation() {
        let chosen = ExerciseOrbField(kind: .reading, chosen: true, hovered: false)
        let hovered = ExerciseOrbField(kind: .reading, chosen: false, hovered: true)
        let idle = ExerciseOrbField(kind: .reading, chosen: false, hovered: false)

        #expect(chosen.speed > hovered.speed)
        #expect(hovered.speed > idle.speed)
        #expect(chosen.speed / idle.speed < 2.2)
        #expect(chosen.activity > idle.activity)
    }

    @Test("an unchosen disc fades to gray")
    func gray() {
        let chosen = ExerciseOrbField(kind: .monologue, chosen: true, hovered: false)
        let idle = ExerciseOrbField(kind: .monologue, chosen: false, hovered: false)

        #expect(chosen.gray == 0)
        #expect(idle.gray > 0.7)
    }

    @Test("coloured discs use their plate colour, and Reading is white")
    func plateColor() {
        for kind in [PracticeFormat.Kind.monologue, .conversation] {
            let plate = ExercisePlate.plate(for: kind)
            let gas = ExerciseOrbField(kind: kind, chosen: true, hovered: false).gases.plate
            #expect(abs(gas.red - plate.red) < 0.001)
            #expect(abs(gas.green - plate.green) < 0.001)
            #expect(abs(gas.blue - plate.blue) < 0.001)
        }

        let reading = ExerciseOrbField(kind: .reading, chosen: true, hovered: false).gases
        #expect(reading.plate.red == 1)
        #expect(reading.plate.green == 1)
        #expect(reading.plate.blue == 1)
        #expect(reading.secondary.red == reading.secondary.green)
        #expect(reading.secondary.green == reading.secondary.blue)
        #expect(reading.secondary.red < 0.8)
        #expect(reading.secondary.red > 0.5)
    }

    @Test("the three exercises are different mixes")
    func families() {
        let reading = ExerciseOrbField(kind: .reading, chosen: true, hovered: false).gases
        let monologue = ExerciseOrbField(kind: .monologue, chosen: true, hovered: false).gases
        let conversation = ExerciseOrbField(kind: .conversation, chosen: true, hovered: false).gases

        #expect(reading.plate != monologue.plate)
        #expect(monologue.plate != conversation.plate)
        #expect(monologue.secondary.red > monologue.secondary.blue)
        #expect(conversation.secondary.blue > conversation.secondary.red)
        #expect(distance(reading.plate, reading.secondary) > 0.5)
        #expect(distance(monologue.plate, monologue.secondary) > 0.25)
        #expect(distance(conversation.plate, conversation.secondary) > 0.30)
        #expect(distance(monologue.plate, monologue.secondary) < 0.55)
        #expect(distance(conversation.plate, conversation.secondary) < 0.60)
    }

    private func distance(_ a: ExerciseOrbField.Stop, _ b: ExerciseOrbField.Stop) -> Double {
        abs(a.red - b.red) + abs(a.green - b.green) + abs(a.blue - b.blue)
    }
}
