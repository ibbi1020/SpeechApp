import AVFoundation
import Foundation
import Observation
import OSLog

/// Plays a saved take through the loudspeaker.
///
/// `AVPlayer` keeps moving its clock even when the session is still `.record`
/// (no speaker), so the button looked like play and nothing came out.
/// `AVAudioPlayer` returns false in that case, and this session is set to
/// play-and-record with the speaker forced on — the route that works right
/// after the microphone has been used.
@MainActor
@Observable
final class TakePlayer: NSObject, AVAudioPlayerDelegate {
    private nonisolated static let log = Logger(subsystem: "com.speechapp", category: "TakePlayer")

    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isPlaying = false
    private(set) var playbackError: String?

    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?

    func load(url: URL) {
        tearDown()
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? -1
        Self.log.info("load \(url.lastPathComponent, privacy: .public) bytes=\(size)")
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.volume = 1
            player.prepareToPlay()
            self.player = player
            duration = player.duration
            if duration.isNaN || duration < 0 { duration = 0 }
        } catch {
            playbackError = "Couldn't open this recording."
            Self.log.error("open failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func play() {
        guard let player else { return }
        if duration > 0, player.currentTime >= duration - 0.05 {
            player.currentTime = 0
        }
        do {
            try Self.routeToSpeaker()
        } catch {
            playbackError = "Couldn't switch on the speaker."
            Self.log.error("session failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        player.volume = 1
        guard player.play() else {
            playbackError = "Playback didn't start."
            Self.log.error("AVAudioPlayer.play() returned false")
            isPlaying = false
            return
        }
        playbackError = nil
        isPlaying = true
        currentTime = player.currentTime
        startTicker()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        ticker?.cancel()
        ticker = nil
        if let player { currentTime = player.currentTime }
    }

    func toggle() {
        if isPlaying { pause() } else { play() }
    }

    func seek(to time: TimeInterval, andPlay: Bool = false) {
        guard let player else { return }
        let upper = duration > 0 ? duration : time
        player.currentTime = max(0, min(time, upper))
        currentTime = player.currentTime
        if andPlay { play() }
    }

    func tearDown() {
        ticker?.cancel()
        ticker = nil
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        playbackError = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = self.duration
            self.ticker?.cancel()
            self.ticker = nil
        }
    }

    /// Record mode has no speaker. Play-and-record plus the speaker override
    /// is what actually comes out of the phone after a take.
    private nonisolated static func routeToSpeaker() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.overrideOutputAudioPort(.speaker)
        try session.setActive(true)
        let outputs = session.currentRoute.outputs.map(\.portType.rawValue).joined(separator: ",")
        log.info(
            "playback category=\(session.category.rawValue, privacy: .public) outputs=\(outputs, privacy: .public) volume=\(session.outputVolume)"
        )
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { @MainActor in
            while !Task.isCancelled, let player, player.isPlaying {
                currentTime = player.currentTime
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }
}
