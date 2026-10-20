import SwiftUI
import SpeechAppKit

struct TakeReviewSection: View {
    let manifest: RecordingManifest
    let saveError: String?

    @State private var selectedTakeIndex: Int = 0
    @State private var player = TakePlayer()
    @State private var activeMarker: ReviewMarker?

    private var takes: [RecordingManifest.Take] { manifest.takes }

    private var selectedTake: RecordingManifest.Take? {
        guard !takes.isEmpty else { return nil }
        let index = min(max(0, selectedTakeIndex), takes.count - 1)
        return takes[index]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SpeechSpacing.section) {
            if let saveError, takes.isEmpty {
                Text(saveError)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if takes.isEmpty {
                Text("Preparing audio…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                playerBody
            }
        }
        .onAppear {
            if selectedTakeIndex == 0, let first = takes.first {
                load(take: first)
            }
        }
        .onDisappear {
            player.tearDown()
        }
    }

    private var playerBody: some View {
        VStack(alignment: .leading, spacing: SpeechSpacing.section) {
            if takes.count > 1 {
                Picker("Take", selection: $selectedTakeIndex) {
                    ForEach(Array(takes.enumerated()), id: \.element.index) { index, take in
                        Text("Take \(take.index)").tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedTakeIndex) { _, _ in
                    if let take = selectedTake { load(take: take) }
                }
            }

            if let take = selectedTake {
                let url = RecordingsService.store.audioURL(
                    regimenID: manifest.id,
                    fileName: take.audioFileName
                )

                VStack(alignment: .leading, spacing: SpeechSpacing.related) {
                    WaveformScrubber(
                        audioURL: url,
                        duration: player.duration > 0 ? player.duration : take.durationSeconds,
                        currentTime: player.currentTime,
                        markers: take.markers,
                        partnerTurns: take.partnerTurns ?? [],
                        onSeek: { player.seek(to: $0) },
                        onMarkerTap: { marker in
                            activeMarker = marker
                            player.seek(to: max(0, marker.start - 2), andPlay: true)
                        }
                    )

                    HStack(spacing: SpeechSpacing.related) {
                        Button {
                            player.toggle()
                        } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.black)
                                .offset(x: player.isPlaying ? 0 : 1)
                                .frame(width: 44, height: 44)
                                .background(Color.white, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                        PlayheadTime(time: player.currentTime)
                        Spacer(minLength: SpeechSpacing.cluster)
                        Text(timeLabel(player.duration > 0 ? player.duration : take.durationSeconds))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    if let playbackError = player.playbackError {
                        Text(playbackError)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let activeMarker {
                        Text(activeMarker.note)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let turns = take.partnerTurns, !turns.isEmpty {
                    ConversationTranscriptView(
                        words: take.words,
                        partnerTurns: turns,
                        currentTime: player.currentTime,
                        onWordTap: { word in
                            player.seek(to: word.start, andPlay: true)
                        }
                    )
                } else {
                    SyncedTranscriptView(
                        words: take.words,
                        currentTime: player.currentTime,
                        onWordTap: { word in
                            player.seek(to: word.start, andPlay: true)
                        }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load(take: RecordingManifest.Take) {
        activeMarker = nil
        let url = RecordingsService.store.audioURL(
            regimenID: manifest.id,
            fileName: take.audioFileName
        )
        player.load(url: url)
    }

    private func timeLabel(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

}

/// Elapsed playback time. The player reports a new time many times a second.
/// Only the displayed second may rebuild the digits, or the roll is cancelled.
private struct PlayheadTime: View {
    var time: TimeInterval

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PlayheadDigits(label: Self.label(time), reduceMotion: reduceMotion)
            .equatable()
    }

    private static func label(_ time: TimeInterval) -> String {
        let s = max(0, Int(time.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct PlayheadDigits: View, Equatable {
    var label: String
    var reduceMotion: Bool

    var body: some View {
        Text(label)
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
            .digitRoll(label, countsDown: false, reduceMotion: reduceMotion)
    }
}
