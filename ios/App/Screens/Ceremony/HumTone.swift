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
    /// Shared so a second call waits for the first open instead of activating twice.
    private var prepareTask: Task<Bool, Never>?

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
    /// the same engine. Voice processing stays off: it learns a held hum and,
    /// a few seconds in, takes the hum out of the meter with the speaker.
    func listen() async {
        _ = await prepare()
    }

    /// Turns the session on without blocking the main thread.
    /// `setActive` from the main thread is the call the runtime warns about.
    private func prepare() async -> Bool {
        if isListening { return true }
        if let prepareTask {
            return await prepareTask.value
        }
        let task = Task { @MainActor () -> Bool in
            await self.openMicrophone()
        }
        prepareTask = task
        let ready = await task.value
        if ready == false {
            prepareTask = nil
        }
        return ready
    }

    private func openMicrophone() async -> Bool {
        let sessionReady = await Self.activateSession()
        guard sessionReady, Task.isCancelled == false else { return false }

        let sampleRate = 44_100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return false }
        wire(format)

        let input = engine.inputNode
        let hardware = input.outputFormat(forBus: 0)
        guard hardware.sampleRate > 0, hardware.channelCount > 0 else { return false }
        // The tap has to use the hardware format. Asking for a converted format
        // throws inside installTap, and that throw is not a Swift error, so the
        // engine never starts and the field stays still. Integer buffers are
        // still read if the callback arrives as int16.
        guard startMeter(on: input, format: hardware) else {
            input.removeTap(onBus: 0)
            return false
        }
        isListening = true
        return true
    }

    /// Installs the tap and starts the engine. On failure the tap stays, so a
    /// retry can replace it.
    private func startMeter(on input: AVAudioInputNode, format: AVAudioFormat) -> Bool {
        input.removeTap(onBus: 0)
        // The tap runs on the audio thread. A closure written here would be
        // isolated to the main actor and trap the first time a buffer arrives.
        Self.installMeterTap(on: input, format: format, meter: meter)
        if engine.isRunning { return true }
        engine.prepare()
        do {
            try engine.start()
            return true
        } catch {
            return false
        }
    }

    /// Category change and activation run off the main actor. On iOS 27 the
    /// completion-based activate returns immediately. Earlier systems still use
    /// `setActive`, but not on the main thread.
    @concurrent
    private static func activateSession() async -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            // Voice processing takes the speaker out of the mic. A held hum matches
            // that speaker, so once the canceller settles it takes the hum out too
            // and the field sinks back to rest. Measurement mode skips that.
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.defaultToSpeaker, .allowBluetoothHFP]
            )
            if #available(iOS 27, *) {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    session.activate(options: []) { activated, error in
                        if let error, activated == false {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
            } else {
                try session.setActive(true)
            }
            // The receiver is too quiet to hear in a room. This forces the
            // loudspeaker after the session is on.
            try session.overrideOutputAudioPort(.speaker)
            return true
        } catch {
            return false
        }
    }

    func play(_ clip: VocalClip) async {
        guard await prepare() else { return }

        let sampleRate = 44_100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let tone = Self.buffer(clip, format: format, sampleRate: sampleRate) else { return }

        wire(format)
        meter.setPlaybackRMS(tone.rms)
        defer { meter.setPlaybackRMS(0) }
        player.volume = 1
        if engine.isRunning == false {
            do {
                try engine.start()
            } catch {
                return
            }
        }

        player.stop()
        // The async schedule queues the buffer, then waits until it has been
        // played. Yield so the queue happens before play, without waiting here
        // for the whole tone.
        let playback = Task { @MainActor in
            await self.player.scheduleBuffer(tone.buffer, at: nil, options: .interrupts)
        }
        await Task.yield()
        if #available(iOS 27, *) {
            try? player.playAudio()
        } else {
            player.play()
        }
        // The schedule call can return before the tone has finished playing.
        // Hold the leak cut for the whole exercise either way.
        await withTaskCancellationHandler {
            try? await Task.sleep(for: .seconds(VocalClip.seconds))
            await playback.value
        } onCancel: {
            playback.cancel()
        }
    }

    func stop() {
        prepareTask?.cancel()
        prepareTask = nil
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
    /// as a voice. A third sits where a phone speaker can actually move air, because
    /// G3 on its own disappears. The peak uses the full sample range.
    private struct PlayableTone {
        var buffer: AVAudioPCMBuffer
        var rms: Double
    }

    private static func buffer(
        _ clip: VocalClip,
        format: AVAudioFormat,
        sampleRate: Double
    ) -> PlayableTone? {
        let seconds = VocalClip.seconds
        let frameCount = AVAudioFrameCount(sampleRate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount

        let fade = Int(sampleRate * 0.12)
        let total = Int(frameCount)
        let second = self.harmonic(clip)
        // Upper partial, same for every exercise. Added on top of the voice so
        // the level rises. The glide pitch does not change.
        let third = 0.5
        var phase = 0.0
        var sum = 0.0
        for index in 0..<total {
            let time = Double(index) / sampleRate
            let hz = frequency(at: time, seconds: seconds)
            phase += 2 * Double.pi * hz / sampleRate
            let shaped = (sin(phase) + second * sin(phase * 2)) / (1 + second)
            var sample = VocalPlayback.sample(
                shaped: shaped,
                partial: third * sin(phase * 3),
                flutter: flutter(clip, at: time)
            )
            if index < fade {
                sample *= Float(index) / Float(fade)
            }
            let remaining = total - index
            if remaining < fade {
                sample *= Float(remaining) / Float(fade)
            }
            samples[index] = sample
            sum += Double(sample) * Double(sample)
        }
        let rms = total > 0 ? (sum / Double(total)).squareRoot() : 0
        return PlayableTone(buffer: buffer, rms: rms)
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
    private var state = HumLevel()

    var level: Double {
        lock.lock()
        defer { lock.unlock() }
        return state.smoothed
    }

    func setPlaybackRMS(_ rms: Double) {
        lock.lock()
        state.playbackRMS = max(0, rms)
        lock.unlock()
    }

    func observe(_ buffer: AVAudioPCMBuffer) {
        let count = Int(buffer.frameLength)
        let rms: Double
        if let channel = buffer.floatChannelData?[0] {
            rms = SampleLoudness.rms(
                floatSamples: UnsafeBufferPointer(start: channel, count: count)
            )
        } else if let channel = buffer.int16ChannelData?[0] {
            rms = SampleLoudness.rms(
                int16Samples: UnsafeBufferPointer(start: channel, count: count)
            )
        } else {
            return
        }
        lock.lock()
        state.observe(micRMS: rms)
        lock.unlock()
    }

    func reset() {
        lock.lock()
        state.reset()
        lock.unlock()
    }
}
