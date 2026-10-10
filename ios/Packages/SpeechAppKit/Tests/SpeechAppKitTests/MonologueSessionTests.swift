import Testing
@testable import SpeechAppKit

@Suite("Monologue session clock")
struct MonologueSessionClockTests {
    @MainActor
    @Test("I'm ready starts take 1 at 4:00 with no warmup")
    func readyStartsTake() {
        let time = ControllableTimeSource(now: 0)
        let session = MonologueSession(
            prompts: ["A familiar topic"],
            store: InMemoryMonologuePromptStore(),
            time: time
        )
        #expect(session.phase == .planning)
        #expect(session.takeNumber == 1)
        session.notes = "keyword outline"
        session.ready()
        #expect(session.phase == .taking)
        #expect(session.remaining == 240)
        #expect(session.store.lastPrompt == "A familiar topic")
        time.advance(10)
        #expect(session.elapsed == 10)
        #expect(session.remaining == 230)
    }

    @MainActor
    @Test("tick samples the clock while time remains so the countdown can move")
    func tickSamplesClockBeforeZero() async {
        let time = ControllableTimeSource(now: 0)
        let session = makeSession(time: time)
        session.ready()
        #expect(session.clockSample == 0)
        time.advance(3)
        await session.tick()
        #expect(session.phase == .taking)
        #expect(session.clockSample == 3)
        #expect(session.remaining == 237)
    }

    @MainActor
    @Test("pause freezes the take clock")
    func pauseFreezes() {
        let time = ControllableTimeSource(now: 0)
        let session = makeSession(time: time)
        session.ready()
        time.advance(5)
        session.pause()
        #expect(session.phase == .paused)
        time.advance(30)
        #expect(session.elapsed == 5)
        session.resume()
        #expect(session.phase == .taking)
        time.advance(2)
        #expect(session.elapsed == 7)
    }

    @MainActor
    @Test("long silence does not auto-pause")
    func silenceStaysOnTape() async {
        let time = ControllableTimeSource(now: 0)
        let session = makeSession(time: time)
        session.ready()
        time.advance(90)
        await session.tick()
        #expect(session.phase == .taking)
        #expect(session.elapsed == 90)
    }

    @MainActor
    @Test("Another topic does not start a take")
    func skipStaysPlanning() {
        let session = MonologueSession(
            prompts: ["one", "two"],
            store: InMemoryMonologuePromptStore(),
            time: ControllableTimeSource()
        )
        session.skipTopic()
        #expect(session.prompt == "two")
        #expect(session.phase == .planning)
    }
}

@Suite("Monologue session takes")
struct MonologueSessionTakeTests {
    @MainActor
    @Test("Done after take 1 goes between with Three minutes")
    func afterTake1() {
        let time = ControllableTimeSource(now: 0)
        let session = makeSession(time: time)
        session.ready()
        time.advance(40)
        session.ingestRanges([ConversationSpeechInterval(start: 0, end: 30)])
        session.ingestText("I take the bus")
        session.done()
        #expect(session.phase == .between)
        #expect(session.betweenCopy == "Three minutes.")
        #expect(session.takeNumber == 2)
        #expect(session.takes.count == 1)
    }

    @MainActor
    @Test("0:00 ends the take the same as Done")
    func zeroEqualsDone() async {
        let time = ControllableTimeSource(now: 0)
        let session = makeSession(time: time)
        session.ready()
        time.advance(240)
        await session.tick()
        #expect(session.phase == .between)
        #expect(session.takes.first?.wallSeconds == 240)
    }

    @MainActor
    @Test("take 3 Done opens the report")
    func take3Report() {
        let time = ControllableTimeSource(now: 0)
        let session = makeSession(time: time)
        for _ in 1...3 {
            session.ready()
            time.advance(35)
            session.ingestRanges([ConversationSpeechInterval(start: 0, end: 30)])
            session.ingestText("I take the bus to work every day")
            session.done()
        }
        #expect(session.phase == .report)
        #expect(session.report?.kind == .full)
        #expect(session.report?.endReason == .completed)
    }

