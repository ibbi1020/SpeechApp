import Foundation
import Testing
@testable import SpeechAppKit

@Suite("Caret follow")
struct CaretFollowTests {
    @Test("a burst sweeps through each word instead of landing on the last one")
    func burstSweepsInOrder() {
        var follow = CaretFollow()
        follow.noteAnchor(index: 0, speechEnd: 0, hostNow: 0)
        follow.noteAnchor(index: 4, speechEnd: 1.2, hostNow: 2)
        var now = 2.0
        follow.tick(hostNow: now, speaking: true)

        for word in 1...4 {
            now += CaretFollow.secondsPerWord
            follow.tick(hostNow: now, speaking: true)
            #expect(follow.displayWordIndex == word)
        }
    }

    @Test("silence freezes the mark even if the last pace would keep going")
    func silenceFreezes() {
        var follow = CaretFollow()
        follow.noteAnchor(index: 0, speechEnd: 0, hostNow: 0)
        follow.tick(hostNow: 0, speaking: true)
        follow.tick(hostNow: 0.1, speaking: true)
        let mid = follow.displayPosition

        follow.tick(hostNow: 0.8, speaking: false)
        #expect(follow.displayPosition == mid)
    }

    @Test("half a second of speech leads by at most one word")
    func coastClampsToOneWord() {
        var follow = CaretFollow()
        follow.noteAnchor(index: 1, speechEnd: 0.4, hostNow: 5)
        follow.tick(hostNow: 5, speaking: true)
        follow.tick(hostNow: 5.5, speaking: true)

        #expect(follow.confirmedIndex == 1)
        #expect(follow.displayPosition >= 1.99)
        #expect(follow.displayPosition <= 2.001)
    }

    @Test("a revised hypothesis behind the mark does not pull it backward")
    func neverRewinds() {
        var follow = CaretFollow()
        follow.noteAnchor(index: 4, speechEnd: 1, hostNow: 0)
        follow.noteAnchor(index: 2, speechEnd: 0.4, hostNow: 0.2)
        #expect(follow.confirmedIndex == 4)

        follow.tick(hostNow: 0, speaking: false)
        follow.tick(hostNow: 0.5, speaking: false)
        #expect(follow.displayWordIndex == 4)
        #expect(follow.displayPosition == 4)
    }

    @Test("reduce motion snaps to the confirmed word")
    func reduceMotionSnaps() {
        var follow = CaretFollow()
        follow.noteAnchor(index: 4, speechEnd: 1, hostNow: 0)
        follow.tick(hostNow: 0, speaking: false, reduceMotion: true)
        #expect(follow.displayWordIndex == 4)
    }

    @Test("the lead stops on the last word")
    func leadStopsAtEnd() {
        var follow = CaretFollow(wordCount: 3)
        follow.noteAnchor(index: 2, speechEnd: 0.4, hostNow: 0)
        follow.tick(hostNow: 0, speaking: true)
        follow.tick(hostNow: 1, speaking: true)
        #expect(follow.displayWordIndex == 2)
        #expect(follow.displayPosition <= 2)
    }

    @Test("session anchor moves forward with the aligned word")
    @MainActor
    func sessionAnchorAdvances() async throws {
        let passage = Passage(
            id: "caret",
            title: "Caret",
            words: [
                ScriptWord(id: "w0", surface: "the"),
                ScriptWord(id: "w1", surface: "quick"),
                ScriptWord(id: "w2", surface: "fox"),
            ]
        )
        let session = ReadingSession(passage: passage, stallTimeout: 30)
        let url = try #require(Bundle.module.url(forResource: "silence", withExtension: "wav"))
        let source = FileReplayAudioSource(fileURL: url, chunkDuration: 0.05)
        let engine = ScriptedTranscriptEngine(
            words: passage.words.map(\.surface),
            wordInterval: 0.05,
            emitVolatiles: true
        )
        try await session.start(audioSource: source, engine: engine)
        await engine.waitUntilFinished()
        try await Task.sleep(for: .milliseconds(50))
        #expect(session.caretAnchor.index >= 2)
        #expect(session.caretAnchor.hostTime > 0)
        _ = await session.stop()
    }
}
