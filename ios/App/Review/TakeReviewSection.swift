import SwiftUI
import SpeechAppKit

struct TakeReviewSection: View {
    let manifest: RecordingManifest
    let saveError: String?

    @State private var selectedTakeIndex: Int = 0
    @State private var player = TakePlayer()
    @State private var activeMarker: ReviewMarker?
    @State private var isPreparing = false

    private var takes: [RecordingManifest.Take] { manifest.takes }

    private var selectedTake: RecordingManifest.Take? {
        guard !takes.isEmpty else { return nil }
        let index = min(max(0, selectedTakeIndex), takes.count - 1)
        return takes[index]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("Listen back")

            if let saveError, takes.isEmpty {
                Text(saveError)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBackground)
            } else if takes.isEmpty {
                Text("Preparing audio…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBackground)
            } else {
                playerCard
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

    private var playerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
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

                WaveformScrubber(
                    audioURL: url,
                    duration: player.duration > 0 ? player.duration : take.durationSeconds,
                    currentTime: player.currentTime,
                    markers: take.markers,
                    onSeek: { player.seek(to: $0) },
                    onMarkerTap: { marker in
                        activeMarker = marker
                        player.seek(to: max(0, marker.start - 2), andPlay: true)
                    }
                )

                HStack(spacing: 16) {
                    Button {
                        player.toggle()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                    Text(timeLabel(player.currentTime))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("/")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                    Text(timeLabel(player.duration > 0 ? player.duration : take.durationSeconds))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
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

                SyncedTranscriptView(
                    words: take.words,
                    currentTime: player.currentTime,
                    onWordTap: { word in
                        player.seek(to: word.start, andPlay: true)
                    }
                )
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
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

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .speechType(.label)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(.secondarySystemBackground))
    }
}
