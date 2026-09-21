import Foundation
import Testing
@testable import SpeechAppKit

@Suite("ConversationSession")
struct ConversationSessionTests {
    @MainActor
    func makeSession(
        cap: TimeInterval = 15 * 60,
        mouth: FakeConversationMouth = FakeConversationMouth()
    ) -> (ConversationSession, FakeConversationMouth, ControllableTimeSource) {
        let time = ControllableTimeSource(now: 0)
        let session = ConversationSession(
            time: time,
            mouth: mouth,
            cap: cap,
            prefix: "PREFIX",
            stance: "STANCE",
            openQuestion: "What did you have for breakfast?"
        )
        return (session, mouth, time)
    }

    @Test("clock does not start at countdown zero")
    @MainActor
    func clockStartsOnFirstAudio() async throws {
        let (session, mouth, _) = makeSession(cap: 300)
        session.beginCountdown()
        #expect(session.phase == .countdown)
        try await session.countdownReachedZero(ephemeralKey: "ek")
        #expect(session.phase == .connecting)
        #expect(session.countsAsBudgetStart == false)
        await session.handle(.sessionUpdated)
        #expect(mouth.responseCreates.count == 1)
        #expect(mouth.responseCreates[0].contains("breakfast"))
        await session.handle(.audioDelta)
        #expect(session.phase == .talking)
        #expect(session.countsAsBudgetStart == true)
        #expect(session.elapsed == 0)
    }

    @Test("user stop never sends wrap_close")
    @MainActor
    func userStopSilent() async throws {
        let (session, mouth, _) = makeSession()
        try await reachTalking(session)
        session.requestStop()
        await session.confirmStop()
        #expect(session.phase == .report)
        #expect(session.report?.endReason == .userStop)
        #expect(mouth.responseCreates.allSatisfy { !$0.lowercased().contains("close the conversation") })
        #expect(mouth.didClose)
    }

    @Test("wrap_warn queues at T-2 min")
    @MainActor
    func wrapWarn() async throws {
        let (session, mouth, time) = makeSession(cap: 180)
        try await reachTalking(session)
        time.advance(60)
        await session.tick()
        session.ingestUserText("eggs")
        await session.handle(.speechStopped)
        #expect(mouth.responseCreates.contains { $0.contains("two minutes") })
    }

    @Test("1.5 min silence auto-pauses after they have spoken")
    @MainActor
    func autoPause() async throws {
        let (session, _, time) = makeSession()
        try await reachTalking(session)
        session.ingestUserText("hello")
        session.noteUserSpeech(seconds: 1)
        await session.handle(.speechStopped)
        time.advance(90)
        await session.tick()
        #expect(session.phase == .paused)
        time.advance(30)
        await session.tick()
        #expect(session.elapsed == 90)
        session.resume()
        #expect(session.phase == .talking)
    }

    @Test("silence before they speak does not auto-pause")
    @MainActor
    func noPauseBeforeFirstUserTurn() async throws {
        let (session, _, time) = makeSession()
        try await reachTalking(session)
        time.advance(90)
        await session.tick()
        #expect(session.phase == .talking)
    }

    @Test("pause TTL 10 min hangs up with no close")
    @MainActor
    func pauseTTL() async throws {
        let (session, mouth, time) = makeSession()
        try await reachTalking(session)
        session.pause()
        time.advance(600)
        await session.tick()
        #expect(session.phase == .report)
        #expect(session.report?.endReason == .pauseTTL)
        #expect(mouth.turnDetectionNulled == false)
    }

    @Test("keyword crisis skips fluency report")
    @MainActor
    func crisis() async throws {
        let (session, mouth, _) = makeSession()
        try await reachTalking(session)
        session.ingestUserText("I want to kill myself")
        await session.handle(.speechStopped)
        #expect(session.phase == .crisis)
        #expect(session.report?.kind == .crisis)
        #expect(mouth.responseCreates.count == 1)
    }

    @Test("spoken minor sets flag and skips 988")
    @MainActor
    func possibleMinor() async throws {
        let (session, mouth, _) = makeSession()
        try await reachTalking(session)
        session.ingestUserText("I am a minor")
        await session.handle(.speechStopped)
        #expect(session.possibleMinorFlag == true)
        #expect(session.phase == .report)
        #expect(session.report?.kind != .crisis)
        #expect(mouth.responseCreates.count == 1)
    }

    @Test("v1 never sends codeSwitch cue")
    @MainActor
    func noCodeSwitch() async throws {
        let (session, mouth, _) = makeSession()
        try await reachTalking(session)
        session.queueIfAllowed(.codeSwitch)
        session.ingestUserText("hello")
        await session.handle(.speechStopped)
        #expect(mouth.responseCreates.allSatisfy { !$0.lowercased().contains("english") })
        #expect(mouth.responseCreates.count == 2) // open + continue, never a code-switch aside
    }

    @Test("ghost speech_started without stop gets no reply")
    @MainActor
    func ghost() async throws {
        let (session, mouth, time) = makeSession()
        try await reachTalking(session)
        await session.handle(.speechStarted)
        session.ingestUserText("hi")
        time.advance(8)
        await session.tick()
        await session.handle(.speechStopped)
        #expect(mouth.responseCreates.count == 1)
    }

    @Test("ghost turn still evaluates crisis keywords")
    @MainActor
    func ghostTurnStillEvaluatesCrisis() async throws {
        let (session, mouth, time) = makeSession()
        try await reachTalking(session)
        session.ingestUserText("I want to kill myself")
        await session.handle(.speechStarted)
        time.advance(8)
        await session.tick()
        await session.handle(.speechStopped)
        #expect(session.phase == .crisis)
        #expect(session.report?.kind == .crisis)
        #expect(mouth.responseCreates.count == 1)
    }

