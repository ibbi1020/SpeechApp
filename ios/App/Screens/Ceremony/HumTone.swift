import AVFoundation
import Foundation
import SpeechAppKit

/// A voice to copy, synthesised per exercise. The microphone is metered so the
/// field can follow the user. Nothing is recorded, and pitch is not checked.
///
/// The four exercises come from the two physiologically distinct families of
/// semi-occluded vocal tract exercise. The steady pair holds one sound source; the
/// fluctuating pair adds a second, vibrating one, which is modelled here as amplitude
/// modulation on the same glide.
@MainActor
final class HumTone {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let meter = VoiceMeter()
    private var isWired = false
    private var isListening = false

    /// Smoothed microphone level, 0...1. Silence stays near 0.
    var voice: Double { meter.level }

    /// One octave, G3 to G4. High enough for a phone speaker to actually carry.
    static let lowHz: Double = 196
    static let highHz: Double = 392

    private nonisolated static let lastClipKey = "ceremony.vocalClip.last"

    /// Walks to the next exercise each time the ceremony runs, so the same one does
    /// not come up twice in a row.
    nonisolated static func rotate() -> VocalClip {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: lastClipKey).flatMap(VocalClip.init(rawValue:))
        let clip = VocalClip.next(after: previous)
        defaults.set(clip.rawValue, forKey: lastClipKey)
        return clip
    }

    /// Opens the microphone. Safe to call more than once. The played note uses
    /// the same engine, with voice processing so the speaker does not count as the user.
    func listen() {
        guard isListening == false else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetooth]
        )
        try? session.setActive(true)

        let sampleRate = 44_100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        wire(format)

        let input = engine.inputNode
        try? input.setVoiceProcessingEnabled(true)
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else { return }
        input.removeTap(onBus: 0)
        // The tap runs on the audio thread. A closure written here would be
        // isolated to the main actor and trap the first time a buffer arrives.
        Self.installMeterTap(on: input, format: inputFormat, meter: meter)

        if engine.isRunning == false {
            engine.prepare()
            do {
                try engine.start()
            } catch {
                input.removeTap(onBus: 0)
                return
            }
        }
        isListening = true
    }

    func play(_ clip: VocalClip) {
        listen()

        let sampleRate = 44_100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = Self.buffer(clip, format: format, sampleRate: sampleRate) else { return }

        wire(format)
        player.volume = 1
        if engine.isRunning == false {
            do {
                try engine.start()
            } catch {
                return
            }
        }

        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    func stop() {
        player.stop()
        if isListening {
            engine.inputNode.removeTap(onBus: 0)
            isListening = false
        }
        if engine.isRunning {
            engine.stop()
        }
        meter.reset()
    }

    private nonisolated static func installMeterTap(
        on input: AVAudioInputNode,
        format: AVAudioFormat,
        meter: VoiceMeter
    ) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            meter.observe(buffer)
        }
    }

    private func wire(_ format: AVAudioFormat) {
        guard isWired == false else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        isWired = true
    }

    /// One up-and-down glide across the ten seconds. A second harmonic makes it read
    /// as a voice, not a beep. Peak is high on purpose: a quiet low sine disappears on
    /// a phone speaker.
    private static func buffer(
        _ clip: VocalClip,
        format: AVAudioFormat,
        sampleRate: Double
    ) -> AVAudioPCMBuffer? {
        let seconds = VocalClip.seconds
        let frameCount = AVAudioFrameCount(sampleRate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount

        let fade = Int(sampleRate * 0.12)
        let total = Int(frameCount)
        let harmonic = self.harmonic(clip)
        var phase = 0.0
        for index in 0..<total {
            let time = Double(index) / sampleRate
            let hz = frequency(at: time, seconds: seconds)
            phase += 2 * Double.pi * hz / sampleRate
            let voice = sin(phase) + harmonic * sin(phase * 2)
            var sample = Float(voice / (1 + harmonic) * 0.85 * flutter(clip, at: time))
            if index < fade {
                sample *= Float(index) / Float(fade)
            }
            let remaining = total - index
            if remaining < fade {
                sample *= Float(remaining) / Float(fade)
            }
            samples[index] = sample
        }
        return buffer
    }

    /// Nasal sounds damp the upper harmonic; trills keep more of it so the buzz is
    /// audible through a phone speaker.
    private static func harmonic(_ clip: VocalClip) -> Double {
        switch clip {
        case .hum: 0.30
        case .nasal: 0.22
        case .lipTrill: 0.55
        case .tongueTrill: 0.62
        }
    }

    /// The dual-source family's second source, as amplitude modulation. Lips flap
    /// slower than a tongue tip does.
    private static func flutter(_ clip: VocalClip, at time: Double) -> Double {
        let rate: Double
        switch clip {
        case .hum, .nasal: return 1
        case .lipTrill: rate = 26
        case .tongueTrill: rate = 32
        }
        return 0.72 + 0.28 * (0.5 + 0.5 * cos(2 * Double.pi * rate * time))
    }

    /// Up for the first half, down for the second.
    private static func frequency(at time: Double, seconds: Double) -> Double {
        let leg = seconds / 2
        let rising = time < leg
        let unit = rising ? time / leg : (time - leg) / leg
        let eased = 0.5 - 0.5 * cos(unit * Double.pi)
        if rising {
            return lowHz + (highHz - lowHz) * eased
        }
        return highHz + (lowHz - highHz) * eased
    }
}

/// Microphone loudness, smoothed off the audio thread. Nothing is kept.
private final class VoiceMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var smoothed = 0.0

    var level: Double {
        lock.lock()
        defer { lock.unlock() }
        return smoothed
    }

    func observe(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        var sum = 0.0
        for index in 0 ..< count {
            let sample = Double(channel[index])
            sum += sample * sample
        }
        let rms = (sum / Double(count)).squareRoot()
        let raw = DitherHorizon.voiceLevel(rms: rms)
        lock.lock()
        let follow = raw > smoothed ? 0.55 : 0.16
        smoothed += (raw - smoothed) * follow
        lock.unlock()
    }

    func reset() {
        lock.lock()
        smoothed = 0
        lock.unlock()
    }
}
