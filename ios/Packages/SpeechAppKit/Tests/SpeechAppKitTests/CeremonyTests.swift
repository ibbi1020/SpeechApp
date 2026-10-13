import Foundation
import Testing
@testable import SpeechAppKit

@Suite("Ceremony steps")
struct CeremonyStepTests {
    @Test("the walk is exercise, then the breathing, then the voice")
    func activeOrder() {
        #expect(Ceremony.active == [.exercise, .breathe, .hum])
    }

    @Test("note, purpose and speak stay defined and off the walk")
    func benched() {
        #expect(Ceremony.benched == [.note, .purpose, .speak])
        #expect(Set(Ceremony.active).isDisjoint(with: Ceremony.benched))
        #expect(Set(Ceremony.active + Ceremony.benched) == Set(CeremonyStep.allCases))
    }

    @Test("next and previous stay inside the walk")
    func neighbours() {
        #expect(Ceremony.next(after: .exercise) == .breathe)
        #expect(Ceremony.next(after: .breathe) == .hum)
        #expect(Ceremony.next(after: .hum) == nil)
        #expect(Ceremony.previous(before: .hum) == .breathe)
        #expect(Ceremony.previous(before: .breathe) == .exercise)
        #expect(Ceremony.previous(before: .exercise) == nil)
        #expect(Ceremony.next(after: .note) == nil)
        #expect(Ceremony.previous(before: .speak) == nil)
    }

    @Test("breathing paces six a minute, four in and six out")
    func pacing() {
        #expect(BreathPacing.cycle == 10)
        #expect(BreathPacing.rate == 6)
        #expect(BreathPacing.inhale == 4)
        #expect(BreathPacing.exhale == 6)
        #expect(BreathPacing.cycles == 3)
        #expect(BreathPacing.total == 30)
        #expect(BreathPacing.settle == 3)
    }

    @Test("the voice runs ten seconds, short enough to hold in one breath")
    func vocalLength() {
        #expect(VocalClip.seconds == 10)
    }

    @Test("clips rotate through both families and wrap")
    func rotation() {
        #expect(VocalClip.next(after: nil) == .hum)
        var seen: [VocalClip] = []
        var clip: VocalClip? = nil
        for _ in 0 ..< VocalClip.allCases.count {
            let next = VocalClip.next(after: clip)
            seen.append(next)
            clip = next
        }
        #expect(Set(seen) == Set(VocalClip.allCases))
        #expect(VocalClip.next(after: seen.last) == seen.first)
        #expect(seen.contains { $0.isFluctuating })
        #expect(seen.contains { $0.isFluctuating == false })
    }

    @Test("the breath cue sits on the vocal step, not the breathing one")
    func breathCuePlacement() {
        #expect(CeremonyCopy.humBreath.lowercased().contains("breath"))
        #expect(CeremonyCopy.breatheLine.lowercased().contains("deep") == false)
        #expect(CeremonyCopy.breatheIn == "Breathe in")
        #expect(CeremonyCopy.breatheOut == "Breathe out")
    }

    @Test("copy never tells the user to relax or calm down")
    func noCalmDown() {
        let lines = [
            CeremonyCopy.breatheLine,
            CeremonyCopy.breatheIn,
            CeremonyCopy.breatheOut,
            CeremonyCopy.breatheButton,
            CeremonyCopy.breatheRate,
            CeremonyCopy.breatheSettle,
            CeremonyCopy.exerciseButton,
            CeremonyCopy.humReady,
            CeremonyCopy.humWaiting,
            CeremonyCopy.humBreath,
        ] + VocalClip.allCases.flatMap { [$0.line, $0.explain] }
        for line in lines {
            let lower = line.lowercased()
            #expect(lower.contains("relax") == false)
            #expect(lower.contains("calm") == false)
        }
    }
}

@Suite("Ceremony button")
struct CeremonyControlTests {
    private let open = ConversationBudgetSnapshot(limit: 20, used: 3, month: "2026-10")
    private let spent = ConversationBudgetSnapshot(limit: 20, used: 20, month: "2026-10")

    @Test("the breathing button waits out every cycle")
    func breathe() {
        let waiting = CeremonyControls.control(step: .breathe, chosen: .reading, budget: spent)
        #expect(waiting.title == "Done")
        #expect(waiting.isEnabled == false)

        let done = CeremonyControls.control(
            step: .breathe, chosen: .reading, budget: spent, breatheDone: true
        )
        #expect(done.isEnabled)
        #expect(done.advance == .step)
    }

    @Test("exercise advances, unless conversation is spent")
    func exercise() {
        let openControl = CeremonyControls.control(
            step: .exercise, chosen: .conversation, budget: open
        )
        #expect(openControl.title == "This one")
        #expect(openControl.isEnabled)
        #expect(openControl.advance == .step)

        let spentControl = CeremonyControls.control(
            step: .exercise, chosen: .conversation, budget: spent
        )
        #expect(spentControl.title == "Back next month")
        #expect(spentControl.isEnabled == false)
    }

