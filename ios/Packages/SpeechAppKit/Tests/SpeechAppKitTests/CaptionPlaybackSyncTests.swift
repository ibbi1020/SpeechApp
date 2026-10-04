import Testing
@testable import SpeechAppKit

struct CaptionPlaybackSyncTests {
    private let sampleRate = CaptionPlaybackSync.sampleRate

    @Test("no characters unlocked before any audio has finished")
    func zeroUntilPlayback() {
        #expect(CaptionPlaybackSync.characterBudget(completedFrames: 0) == 0)
        #expect(revealedWords(["One", "two", "three"], frames: 0) == 0)
    }

    @Test("one second of heard audio unlocks a short line of whole words")
    func oneSecondUnlocksShortLine() {
        let frames = Int(sampleRate) // 1.0 s → budget 18
        #expect(CaptionPlaybackSync.characterBudget(completedFrames: frames) == 18)

        // "One two three four" = 18 chars; " five" does not fit.
        #expect(revealedWords(["One", "two", "three", "four", "five"], frames: frames) == 4)
        #expect(
            CaptionPlaybackSync.revealedPrefix(
                transcript: "One two three four five",
                completedFrames: frames
            ) == "One two three four"
        )
    }

    @Test("audio finished flushes every remaining word")
    func audioFinishedFlushesAll() {
        #expect(
            CaptionPlaybackSync.revealedWordCount(
                words: ["One", "two", "three", "four"],
                completedFrames: 1_000,
                audioFinished: true
            ) == 4
        )
        #expect(
            CaptionPlaybackSync.revealedPrefix(
                transcript: "One two three four",
                completedFrames: 1_000,
                audioFinished: true
            ) == "One two three four"
        )
    }

    @Test("first word surfaces once there is any character credit")
    func firstWordWithTinyBudget() {
        // 0.1 s → budget 1, shorter than "Hello", still show the first word.
        let frames = Int(sampleRate * 0.1)
        #expect(CaptionPlaybackSync.characterBudget(completedFrames: frames) == 1)
        #expect(revealedWords(["Hello", "there"], frames: frames) == 1)
    }

    private func revealedWords(_ words: [String], frames: Int) -> Int {
        CaptionPlaybackSync.revealedWordCount(
            words: words,
            completedFrames: frames,
            audioFinished: false
        )
    }
}

struct CaptionAudioLedgerTests {
    private let oneSecond = Int(CaptionPlaybackSync.sampleRate)

    @Test("transcript alone does not reveal words")
    func transcriptWaitsForAudio() {
        var ledger = CaptionAudioLedger()
        ledger.appendTranscript("Hello there friend")
        #expect(ledger.revealedCaption() == "")
    }

    @Test("first completed buffer unlocks a short line from heard seconds")
    func firstBufferShowsLine() {
        var ledger = CaptionAudioLedger()
        ledger.appendTranscript("Hello there friend")
        ledger.enqueueAudio(frames: 2_400)
        ledger.enqueueAudio(frames: 2_400)
        ledger.enqueueAudio(frames: 2_400)
        #expect(ledger.completeAudio(frames: 2_400) == "Hello")
    }

    @Test("long queued tail does not hold the line back")
    func queuedTailDoesNotBlock() {
        var ledger = CaptionAudioLedger()
        ledger.appendTranscript("One two three four five six seven eight")
        // Huge future queue — old proportional math would under-reveal.
        ledger.enqueueAudio(frames: 240_000)
        _ = ledger.completeAudio(frames: oneSecond)
        #expect(ledger.revealedCaption() == "One two three four")
    }

    @Test("heard seconds unlock words independent of total queue")
    func completesByHeardSeconds() {
        var ledger = CaptionAudioLedger()
        ledger.appendTranscript("One two three four five six seven")
        ledger.enqueueAudio(frames: oneSecond * 2)
        _ = ledger.completeAudio(frames: oneSecond)
        #expect(ledger.revealedCaption() == "One two three four")
        _ = ledger.completeAudio(frames: oneSecond)
        #expect(ledger.revealedCaption() == "One two three four five six seven")
    }

    @Test("catching the audio queue mid-reply does not dump the rest")
    func queueCatchUpDoesNotFlush() {
        var ledger = CaptionAudioLedger()
        ledger.appendTranscript("One two three four five six seven")
        ledger.enqueueAudio(frames: 2_400)
        _ = ledger.completeAudio(frames: 2_400)
        #expect(ledger.completedFrames == ledger.queuedFrames)
        #expect(ledger.revealedCaption() == "One")
    }

    @Test("late transcript catches up to already-heard audio")
    func lateTranscriptCatchesUp() {
        var ledger = CaptionAudioLedger()
        ledger.enqueueAudio(frames: oneSecond)
        _ = ledger.completeAudio(frames: oneSecond)
        #expect(ledger.revealedCaption() == "")
        ledger.appendTranscript("One two three four five six seven")
        #expect(ledger.revealedCaption() == "One two three four")
    }

    @Test("late transcript mid-play uses saved heard credit")
    func lateTranscriptMidPlay() {
        var ledger = CaptionAudioLedger()
        ledger.enqueueAudio(frames: oneSecond * 2)
        _ = ledger.completeAudio(frames: oneSecond)
        #expect(ledger.revealedCaption() == "")
        ledger.appendTranscript("One two three four five six seven")
        #expect(ledger.revealedCaption() == "One two three four")
    }

    @Test("revealed word count never shrinks when more audio is queued")
    func monotonicReveal() {
        var ledger = CaptionAudioLedger()
        ledger.appendTranscript("One two three four")
        ledger.enqueueAudio(frames: oneSecond)
        _ = ledger.completeAudio(frames: oneSecond)
        let mid = ledger.revealedWordCount
        ledger.enqueueAudio(frames: 240_000)
        #expect(ledger.revealedCaption().split(separator: " ").count >= mid)
    }

    @Test("forceFull shows leftover words")
    func forceFullDrain() {
        var ledger = CaptionAudioLedger()
        ledger.appendTranscript("One two three four five six")
        ledger.enqueueAudio(frames: 2_400)
        _ = ledger.completeAudio(frames: 2_400)
        #expect(ledger.revealedCaption(forceFull: true) == "One two three four five six")
    }

    @Test("heard frames during a buffer unlock words before it finishes")
    func heardDuringBuffer() {
        var ledger = CaptionAudioLedger()
        ledger.appendTranscript("One two three four five six seven")
        ledger.enqueueAudio(frames: oneSecond * 3)
        ledger.noteHeard(frames: oneSecond)
        #expect(ledger.revealedCaption() == "One two three four")
        #expect(ledger.completedFrames == 0)
    }
}

struct CaptionPlayheadTests {
    @Test("playhead credits the sounding buffer before it completes")
    func partialThenNext() {
        var head = CaptionPlayhead()
        head.enqueue(frames: 24_000, now: 0)
        #expect(head.heardFrames(now: 0, sampleRate: 24_000) == 0)
        #expect(head.heardFrames(now: 0.5, sampleRate: 24_000) == 12_000)

        head.enqueue(frames: 24_000, now: 0.5)
        #expect(head.heardFrames(now: 0.5, sampleRate: 24_000) == 12_000)

        #expect(head.completeCurrent(now: 1) == 24_000)
        #expect(head.heardFrames(now: 1, sampleRate: 24_000) == 24_000)
        #expect(head.heardFrames(now: 1.25, sampleRate: 24_000) == 30_000)
    }
}
