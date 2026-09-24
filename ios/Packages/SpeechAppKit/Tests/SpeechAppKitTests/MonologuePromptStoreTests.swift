import Testing
@testable import SpeechAppKit

@Suite("Monologue last prompt")
struct MonologuePromptStoreTests {
    @Test("memory store round-trips")
    func memory() {
        let store = InMemoryMonologuePromptStore()
        #expect(store.lastPrompt == nil)
        store.lastPrompt = "How was your commute today?"
        #expect(store.lastPrompt == "How was your commute today?")
    }
}
