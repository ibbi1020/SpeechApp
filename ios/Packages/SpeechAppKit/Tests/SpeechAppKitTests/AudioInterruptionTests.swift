import Testing
@testable import SpeechAppKit

@Suite("Audio interruption")
struct AudioInterruptionTests {
    @Test("a call or other began interruption pauses")
    func beganPauses() {
        // AVAudioSession.InterruptionType.began
        #expect(AudioInterruption.shouldPause(type: 1))
    }

    @Test("the interruption ending does not resume")
    func endedDoesNotPause() {
        // AVAudioSession.InterruptionType.ended
        #expect(!AudioInterruption.shouldPause(type: 0))
    }
}