    @MainActor
    @Test("between copy after take 2 is Two minutes")
    func afterTake2() {
        let time = ControllableTimeSource(now: 0)
        let session = makeSession(time: time)
        session.ready(); time.advance(35); session.done()
        session.ready(); time.advance(35); session.done()
        #expect(session.phase == .between)
        #expect(session.betweenCopy == "Two minutes.")
        #expect(session.takeNumber == 3)
    }

    @MainActor
    @Test("ingestWords keeps file-timed words on the take and drops pause words")
    func retainsWords() {
        let time = ControllableTimeSource(now: 0)
        let session = makeSession(time: time)
        session.ready()
        session.ingestWords([
            SpokenToken(surface: "I", startTime: 0.1, endTime: 0.2, isFinal: true),
            SpokenToken(surface: "went", startTime: 0.3, endTime: 0.5, isFinal: true),
        ])
        session.pause(atStreamTime: 1.0)
        // Would be spoken during pause — must not land on the take.
        session.ingestWords([
            SpokenToken(surface: "I", startTime: 0.1, endTime: 0.2, isFinal: true),
            SpokenToken(surface: "went", startTime: 0.3, endTime: 0.5, isFinal: true),
            SpokenToken(surface: "nope", startTime: 1.2, endTime: 1.4, isFinal: true),
        ])
        #expect(session.phase == .paused)
        session.resume(atStreamTime: 3.0)
        session.ingestWords([
            SpokenToken(surface: "I", startTime: 0.1, endTime: 0.2, isFinal: true),
            SpokenToken(surface: "went", startTime: 0.3, endTime: 0.5, isFinal: true),
            SpokenToken(surface: "home", startTime: 3.1, endTime: 3.4, isFinal: true),
        ])
        time.advance(40)
        session.done()
        let words = session.takes.first?.words ?? []
        #expect(words.map(\.surface) == ["I", "went", "home"])
        // Origin bound to first word (0.1); pause 1.0…3.0 → home at 3.1 maps to 1.0.
        #expect(words.last?.start == 1.0)
    }
}

@Suite("Monologue session crisis and leave")
struct MonologueSessionCrisisTests {
    @MainActor
    @Test("keyword crisis skips the fluency report")
    func crisis() {
        let session = makeSession()
        session.ready()
        session.ingestText("I want to kill myself")
        #expect(session.phase == .crisis)
        #expect(session.report?.kind == .crisis)
        #expect(session.report?.lines.isEmpty == true)
    }

    @MainActor
    @Test("empty Apple text is not 988")
    func emptyNotCrisis() {
        let session = makeSession()
        session.ready()
        session.ingestText("   ")
        #expect(session.phase == .taking)
    }

    @MainActor
    @Test("Back after a counting take opens a report")
    func leaveOpensReport() {
        let time = ControllableTimeSource(now: 0)
        let session = makeSession(time: time)
        session.ready()
        time.advance(40)
        session.ingestRanges([ConversationSpeechInterval(start: 0, end: 30)])
        session.confirmLeave()
        #expect(session.phase == .report)
        #expect(session.report?.kind == .thin)
        #expect(session.report?.endReason == .leftEarly)
    }

    @MainActor
    @Test("Back on planning with no take does not fabricate a report")
    func leavePlanning() {
        let session = makeSession()
        session.confirmLeave()
        #expect(session.phase == .planning)
        #expect(session.report == nil)
    }
}

@MainActor
private func makeSession(
    time: ControllableTimeSource = ControllableTimeSource(now: 0),
    store: any MonologuePromptStore = InMemoryMonologuePromptStore()
) -> MonologueSession {
    MonologueSession(prompts: ["Talk about breakfast"], store: store, time: time)
}
