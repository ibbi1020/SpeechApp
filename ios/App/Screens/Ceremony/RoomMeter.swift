import AVFoundation
import Foundation
import SpeechAppKit

/// What the ceremony reads off the room meter. `decibels` is nil until a second
/// of sound, after the open pop, has been averaged.
struct RoomMeterSnapshot: Equatable {
    var ready: Bool
    var decibels: Double?
    var warning: Bool
    var voice: Double
    var denied: Bool
}

/// Measures the room during exercise selection. Measurement mode, no voice
/// processing: automatic gain would hide a loud room, and the hum step already
/// keeps that processing off for the same reason.
///
/// The session stays active after the engine stops. A quick return from the
/// breath step starts this meter again, and a deactivate from the previous
/// stop would turn the microphone off under that new listener. The hum step
/// replaces the category when it opens.
@MainActor
final class RoomMeter {
    private let engine = AVAudioEngine()
    private let state = LockedRoom()
    private var listening = false
    private var tapInstalled = false
    /// A newer start invalidates an older stop, so leaving and coming straight
    /// back does not tear the new tap down.
    private var generation = 0

    var snapshot: RoomMeterSnapshot { state.snapshot() }

    /// Opens the microphone. The returned token is the only one `stop` will honor.
    func start() async -> Int {
        generation += 1
        let token = generation
        let granted = await Self.requestPermission()
        guard token == generation, Task.isCancelled == false else { return token }
        guard granted else {
            state.deny()
            return token
        }
        let sessionReady = await Self.activateSession()
        guard token == generation, Task.isCancelled == false, sessionReady else { return token }
        guard openEngine() else { return token }
        listening = true
        return token
    }

    /// Stops the tap when `token` is still the latest start. Does not deactivate
    /// the session. See the type comment.
    func stop(token: Int) {
        guard token == generation, listening else { return }
        state.close()
        removeTap()
        if engine.isRunning {
            engine.stop()
        }
        listening = false
    }

    private func openEngine() -> Bool {
        removeTap()
        if engine.isRunning {
            engine.stop()
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return false }
        let frames = AVAudioFrameCount(max(256, (format.sampleRate * 0.02).rounded()))
        state.begin(at: ProcessInfo.processInfo.systemUptime)
        Self.installTap(on: input, format: format, frames: frames, state: state)
        tapInstalled = true
        engine.prepare()
        do {
            try engine.start()
        } catch {
            removeTap()
            state.close()
            return false
        }
        return true
    }

    private func removeTap() {
        guard tapInstalled else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    private nonisolated static func installTap(
        on input: AVAudioInputNode,
        format: AVAudioFormat,
        frames: AVAudioFrameCount,
        state: LockedRoom
    ) {
        input.installTap(onBus: 0, bufferSize: frames, format: format) { buffer, _ in
            state.observe(buffer)
        }
    }

    private static func requestPermission() async -> Bool {
        let current = AVAudioApplication.shared.recordPermission
        switch current {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    /// Category and activation run off the main actor. On iOS 27 the
    /// completion-based activate returns immediately.
    @concurrent
    private static func activateSession() async -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try? session.setPreferredIOBufferDuration(0.02)
#if compiler(>=6.4) // iOS 27 SDK (Xcode 27+); Xcode 26 (Swift 6.3) builds take the fallback
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
#else
            try session.setActive(true)
#endif
            return true
        } catch {
            return false
        }
    }
}

/// Microphone buffers arrive on the audio thread. The reading stays behind the lock.
private final class LockedRoom: @unchecked Sendable {
    private let lock = NSLock()
    private var reading = RoomReading()
    private var latestRMS = 0.0
    private var openedAt = 0.0
    private var accepting = false
    private var denied = false

    func begin(at uptime: TimeInterval) {
        lock.lock()
        reading = RoomReading()
        latestRMS = 0
        openedAt = uptime
        accepting = true
        denied = false
        lock.unlock()
    }

    func deny() {
        lock.lock()
        denied = true
        accepting = false
        lock.unlock()
    }

    func close() {
        lock.lock()
        accepting = false
        reading = RoomReading()
        latestRMS = 0
        lock.unlock()
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
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        defer { lock.unlock() }
        guard accepting else { return }
        reading.observe(rms: rms, at: now - openedAt)
        latestRMS = rms
    }

    func snapshot() -> RoomMeterSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return RoomMeterSnapshot(
            ready: reading.ready,
            decibels: reading.decibels,
            warning: reading.warning,
            voice: DitherHorizon.voiceLevel(rms: latestRMS),
            denied: denied
        )
    }
}
