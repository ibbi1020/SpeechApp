import Foundation
import Testing
@testable import SpeechAppKit

@Suite("BargeInGate")
struct BargeInGateTests {
    @Test("speech passes through when the partner is not speaking")
    func passThroughWhenIdle() {
        var gate = BargeInGate()
        #expect(gate.onSpeechStarted() == .passThrough)
        #expect(gate.onSpeechStopped() == .passThrough)
    }

    @Test("short speech while the partner speaks is held then swallowed")
    func swallowEchoBlip() {
        var gate = BargeInGate()
        gate.noteAgentAudio()
        #expect(gate.onSpeechStarted() == .hold)
        #expect(gate.tick(now: 0, level: 0.2) == .hold)
        #expect(gate.tick(now: 0.1, level: 0.2) == .hold)
        #expect(gate.onSpeechStopped() == .swallow)
    }

    @Test("sustained loud speech while the partner speaks commits a cancel")
    func commitSustainedBargeIn() {
        var gate = BargeInGate()
        gate.noteAgentAudio()
        #expect(gate.onSpeechStarted() == .hold)
        #expect(gate.tick(now: 0, level: 0.2) == .hold)
        #expect(gate.tick(now: 0.15, level: 0.2) == .hold)
        #expect(gate.tick(now: 0.31, level: 0.2) == .commitCancel)
        #expect(gate.agentSpeaking == false)
        #expect(gate.onSpeechStopped() == .passThrough)
    }

    @Test("quiet mic while holding never commits")
    func quietNeverCommits() {
        var gate = BargeInGate()
        gate.noteAgentAudio()
        #expect(gate.onSpeechStarted() == .hold)
        #expect(gate.tick(now: 0, level: 0.01) == .hold)
        #expect(gate.tick(now: 0.5, level: 0.01) == .hold)
        #expect(gate.onSpeechStopped() == .swallow)
    }

    @Test("partner finishing releases held speech without cancel")
    func responseDoneReleasesHold() {
        var gate = BargeInGate()
        gate.noteAgentAudio()
        #expect(gate.onSpeechStarted() == .hold)
        #expect(gate.noteResponseDone() == .passThrough)
        #expect(gate.agentSpeaking == false)
        #expect(gate.onSpeechStopped() == .passThrough)
    }
}
