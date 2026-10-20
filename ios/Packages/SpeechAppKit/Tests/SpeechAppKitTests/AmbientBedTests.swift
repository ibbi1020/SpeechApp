import AVFoundation
import Testing
@testable import SpeechAppKit

@Suite("Ambient bed")
struct AmbientBedTests {
    @Test("off stays stopped while the partner is live")
    func offStaysStopped() {
        #expect(AmbientBedPolicy.command(place: .off, phase: .talking) == .stop)
        #expect(AmbientBedPolicy.command(place: .off, phase: .wrapping) == .stop)
    }

    @Test("a chosen place plays through the talk and the goodbye")
    func beachPlaysWhileLive() {
        #expect(AmbientBedPolicy.command(place: .beach, phase: .talking) == .play(.beach))
        #expect(AmbientBedPolicy.command(place: .beach, phase: .wrapping) == .play(.beach))
        #expect(AmbientBedPolicy.command(place: .beach, phase: .paused) == .stop)
        #expect(AmbientBedPolicy.command(place: .beach, phase: .report) == .stop)
        #expect(AmbientBedPolicy.command(place: .beach, phase: .crisis) == .stop)
    }

    @Test("gain stays a fixed step under the partner")
    func gain() {
        #expect(AmbientBedPolicy.gain(place: .off) == 0)
        #expect(AmbientBedPolicy.gain(place: .rain) == 0.08)
    }

    @Test("partner cancel leaves the bed up")
    func partnerCancelKeepsTheBed() {
        #expect(AmbientBedPolicy.keepsPlaying(after: .partnerCancel) == true)
        #expect(AmbientBedPolicy.keepsPlaying(after: .teardown) == false)
        #expect(AmbientBedPolicy.keepsPlaying(after: .pause) == false)
        #expect(AmbientBedPolicy.keepsPlaying(after: .userOff) == false)
    }

    @Test("the choice survives a new reader of the same store")
    func preferenceRoundTrip() {
        let name = "AmbientPreferenceTests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        let first = AmbientPreference(defaults: suite)
        #expect(first.place == .off)
        first.place = .beach
        let second = AmbientPreference(defaults: suite)
        #expect(second.place == .beach)
        suite.removePersistentDomain(forName: name)
    }

    @Test("only a 24 kHz mono float buffer is a bed")
    func loopFormat() {
        let wideFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        )!
        let wide = AVAudioPCMBuffer(pcmFormat: wideFormat, frameCapacity: 8)!
        wide.frameLength = 8
        #expect(AmbientLoopFormat.matches(wide) == false)

        let bedFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24_000,
            channels: 1,
            interleaved: false
        )!
        let bed = AVAudioPCMBuffer(pcmFormat: bedFormat, frameCapacity: 8)!
        bed.frameLength = 8
        #expect(AmbientLoopFormat.matches(bed) == true)
    }
}