    @Test("silent at cap skips spoken close")
    @MainActor
    func skipCloseWhenSilentAtCap() async throws {
        let (session, mouth, time) = makeSession(cap: 60)
        try await reachTalking(session)
        session.ingestUserText("hi")
        await session.handle(.speechStopped)
        time.advance(60)
        await session.tick()
        #expect(session.phase == .report)
        #expect(session.report?.endReason == .wrap)
        #expect(mouth.responseCreates.allSatisfy { !$0.lowercased().contains("close the conversation") })
    }

    @Test("open ignore retries once")
    @MainActor
    func openRetry() async throws {
        let (session, mouth, _) = makeSession()
        try await reachTalking(session)
        await session.handle(.responseDone(transcript: "Sure."))
        #expect(mouth.responseCreates.filter { $0.contains("breakfast") }.count == 2)
    }

    @Test("first audio watchdog retries then drops")
    @MainActor
    func firstAudioWatchdog() async throws {
        let (session, mouth, time) = makeSession()
        session.beginCountdown()
        try await session.countdownReachedZero(ephemeralKey: "ek")
        await session.handle(.sessionUpdated)
        #expect(mouth.responseCreates.count == 1)
        time.advance(8)
        await session.tick()
        #expect(mouth.responseCreates.count == 2)
        time.advance(8)
        await session.tick()
        #expect(session.phase == .dropped)
    }

    @Test("user stop after wrap close started never sends wrap_close")
    @MainActor
    func userStopDuringWrapping() async throws {
        let (session, mouth, time) = makeSession(cap: 60)
        try await reachTalking(session)
        await session.handle(.speechStarted)
        time.advance(60)
        await session.tick()
        #expect(mouth.turnDetectionNulled == true)
        await session.confirmStop()
        await session.handle(.sessionUpdated)
        #expect(session.phase == .report)
        #expect(session.report?.endReason == .userStop)
        #expect(mouth.responseCreates.allSatisfy { !$0.lowercased().contains("close the conversation") })
    }

    @Test("thin report under 45s")
    @MainActor
    func thinReport() async throws {
        let (session, _, _) = makeSession()
        try await reachTalking(session)
        session.noteUserSpeech(seconds: 10)
        await session.confirmStop()
        #expect(session.report?.kind == .thin)
        #expect(session.report?.lines.count == 2)
        #expect(session.report?.lines.contains(where: { $0.label == "Pace" }) == false)
        #expect(session.report?.lines.contains(where: { $0.label == "Pause time" }) == false)
    }

    @Test("full report attaches pace and pause time")
    @MainActor
    func fullReportExtraLines() async throws {
        let (session, mouth, time) = makeSession()
        try await reachTalking(session)
        let createsBefore = mouth.responseCreates.count
        for _ in 0..<3 {
            await session.handle(.speechStarted)
            time.advance(20)
            session.noteUserSpeech(seconds: 20)
            session.ingestUserText("hello")
            await session.handle(.speechStopped)
            time.advance(0.5)
        }
        #expect(mouth.responseCreates.count == createsBefore + 3)
        await session.confirmStop()
        let report = try #require(session.report)
        #expect(report.kind == .full)
        #expect(report.limitedAnalysis == false)
        #expect(report.lines.contains(where: { $0.label == "Time spoken" && !$0.value.contains("uncertain") }))
        #expect(report.lines.contains(where: { $0.label == "Pace" && $0.value == "6 syl/min" }))
        #expect(report.lines.contains(where: { $0.label == "Pause time" && $0.value == "1.0s" }))
        #expect(!report.lines.contains(where: { $0.label == "Slips" }))
        #expect(!report.lines.contains(where: { $0.label == "Filled pauses" }))
        #expect(!report.lines.contains(where: { $0.value.lowercased().contains("too fast") }))
        #expect(!report.lines.contains(where: { $0.label.lowercased().contains("grammar") }))
        #expect(!report.lines.contains(where: { $0.label.lowercased().contains("pmi") }))
    }

    @Test("uncertain coverage omits pace and pause on a full report")
    @MainActor
    func uncertainOmitsExtraLines() async throws {
        let (session, _, time) = makeSession()
        try await reachTalking(session)
        for _ in 0..<3 {
            await session.handle(.speechStarted)
            time.advance(2)
            session.noteUserSpeech(seconds: 20)
            session.ingestUserText("hello")
            await session.handle(.speechStopped)
            time.advance(0.5)
        }
        await session.confirmStop()
        let report = try #require(session.report)
        #expect(report.kind == .full)
        #expect(report.limitedAnalysis)
        #expect(report.lines.contains(where: { $0.label == "Time spoken" && $0.value.contains("uncertain") }))
        #expect(!report.lines.contains(where: { $0.label == "Pace" }))
        #expect(!report.lines.contains(where: { $0.label == "Pause time" }))
    }

    @Test("configDrift hangups with that reason")
    @MainActor
    func configDriftHangup() async throws {
        let (session, mouth, _) = makeSession()
        try await reachTalking(session)
        await session.handle(.configDrift)
        #expect(session.phase == .report)
        #expect(session.report?.endReason == .configDrift)
        #expect(mouth.didClose)
    }

    @MainActor
    private func reachTalking(_ session: ConversationSession) async throws {
        session.beginCountdown()
        try await session.countdownReachedZero(ephemeralKey: "ek")
        await session.handle(.sessionUpdated)
        await session.handle(.audioDelta)
    }
}
