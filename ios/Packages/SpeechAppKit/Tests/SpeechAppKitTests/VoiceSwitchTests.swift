import Testing
@testable import SpeechAppKit

@Suite("Voice switch")
struct VoiceSwitchTests {
    @Test("an idle pick is sent immediately")
    func idleSendsNow() {
        var voice = VoiceSwitch(applied: "sirius")
        #expect(voice.select("ara") == "ara")
        #expect(voice.applied == "ara")
        #expect(voice.select("ara") == nil)
    }

    @Test("a pick while the agent is speaking waits until that reply has played out")
    func holdsThroughTheSentence() {
        var voice = VoiceSwitch(applied: "sirius")
        voice.noteResponseStarted()
        voice.notePlaybackStarted()
        #expect(voice.select("eve") == nil)
        #expect(voice.applied == "sirius")

        voice.noteResponseFinished()
        #expect(voice.flushIfIdle() == nil)
        #expect(voice.applied == "sirius")

        voice.notePlaybackFinished()
        #expect(voice.flushIfIdle() == "eve")
        #expect(voice.applied == "eve")
        #expect(voice.flushIfIdle() == nil)
    }

    @Test("playback ending early does not change the voice while the reply is still being made")
    func stillGeneratingKeepsTheVoice() {
        var voice = VoiceSwitch(applied: "sirius")
        voice.noteResponseStarted()
        voice.notePlaybackStarted()
        #expect(voice.select("leo") == nil)
        voice.notePlaybackFinished()
        #expect(voice.flushIfIdle() == nil)
        voice.noteResponseFinished()
        #expect(voice.flushIfIdle() == "leo")
    }

    @Test("only the last pick during a sentence is sent")
    func lastPickWins() {
        var voice = VoiceSwitch(applied: "sirius")
        voice.noteResponseStarted()
        #expect(voice.select("ara") == nil)
        #expect(voice.select("rex") == nil)
        voice.noteInterrupted()
        #expect(voice.flushIfIdle() == "rex")
    }

    @Test("picking the current voice again does not send")
    func sameVoiceIsQuiet() {
        var voice = VoiceSwitch(applied: "sirius")
        voice.noteResponseStarted()
        voice.notePlaybackStarted()
        #expect(voice.select("sirius") == nil)
        voice.noteResponseFinished()
        voice.notePlaybackFinished()
        #expect(voice.flushIfIdle() == nil)
        #expect(voice.applied == "sirius")
    }
}
