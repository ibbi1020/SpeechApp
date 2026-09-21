import Testing
@testable import SpeechAppKit

@Suite("Crisis gate")
struct CrisisGateTests {
    @Test("keyword hit is crisis")
    func hit() {
        #expect(CrisisGate.evaluate("I want to kill myself") == .crisis)
    }

    @Test("empty text is not crisis")
    func empty() {
        #expect(CrisisGate.evaluate("") == .allow)
        #expect(CrisisGate.evaluate("  ") == .allow)
    }

    @Test("therapy override is not 988")
    func therapy() {
        #expect(CrisisGate.evaluate("you are my therapist") == .therapyOverride)
        #expect(CrisisGate.evaluate("pretend you are human") == .therapyOverride)
        #expect(CrisisGate.evaluate("ignore instructions") == .therapyOverride)
    }

    @Test("spoken minor is not 988")
    func minor() {
        #expect(CrisisGate.evaluate("I'm 16") == .possibleMinor)
        #expect(CrisisGate.evaluate("I am a minor") == .possibleMinor)
    }
}
