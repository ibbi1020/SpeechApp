import AVFoundation
import DSWaveformImage
import DSWaveformImageViews
import SwiftUI
import SpeechAppKit

struct WaveformScrubber: View {
    let audioURL: URL
    let duration: TimeInterval
    let currentTime: TimeInterval
    let markers: [ReviewMarker]
    var partnerTurns: [PartnerTurn] = []
    let onSeek: (TimeInterval) -> Void
    let onMarkerTap: (ReviewMarker) -> Void

    /// Opaque, so the partner bars cover the speaker color instead of mixing with it.
    private var agentUnplayed: Color { Color.teal.mix(with: Color.secondary, by: 0.45) }
    private let agentPlayed = Color.teal

    @State private var dragTime: TimeInterval?

    private var progress: Double {
        let t = dragTime ?? currentTime
        guard duration > 0 else { return 0 }
        return min(1, max(0, t / duration))
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                WaveformView(audioURL: audioURL) { shape in
                    let played = dragTime ?? currentTime
                    ForEach(Array(speakerRanges.enumerated()), id: \.offset) { _, range in
                        colored(shape, color: Color.primary.opacity(0.22), from: range.start, to: range.end)
                        let playedEnd = min(range.end, played)
                        if playedEnd > range.start {
                            colored(shape, color: Color.primary, from: range.start, to: playedEnd)
                        }
                    }
                    ForEach(Array(partnerTurns.enumerated()), id: \.offset) { _, turn in
                        colored(shape, color: agentUnplayed, from: turn.start, to: turn.end)
                        let playedEnd = min(turn.end, played)
                        if playedEnd > turn.start {
                            colored(shape, color: agentPlayed, from: turn.start, to: playedEnd)
                        }
                    }
                }

                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 1.5)
                    .offset(x: width * progress)

                ForEach(markers) { marker in
                    let x = markerX(marker.start, width: width)
                    Button {
                        onMarkerTap(marker)
                    } label: {
                        Circle()
                            .fill(markerColor(marker.kind))
                            .frame(width: 10, height: 10)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .position(x: x, y: geo.size.height / 2)
                    .accessibilityLabel(markerAccessibility(marker))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragTime = time(at: value.location.x, width: width)
                    }
                    .onEnded { value in
                        let t = time(at: value.location.x, width: width)
                        dragTime = nil
                        onSeek(t)
                    }
            )
        }
        .frame(height: 56)
    }

    private struct TimeRange {
        let start: TimeInterval
        let end: TimeInterval
    }

    /// Stretches that are not a partner turn.
    private var speakerRanges: [TimeRange] {
        let turns = partnerTurns.sorted { $0.start < $1.start }
        var cursor: TimeInterval = 0
        var ranges: [TimeRange] = []
        for turn in turns {
            if turn.start > cursor {
                ranges.append(TimeRange(start: cursor, end: turn.start))
            }
            cursor = max(cursor, turn.end)
        }
        if duration > cursor {
            ranges.append(TimeRange(start: cursor, end: duration))
        }
        return ranges
    }

    private func colored(
        _ shape: WaveformShape,
        color: Color,
        from start: TimeInterval,
        to end: TimeInterval
    ) -> some View {
        shape.fill(color).mask {
            Canvas { context, size in
                guard duration > 0, size.width > 0 else { return }
                let x = CGFloat(max(0, start) / duration) * size.width
                let endX = CGFloat(max(0, end) / duration) * size.width
                let rect = CGRect(x: x, y: 0, width: max(0, endX - x), height: size.height)
                context.fill(Path(rect), with: .color(.white))
            }
        }
    }

    private func markerX(_ time: TimeInterval, width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(time / duration) * width
    }

    private func time(at x: CGFloat, width: CGFloat) -> TimeInterval {
        guard width > 0, duration > 0 else { return 0 }
        let fraction = min(1, max(0, x / width))
        return duration * Double(fraction)
    }

    private func markerColor(_ kind: ReviewMarker.Kind) -> Color {
        switch kind {
        case .pause, .slowStart: .orange
        case .fillerCluster: .yellow
        case .restart: .mint
        case .skippedWord: .purple
        case .swappedWord: .pink
        case .otherLanguage: .indigo
        }
    }

    private func markerAccessibility(_ marker: ReviewMarker) -> String {
        switch marker.kind {
        case .pause: "Pause marker"
        case .fillerCluster: "Filler cluster marker"
        case .restart: "Restart marker"
        case .skippedWord: "Skipped word marker"
        case .swappedWord: "Swapped word marker"
        case .slowStart: "Slow start marker"
        case .otherLanguage: "Other language marker"
        }
    }
}
