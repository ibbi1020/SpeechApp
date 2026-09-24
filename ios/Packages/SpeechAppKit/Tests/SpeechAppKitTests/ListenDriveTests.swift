import Testing
@testable import SpeechAppKit

@Suite("Listen drive")
struct ListenDriveTests {
    @Test("room noise stays near the idle floor")
    func silenceStaysQuiet() {
        #expect(ListenDrive.normalized(rms: 0.001) < 0.08)
    }

    @Test("conversational speech sits in the lab's reacting band")
    func speechMatchesLabBand() {
        let level = ListenDrive.normalized(rms: 0.02)
        #expect(level > 0.35)
        #expect(level < 0.7)
    }

    @Test("loud speech stays in the user-speaking band")
    func loudSpeechStaysInListenBand() {
        #expect(ListenDrive.normalized(rms: 0.05) == ListenDrive.ceiling)
        #expect(ListenDrive.normalized(rms: 1) == ListenDrive.ceiling)
        #expect(ListenDrive.ceiling < 0.6)
    }
}
