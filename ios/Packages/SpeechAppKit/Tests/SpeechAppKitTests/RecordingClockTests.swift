import Testing
@testable import SpeechAppKit

@Suite("Recording clock")
struct RecordingClockTests {
    @Test("stream time maps 1:1 while recording with no pauses")
    func identity() {
        var clock = RecordingClock()
        clock.beginTake(atStreamTime: 1.0)
        #expect(clock.fileTime(forStreamTime: 1.0) == 0)
        #expect(clock.fileTime(forStreamTime: 3.5) == 2.5)
        clock.appendAudio(duration: 2.5)
        #expect(clock.writtenSeconds == 2.5)
    }

    @Test("pause returns nil and resume cuts the gap from the file timeline")
    func pauseCutsGap() {
        var clock = RecordingClock()
        clock.beginTake(atStreamTime: 0)
        // Speak 0–2s stream
        #expect(clock.fileTime(forStreamTime: 2) == 2)
        clock.pause(atStreamTime: 2)
        #expect(clock.fileTime(forStreamTime: 3) == nil)
        // 3s of pause on the stream, then resume
        clock.resume(atStreamTime: 5)
        // Stream 5 → file 2 (pause 2…5 dropped)
        #expect(clock.fileTime(forStreamTime: 5) == 2)
        #expect(clock.fileTime(forStreamTime: 7) == 4)
    }

    @Test("recordedWord drops words that fall inside a pause")
    func dropsPausedWords() {
        var clock = RecordingClock()
        clock.beginTake(atStreamTime: 0)
        clock.pause(atStreamTime: 1)
        #expect(clock.recordedWord(surface: "um", streamStart: 1.2, streamEnd: 1.4) == nil)
        clock.resume(atStreamTime: 3)
        let word = clock.recordedWord(surface: "went", streamStart: 3.1, streamEnd: 3.4)
        #expect(word?.start == 1.1)
        #expect(word?.end == 1.4)
        #expect(word?.surface == "went")
    }

    @Test("appendAudio ignores duration while paused")
    func noWriteWhilePaused() {
        var clock = RecordingClock()
        clock.beginTake(atStreamTime: 0)
        clock.appendAudio(duration: 1)
        clock.pause(atStreamTime: 1)
        clock.appendAudio(duration: 5)
        #expect(clock.writtenSeconds == 1)
    }
}
