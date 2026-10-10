import AVFoundation
import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class TakePlayer {
    private nonisolated static let log = Logger(subsystem: "com.speechapp", category: "TakePlayer")

    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isPlaying = false
    private(set) var isSeeking = false

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var playbackReady = false

    func load(url: URL) {
        tearDown()

        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? -1
        Self.log.info("load \(url.lastPathComponent) bytes=\(size)")

        let asset = AVURLAsset(
            url: url,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        )
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.volume = 1
        self.player = player
        duration = 0
        Task { await self.refreshDuration(from: asset) }
        statusObservation = item.observe(\.status, options: [.new]) { item, _ in
            if item.status == .failed {
                Self.log.error("player item failed: \(item.error?.localizedDescription ?? "unknown")")
            }
        }

        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, !self.isSeeking else { return }
                let seconds = CMTimeGetSeconds(time)
                if seconds.isFinite {
                    self.currentTime = seconds
                }
                self.isPlaying = (self.player?.rate ?? 0) > 0
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.currentTime = self?.duration ?? 0
            }
        }
    }

    func play() {
        Task { await startPlayback() }
    }

    private func startPlayback() async {
        await preparePlaybackSession()
        guard let player else { return }

        // At end-of-file, play() is a no-op until we seek back.
        let t = CMTimeGetSeconds(player.currentTime())
        if duration > 0, t.isFinite, t >= duration - 0.05 {
            seek(to: 0, andPlay: true)
            return
        }

        player.volume = 1
        player.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func toggle() {
        if isPlaying { pause() } else { play() }
    }

    func seek(to time: TimeInterval, andPlay: Bool = false) {
        guard let player else { return }
        isSeeking = true
        let upper = duration > 0 ? duration : time
        let cm = CMTime(seconds: max(0, min(time, upper)), preferredTimescale: 600)
        player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                guard let self else { return }
                if finished {
                    self.currentTime = CMTimeGetSeconds(cm)
                }
                self.isSeeking = false
                if andPlay { self.play() }
            }
        }
    }

    /// Monologue leaves the shared session on `.record` (no speaker) and ducked.
    /// Switch to playback off the main thread so activation does not hang the UI.
    private func preparePlaybackSession() async {
        guard !playbackReady else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                Self.switchToPlayback()
                continuation.resume()
            }
        }
        playbackReady = true
    }

    private nonisolated static func switchToPlayback() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            log.error("deactivate before playback failed: \(error.localizedDescription)")
        }
        do {
            // No mixWithOthers: the record session ducked other audio, and mixing keeps that duck.
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
        } catch {
            log.error("playback session failed: \(error.localizedDescription)")
        }
        let outputs = session.currentRoute.outputs.map { "\($0.portType.rawValue)" }.joined(separator: ",")
        log.info(
            "playback session category=\(session.category.rawValue) outputs=\(outputs) volume=\(session.outputVolume)"
        )
    }

    private func refreshDuration(from asset: AVURLAsset) async {
        do {
            let loaded = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(loaded)
            if seconds.isFinite, seconds > 0 {
                duration = seconds
            }
        } catch {
            // Keep whatever duration the manifest already shows in the UI.
        }
    }

    func tearDown() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        statusObservation = nil
        player?.pause()
        player = nil
        playbackReady = false
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    deinit {
        // Observers cleared on tearDown from views; player releases with self.
    }
}
