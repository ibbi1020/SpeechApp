import Testing
@testable import SpeechAppKit

@Suite("Listen drive")
struct ListenDriveTests {
    @Test("room noise stays near the idle floor")
    func silenceStaysQuiet() {
        #expect(ListenDrive.normalized(rms: 0.001) < 0.08)
    }

    @Test("quiet speech still moves the orb")
    func quietSpeechIsAudible() {
        #expect(ListenDrive.normalized(rms: 0.01) > 0.25)
    }

    @Test("conversational speech fills most of the listening range")
    func speechMatchesLabBand() {
        let level = ListenDrive.normalized(rms: 0.02)
        #expect(level > 0.55)
        #expect(level < 1)
    }

    @Test("loud speech uses the full listening range")
    func loudSpeechStaysInListenBand() {
        #expect(ListenDrive.normalized(rms: 0.05) == ListenDrive.ceiling)
        #expect(ListenDrive.normalized(rms: 1) == ListenDrive.ceiling)
        #expect(ListenDrive.ceiling == 1)
    }
}