    @Test("a spent month does not block reading or monologue")
    func otherFormats() {
        for kind in [PracticeFormat.Kind.reading, .monologue] {
            let control = CeremonyControls.control(step: .exercise, chosen: kind, budget: spent)
            #expect(control.isEnabled)
            #expect(control.title == "This one")
        }
    }

    @Test("the siren waits for Ready, then the exercise's own start title")
    func hum() {
        let explain = CeremonyControls.control(step: .hum, chosen: .reading, budget: open)
        #expect(explain.title == "Ready")
        #expect(explain.isEnabled)
        #expect(explain.advance == .armHum)

        let playing = CeremonyControls.control(
            step: .hum, chosen: .reading, budget: open, humPhase: .playing
        )
        #expect(playing.title == "Listen")
        #expect(playing.isEnabled == false)

        let ready = CeremonyControls.control(
            step: .hum, chosen: .reading, budget: open, humPhase: .finished
        )
        #expect(ready.title == "Choose a passage")
        #expect(ready.isEnabled)
        #expect(ready.advance == .start(.reading))

        let talk = CeremonyControls.control(
            step: .hum, chosen: .monologue, budget: spent, humPhase: .finished
        )
        #expect(talk.title == "Begin a talk")
        #expect(talk.advance == .start(.monologue))
    }

    @Test("benched steps cannot be pressed")
    func benched() {
        for step in Ceremony.benched {
            let control = CeremonyControls.control(step: step, chosen: .reading, budget: open)
            #expect(control.isEnabled == false)
        }
    }
}

@Suite("Exercise offer")
struct ExerciseOfferTests {
    @Test("an empty week proposes conversation and names what it is")
    func emptyWeek() {
        let offer = ExerciseOfferMaker.offer(counts: WeeklyPracticeCounts(), conversationAvailable: true)
        #expect(offer.proposed == .conversation)
        #expect(offer.alternates == [.reading, .monologue])
        #expect(
            ExerciseOfferMaker.history(
                for: .conversation, counts: WeeklyPracticeCounts(), proposed: .conversation
            ) == nil
        )
    }

    @Test("a spent month is not proposed, even on an empty week")
    func spentMonth() {
        let offer = ExerciseOfferMaker.offer(counts: WeeklyPracticeCounts(), conversationAvailable: false)
        #expect(offer.proposed == .monologue)
        #expect(offer.alternates == [.reading, .conversation])
    }

    @Test("the least practised exercise is proposed, and the reason cites the heavy one")
    func imbalance() {
        let counts = WeeklyPracticeCounts(reading: 3, monologue: 0, conversation: 0)
        let offer = ExerciseOfferMaker.offer(counts: counts, conversationAvailable: true)
        #expect(offer.proposed == .conversation)
        #expect(
            ExerciseOfferMaker.history(for: .conversation, counts: counts, proposed: .conversation)
                == "You've read 3 times this week."
        )
    }

    @Test("overruling the proposal says nothing about the week")
    func override() {
        let counts = WeeklyPracticeCounts(reading: 5, monologue: 0, conversation: 0)
        let offer = ExerciseOfferMaker.offer(counts: counts, conversationAvailable: true)
        #expect(offer.proposed == .conversation)
        #expect(ExerciseOfferMaker.history(for: .reading, counts: counts, proposed: offer.proposed) == nil)
    }

    @Test("one session uses the singular")
    func singular() {
        let counts = WeeklyPracticeCounts(reading: 1, monologue: 0, conversation: 0)
        #expect(
            ExerciseOfferMaker.history(for: .reading, counts: counts, proposed: .reading)
                == "You've read 1 time this week."
        )
    }

    @Test("a tie breaks toward conversation, then monologue")
    func ties() {
        let even = WeeklyPracticeCounts(reading: 2, monologue: 2, conversation: 2)
        #expect(ExerciseOfferMaker.offer(counts: even, conversationAvailable: true).proposed == .conversation)
        #expect(ExerciseOfferMaker.offer(counts: even, conversationAvailable: false).proposed == .monologue)
    }

    @Test("counts only the last seven days")
    func window() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let stamps = [
            PracticeStamp(format: .reading, createdAt: now.addingTimeInterval(-6 * 24 * 60 * 60)),
            PracticeStamp(format: .reading, createdAt: now.addingTimeInterval(-8 * 24 * 60 * 60)),
            PracticeStamp(format: .monologue, createdAt: now),
        ]
        let counts = ExerciseOfferMaker.counts(of: stamps, now: now)
        #expect(counts == WeeklyPracticeCounts(reading: 1, monologue: 1, conversation: 0))
    }
}
