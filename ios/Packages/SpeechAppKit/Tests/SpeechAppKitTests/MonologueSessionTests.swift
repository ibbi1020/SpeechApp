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

@MainActor
private func makeSession(
    time: ControllableTimeSource = ControllableTimeSource(now: 0),
    store: any MonologuePromptStore = InMemoryMonologuePromptStore()
) -> MonologueSession {
    MonologueSession(prompts: ["Talk about breakfast"], store: store, time: time)
}
