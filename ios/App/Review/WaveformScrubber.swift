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
    let onSeek: (TimeInterval) -> Void
    let onMarkerTap: (ReviewMarker) -> Void

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
                    shape.fill(Color.secondary.opacity(0.35))
                    shape.fill(Color.accentColor).mask(alignment: .leading) {
                        Rectangle().frame(width: width * progress)
                    }
                }

                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 2)
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
        }
    }
}
