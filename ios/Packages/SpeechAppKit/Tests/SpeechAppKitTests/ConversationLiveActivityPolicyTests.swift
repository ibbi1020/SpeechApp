import Foundation
import Testing
@testable import SpeechAppKit

struct ConversationLiveActivityPolicyTests {
    private let started = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("no activity before the talk, or before the first partner audio")
    func waitsForTalkAndClock() {
        #expect(ConversationLiveActivityPolicy.command(for: input(phase: .countdown, startedAt: nil)) == .none)
        #expect(ConversationLiveActivityPolicy.command(for: input(phase: .connecting, startedAt: nil)) == .none)
        #expect(ConversationLiveActivityPolicy.command(for: input(phase: .talking, startedAt: nil)) == .none)
    }

    @Test("first partner audio starts one activity")
    func startsOnceClockRuns() {
        let command = ConversationLiveActivityPolicy.command(for: input(phase: .talking, startedAt: started))
        guard case .start(let snapshot) = command else {
            Issue.record("expected start, got \(command)")
            return
        }
        #expect(snapshot.phase == .talking)
        #expect(snapshot.timerStart == started)
        #expect(snapshot.pauseTime == nil)
        #expect(snapshot.timerEnd == started.addingTimeInterval(15 * 60))
    }

    @Test("a live activity updates instead of starting a second one")
    func oneActivity() {
        let command = ConversationLiveActivityPolicy.command(
            for: input(phase: .talking, startedAt: started, activityIsLive: true)
        )
        guard case .update = command else {
            Issue.record("expected update, got \(command)")
            return
        }
    }

    @Test("pause freezes the timer and resume shifts the origin by the pause")
    func pauseAndResume() {
        let pauseBegan = started.addingTimeInterval(60)
        let paused = ConversationLiveActivityPolicy.command(
            for: input(
                phase: .paused,
                startedAt: started,
                pauseBeganAt: pauseBegan,
                activityIsLive: true
            )
        )
        guard case .update(let frozen) = paused else {
            Issue.record("expected paused update")
            return
        }
        #expect(frozen.phase == .paused)
        #expect(frozen.orb == .paused)
        #expect(frozen.pauseTime == pauseBegan)
        #expect(frozen.timerStart == started)

        let resumed = ConversationLiveActivityPolicy.command(
            for: input(
                phase: .talking,
                startedAt: started,
                pausedAccumulated: 60,
                activityIsLive: true
            )
        )
        guard case .update(let running) = resumed else {
            Issue.record("expected resumed update")
            return
        }
        #expect(running.pauseTime == nil)
        #expect(running.timerStart == started.addingTimeInterval(60))
    }

    @Test("report, drop, crisis, and leaving end a live activity")
    func ends() {
        for phase in [ConversationPhase.report, .dropped, .crisis] {
            let command = ConversationLiveActivityPolicy.command(
                for: input(phase: phase, startedAt: started, activityIsLive: true)
            )
            #expect(command == .end)
        }
        let leaving = ConversationLiveActivityPolicy.command(
            for: input(phase: .talking, startedAt: started, activityIsLive: true, leaving: true)
        )
        #expect(leaving == .end)
    }

