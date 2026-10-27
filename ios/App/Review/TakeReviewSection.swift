import SwiftUI
import SpeechAppKit

struct TakeReviewSection: View {
    let manifest: RecordingManifest
    let saveError: String?
    /// A thin or crisis conversation already explains itself. The line would
    /// call that take perfect. Gallery has no report kind, so it leaves this on.
    var showsPerfectLine: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedTakeIndex: Int = 0
    @State private var player = TakePlayer()
    @State private var shownNote: ReviewMarker?
    @State private var notesInside: Set<ReviewMarker.ID> = []
    @State private var preferredNote: ReviewMarker.ID?

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
                .frame(maxWidth: .infinity)
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
                        scrubGeneration: player.scrubGeneration,
                        onSeek: { player.seek(to: $0) },
                        onMarkerTap: { marker in
                            preferredNote = marker.id
                            player.seek(to: max(0, marker.start - VisibleFeedback.vicinity), andPlay: true)
                            followPlayhead(player.currentTime, markers: take.markers)
                        },
                        onScrubBegan: { player.beginScrub() },
                        onScrub: { time, generation in player.scrub(to: time, generation: generation) },
                        onScrubEnded: { generation in player.endScrub(generation: generation) }
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
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    if let playbackError = player.playbackError {
                        Text(playbackError)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if shownNote != nil || (showsPerfectLine && PerfectTake.isClean(take)) {
                        ZStack(alignment: .topLeading) {
                            if let shownNote {
                                FeedbackNote(marker: shownNote)
                                    .id(shownNote.id)
                                    .transition(.opacity)
                            } else {
                                Text(PerfectTake.line)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 12)
                                    .padding(.leading, 15)
                                    .background(alignment: .leading) {
                                        Rectangle()
                                            .fill(PerfectTake.green)
                                            .frame(width: 3)
                                            .accessibilityHidden(true)
                                    }
                                    .accessibilityLabel(PerfectTake.lineLabel)
                                    .transition(.opacity)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
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
        .animation(noteAnimation, value: shownNote?.id)
        .onChange(of: player.currentTime) { _, time in
            guard let take = selectedTake else { return }
            followPlayhead(time, markers: take.markers)
        }
    }

    /// Shorter than a screen dissolve. The sentence fades, and the transcript
    /// moves with the space the sentence takes.
    private var noteAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: BlurMotion.reducedFade)
            : .easeInOut(duration: 0.18)
    }

    private func followPlayhead(_ time: TimeInterval, markers: [ReviewMarker]) {
        let choice = VisibleFeedback.marker(
            at: time,
            among: markers,
            previouslyInside: notesInside,
            showing: shownNote?.id,
            preferred: preferredNote
        )
        if notesInside != choice.inside {
            notesInside = choice.inside
        }
        if let preferredNote, !choice.inside.contains(preferredNote) {
            self.preferredNote = nil
        }
        if shownNote != choice.marker {
            shownNote = choice.marker
        }
    }

    private func load(take: RecordingManifest.Take) {
        notesInside = []
        preferredNote = nil
        shownNote = nil
        let url = RecordingsService.store.audioURL(
            regimenID: manifest.id,
            fileName: take.audioFileName
        )
        player.load(url: url)
        followPlayhead(player.currentTime, markers: take.markers)
    }

    private func timeLabel(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

}

/// The sentence for the marker the playhead is near. Body size, regular, and
/// white, with the marker's bar and no fill behind the words.
private struct FeedbackNote: View {
    var marker: ReviewMarker

    var body: some View {
        Text(marker.note)
            .speechType(.body)
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 15)
            .background(alignment: .leading) {
                Rectangle()
                    .fill(markerColor(marker.kind))
                    .frame(width: 3)
                    .accessibilityHidden(true)
            }
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
            .font(.body.monospacedDigit())
            .foregroundStyle(.secondary)
            .digitRoll(label, countsDown: false, reduceMotion: reduceMotion)
    }
}
