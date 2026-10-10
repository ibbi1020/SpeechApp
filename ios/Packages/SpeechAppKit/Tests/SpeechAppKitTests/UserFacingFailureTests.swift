import Testing
@testable import SpeechAppKit

@Suite("User-facing failures")
struct UserFacingFailureTests {
    @Test("a socket failure does not show the socket or an error code")
    func socketStaysOffScreen() {
        let error = GrokTranscriptionError.failed("Socket is not connected")
        let shown = UserFacingFailure.message(for: error)
        #expect(shown == UserFacingFailure.practiceDidNotStart)
        #expect(!shown.contains("Socket"))
        #expect(!shown.contains("error"))
    }

    @Test("MouthError does not show the type name")
    func mouthStaysOffScreen() {
        let shown = UserFacingFailure.message(for: MouthError.connectFailed)
        #expect(shown == UserFacingFailure.practiceDidNotStart)
        #expect(!shown.contains("MouthError"))
    }

    @Test("a missing recording is not an internal save error")
    func missingRecording() {
        let shown = UserFacingFailure.message(for: RecordingStoreError.ioFailed("posix 28"))
        #expect(shown == UserFacingFailure.recordingsDidNotLoad)
        #expect(!shown.contains("posix"))
    }

    @Test("a full disk tells them to free space")
    func diskFull() {
        #expect(UserFacingFailure.message(for: RecordingStoreError.diskFull) == UserFacingFailure.diskFull)
        #expect(UserFacingFailure.diskFull.contains("Free up space"))
    }
}