    @Test("ending states do nothing when no activity is up")
    func endIsQuietWhenIdle() {
        #expect(
            ConversationLiveActivityPolicy.command(for: input(phase: .report, startedAt: started)) == .none
        )
    }

    @Test(arguments: [PracticeFormat.Kind.reading, .monologue])
    func otherExercisesNeverCommand(_ kind: PracticeFormat.Kind) {
        let command = ConversationLiveActivityPolicy.command(
            for: input(exercise: kind, phase: .talking, startedAt: started, activityIsLive: false)
        )
        #expect(command == .none)
    }

    @Test("phrase is trimmed to eighty characters")
    func truncatesPhrase() {
        let long = String(repeating: "word ", count: 30)
        let command = ConversationLiveActivityPolicy.command(
            for: input(phase: .talking, startedAt: started, phrase: long)
        )
        guard case .start(let snapshot) = command else {
            Issue.record("expected start")
            return
        }
        #expect(snapshot.phrase.count <= ConversationLiveActivityPolicy.phraseLimit)
        #expect(snapshot.phrase.hasSuffix("…"))
    }

    @Test("the live phrase stays off every island surface")
    func captionSurfaces() {
        #expect(ConversationLiveActivityPolicy.showsPhrase(on: .expanded) == false)
        #expect(ConversationLiveActivityPolicy.showsPhrase(on: .lockScreen) == false)
        #expect(ConversationLiveActivityPolicy.showsPhrase(on: .compact) == false)
        #expect(ConversationLiveActivityPolicy.showsPhrase(on: .minimal) == false)
    }

    @Test("pause is only on expanded and Lock Screen, and only while talking or paused")
    func pauseSurfaces() {
        #expect(ConversationLiveActivityPolicy.showsPause(on: .expanded, phase: .talking))
        #expect(ConversationLiveActivityPolicy.showsPause(on: .expanded, phase: .paused))
        #expect(ConversationLiveActivityPolicy.showsPause(on: .expanded, phase: .wrapping) == false)
        #expect(ConversationLiveActivityPolicy.showsPause(on: .lockScreen, phase: .talking))
        #expect(ConversationLiveActivityPolicy.showsPause(on: .compact, phase: .talking) == false)
        #expect(ConversationLiveActivityPolicy.showsPause(on: .minimal, phase: .paused) == false)
    }

    @Test("stop is only on expanded and Lock Screen")
    func stopSurfaces() {
        #expect(ConversationLiveActivityPolicy.showsStop(on: .expanded))
        #expect(ConversationLiveActivityPolicy.showsStop(on: .lockScreen))
        #expect(ConversationLiveActivityPolicy.showsStop(on: .compact) == false)
        #expect(ConversationLiveActivityPolicy.showsStop(on: .minimal) == false)
    }

    @Test("limited width compact is the orb only")
    func limitedWidth() {
        #expect(
            ConversationLiveActivityPolicy.showsTimer(on: .compact, limitedWidth: true) == false
        )
        #expect(ConversationLiveActivityPolicy.showsTimer(on: .compact, limitedWidth: false))
        #expect(
            ConversationLiveActivityPolicy.showsTimer(on: .minimal, limitedWidth: true) == false
        )
    }

    @Test("orb follows who is speaking, and pause is its own look")
    func orbLooks() {
        #expect(
            ConversationLiveActivityPolicy.orb(phase: .paused, floor: .partner, agentSpeaking: false) == .paused
        )
        #expect(
            ConversationLiveActivityPolicy.orb(phase: .talking, floor: .partner, agentSpeaking: true) == .speaking
        )
        #expect(
            ConversationLiveActivityPolicy.orb(phase: .talking, floor: .user, agentSpeaking: false) == .listening
        )
    }

    @Test("open link round-trips the conversation id")
    func link() throws {
        let id = UUID()
        let url = try #require(ConversationLiveActivityLink.url(for: id))
        #expect(ConversationLiveActivityLink.conversationID(from: url) == id)
        #expect(ConversationLiveActivityLink.conversationID(from: URL(string: "https://example.com")!) == nil)
    }

    private func input(
        exercise: PracticeFormat.Kind = .conversation,
        phase: ConversationPhase,
        floor: ConversationFloorOwner = .partner,
        agentSpeaking: Bool = false,
        startedAt: Date? = nil,
        pausedAccumulated: TimeInterval = 0,
        pauseBeganAt: Date? = nil,
        phrase: String = "Tell me about your week.",
        phraseIsPartner: Bool = true,
        activityIsLive: Bool = false,
        leaving: Bool = false
    ) -> ConversationLiveActivityInput {
        ConversationLiveActivityInput(
            exercise: exercise,
            phase: phase,
            floor: floor,
            agentSpeaking: agentSpeaking,
            startedAt: startedAt,
            pausedAccumulated: pausedAccumulated,
            pauseBeganAt: pauseBeganAt,
            phrase: phrase,
            phraseIsPartner: phraseIsPartner,
            activityIsLive: activityIsLive,
            leaving: leaving
        )
    }
}
