import Testing
@testable import SpeechAppKit

@Suite("Monologue fluency profile")
struct MonologueFluencyTests {
    @Test("speech rate uses the take clock and articulation rate uses phonation")
    func rates() {
        let take = MonologueTake(
            index: 1,
            wallSeconds: 60,
            ranges: [ConversationSpeechInterval(start: 0, end: 30)],
            transcript: "cat sat",
            words: [
                RecordedWord(surface: "cat", start: 0, end: 0.3),
                RecordedWord(surface: "sat", start: 0.4, end: 0.7),
            ]
        )
        let profile = MonologueFluency.measure(take)
        // Two syllables across a full minute, and across 30 s of phonation.
        #expect(profile.speechRate == 2)
        #expect(profile.articulationRate == 4)
        #expect(profile.pauseCount == 0)
        #expect(profile.meanLengthOfRun == 2)
    }

    @Test("a real quarter-second silence counts, and a short word gap does not")
    func pauseThreshold() {
        // 0.45 s between Grok edges is 0.25 s of real silence.
        let paused = MonologueTake(
            index: 1,
            wallSeconds: 60,
            ranges: [],
            transcript: "cat sat",
            words: [
                RecordedWord(surface: "cat", start: 0, end: 0.3),
                RecordedWord(surface: "sat", start: 0.75, end: 1.0),
            ]
        )
        let breath = MonologueTake(
            index: 1,
            wallSeconds: 60,
            ranges: [],
            transcript: "cat sat",
            words: [
                RecordedWord(surface: "cat", start: 0, end: 0.3),
                RecordedWord(surface: "sat", start: 0.6, end: 0.9),
            ]
        )
        let held = MonologueFluency.measure(paused)
        #expect(held.pauseCount == 1)
        #expect(held.meanPause == 0.25)
        #expect(held.pauseFrequency == 1)
        #expect(held.meanLengthOfRun == 1)
        #expect(MonologueFluency.measure(breath).pauseCount == 0)
    }

    @Test("trimmed speech rate drops fillers and the abandoned restart")
    func trimmed() {
        let take = MonologueTake(
            index: 1,
            wallSeconds: 60,
            ranges: [ConversationSpeechInterval(start: 0, end: 30)],
            transcript: "I um I went",
            words: [
                RecordedWord(surface: "I", start: 0, end: 0.2),
                RecordedWord(surface: "um", start: 0.3, end: 0.5),
                RecordedWord(surface: "I", start: 0.6, end: 0.8),
                RecordedWord(surface: "went", start: 0.9, end: 1.2),
            ]
        )
        let profile = MonologueFluency.measure(take)
        // I, um, I, went → 4 raw. Content drops um → 3. Trimmed also drops the first I → 2.
        #expect(profile.speechRate == 4)
        #expect(profile.articulationRate == 6)
        #expect(profile.trimmedSpeechRate == 2)
        #expect(profile.filledPauseFrequency == 2)
    }

    @Test("comparison follows speech rate and pauses per minute")
    func comparison() {
        let first = MonologueTake(
            index: 1,
            wallSeconds: 60,
            ranges: [ConversationSpeechInterval(start: 0, end: 50)],
            transcript: "one two three four"
        )
        let last = MonologueTake(
            index: 3,
            wallSeconds: 60,
            ranges: [
                ConversationSpeechInterval(start: 0, end: 10),
                ConversationSpeechInterval(start: 12, end: 40),
            ],
            transcript: "one two three four five six seven eight"
        )
        let sentence = MonologueReportBuilder.comparison(first: first, last: last)
        #expect(sentence == "Take 3 vs take 1: a faster speech rate, more pauses per minute.")
    }
}
