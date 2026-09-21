import Testing
@testable import SpeechAppKit

@Suite("Fake mouth")
struct FakeConversationMouthTests {
    @Test("records response.create instructions")
    @MainActor
    func recordsInstructions() async throws {
        let mouth = FakeConversationMouth()
        try await mouth.connect(ephemeralKey: "ek_test")
        try await mouth.sendResponseCreate(instructions: "OPEN: ask about coffee")
        #expect(mouth.responseCreates == ["OPEN: ask about coffee"])
        mouth.emit(.audioDelta)
        mouth.emit(.responseDone(transcript: "Coffee?"))
        #expect(mouth.didClose == false)
        await mouth.close()
        #expect(mouth.didClose == true)
    }
}
