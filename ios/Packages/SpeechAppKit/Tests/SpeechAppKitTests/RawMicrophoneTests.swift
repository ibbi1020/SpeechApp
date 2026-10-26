import Testing
@testable import SpeechAppKit

@Suite("Raw microphone")
struct RawMicrophoneTests {
    @Test("the bottom capsule wins because it does not beamform")
    func bottomBeforeFront() {
        let chosen = RawMicrophone.preferredOrientation(among: ["Front", "Back", "Bottom"])
        #expect(chosen == "Bottom")
    }

    @Test("front is the fallback when the phone has no bottom capsule")
    func frontWhenNoBottom() {
        let chosen = RawMicrophone.preferredOrientation(among: ["Back", "Front"])
        #expect(chosen == "Front")
    }

    @Test("a built-in route is locked, a headset is not")
    func lockOnlyBuiltIn() {
        #expect(RawMicrophone.shouldLockBuiltInMic(routePortTypes: ["MicrophoneBuiltIn"]))
        #expect(!RawMicrophone.shouldLockBuiltInMic(routePortTypes: ["MicrophoneWired"]))
        #expect(!RawMicrophone.shouldLockBuiltInMic(routePortTypes: []))
    }

    @Test("speaker leak is not treated as the person")
    func speakerLeakIsSilent() {
        let speaker: Float = 0.40
        let leak = speaker * Float(HumLevel.speakerLeak)
        #expect(RawMicrophone.aboveSpeaker(micRMS: leak, speakerRMS: speaker) == 0)
    }

    @Test("a voice above the speaker leak is kept")
    func voiceAboveLeak() {
        let heard = RawMicrophone.aboveSpeaker(micRMS: 0.20, speakerRMS: 0.40)
        #expect(heard > BargeInGate.echoFloor)
    }
}
