import Testing
@testable import SpeechAppKit

@Suite("Conversation route pause")
struct ConversationRoutePauseTests {
    @Test("unplug or Bluetooth drop pauses")
    func oldDeviceUnavailablePauses() {
        // AVAudioSession.RouteChangeReason.oldDeviceUnavailable
        #expect(ConversationRoutePause.shouldPause(reason: 2))
    }

    @Test("audio override pauses")
    func overridePauses() {
        // AVAudioSession.RouteChangeReason.override
        #expect(ConversationRoutePause.shouldPause(reason: 4))
    }

    @Test("category change does not pause")
    func categoryChangeDoesNotPause() {
        // AVAudioSession.RouteChangeReason.categoryChange
        #expect(!ConversationRoutePause.shouldPause(reason: 3))
    }

    @Test("volume is not a route-loss pause")
    func volumeIsNotPause() {
        // Volume 0 is not a route change. Unknown / new device stay talking.
        #expect(!ConversationRoutePause.shouldPause(reason: 0))
        #expect(!ConversationRoutePause.shouldPause(reason: 1))
    }
}
