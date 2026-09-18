import Foundation
import Testing
@testable import SpeechAppKit

@Suite("PresenceWalk")
struct PresenceWalkTests {
    private let wordIDs = (0..<12).map { "w\($0)" }
    private var syllables: [String: Int] {
        Dictionary(uniqueKeysWithValues: wordIDs.map { ($0, 1) })
    }

    @Test("sustained speaking advances presence past first word")
    func advancesPastFirstWord() {
        let state = PresenceWalkState(presenceWordID: "w0")
        let duration = PresenceWalk.syllableDuration(syllableCount: 1)

        let (started, _) = PresenceWalk.tick(
            state: state,
            speaking: true,
            now: 0,
            wordIDs: wordIDs,
            syllableCounts: syllables,
            asrWordID: "w0",
            heardIDs: []
        )
        #expect(started.presenceWordID == "w0")
        #expect(started.presenceProgress == 0)

        let (advanced, event) = PresenceWalk.tick(
            state: started,
            speaking: true,
            now: duration,
            wordIDs: wordIDs,
            syllableCounts: syllables,
            asrWordID: "w0",
            heardIDs: []
        )
        #expect(advanced.presenceWordID == "w1")
        #expect(advanced.presenceTrailIDs.contains("w0"))
        #expect(event == .advanced(from: "w0", to: "w1"))
    }

    @Test("presence cannot walk more than 8 words ahead of frozen ASR")
    func eightWordCap() {
        var state = PresenceWalkState(presenceWordID: "w0")
        var now: TimeInterval = 0
        let step = PresenceWalk.syllableDuration(syllableCount: 1) + 0.05

        for _ in 0..<20 {
            let (next, _) = PresenceWalk.tick(
                state: state,
                speaking: true,
                now: now,
                wordIDs: wordIDs,
                syllableCounts: syllables,
                asrWordID: "w0",
                heardIDs: []
            )
            state = next
            now += step
        }

        let presenceIndex = wordIDs.firstIndex(of: state.presenceWordID ?? "") ?? -1
        #expect(presenceIndex == PresenceWalk.maxWordsAhead)
        #expect(state.presenceTrailIDs.count == PresenceWalk.maxWordsAhead)
        #expect(state.presenceProgress == 1)
    }

    @Test("ASR catch-up snaps presence and clears trail behind caret")
    func asrSnapClearsTrail() {
        let state = PresenceWalkState(
            presenceWordID: "w5",
            presenceProgress: 0.4,
            presenceTrailIDs: ["w0", "w1", "w2", "w3", "w4"]
        )
        let heard: Set<String> = ["w0", "w1", "w2", "w3", "w4", "w5"]
        let (snapped, event) = PresenceWalk.reconcile(
            state: state,
            asrWordID: "w6",
            wordIDs: wordIDs,
            heardIDs: heard,
            speaking: true,
            now: 10
        )
        #expect(snapped.presenceWordID == "w6")
        #expect(snapped.presenceProgress == 0)
        #expect(snapped.presenceTrailIDs.isEmpty)
        #expect(event == .snapped(to: "w6"))
    }

    @Test("silence decays fill but does not rewind presence index")
    func silenceDoesNotRewind() {
        let state = PresenceWalkState(
            presenceWordID: "w3",
            presenceProgress: 0.7,
            presenceTrailIDs: ["w0", "w1", "w2"],
            fillWordID: "w3",
            speechStartedAt: 1
        )
        let (afterSilence, event) = PresenceWalk.tick(
            state: state,
            speaking: false,
            now: 5,
            wordIDs: wordIDs,
            syllableCounts: syllables,
            asrWordID: "w0",
            heardIDs: []
        )
        #expect(afterSilence.presenceWordID == "w3")
        #expect(afterSilence.presenceTrailIDs == ["w0", "w1", "w2"])
        #expect(afterSilence.presenceProgress < 0.7)
        #expect(event == nil)
    }

    @Test("ASR still behind presence leaves presence ahead")
    func asrBehindLeavesPresence() {
        let state = PresenceWalkState(
            presenceWordID: "w6",
            presenceProgress: 0.2,
            presenceTrailIDs: ["w1", "w2", "w3", "w4", "w5"]
        )
        let (next, event) = PresenceWalk.reconcile(
            state: state,
            asrWordID: "w2",
            wordIDs: wordIDs,
            heardIDs: ["w0", "w1"],
            speaking: true,
            now: 3
        )
        #expect(next.presenceWordID == "w6")
        #expect(next.presenceProgress == 0.2)
        #expect(!next.presenceTrailIDs.contains("w1"))
        #expect(next.presenceTrailIDs.contains("w3"))
        #expect(event == nil)
    }
}
