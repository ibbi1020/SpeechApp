import DSWaveformImage
import OSLog
import SwiftUI
import SpeechAppKit
import UIKit

func markerColor(_ kind: ReviewMarker.Kind) -> Color {
    switch kind {
    case .pause, .slowStart: .orange
    case .fillerCluster: .yellow
    case .restart: .mint
    case .skippedWord: .purple
    case .swappedWord: .pink
    case .otherLanguage: .indigo
    }
}

struct WaveformScrubber: View {
    let audioURL: URL
    let duration: TimeInterval
    let currentTime: TimeInterval
    let markers: [ReviewMarker]
    var partnerTurns: [PartnerTurn] = []
    var scrubGeneration: Int = 0
    let onSeek: (TimeInterval) -> Void
    let onMarkerTap: (ReviewMarker) -> Void
    var onScrubBegan: () -> Int = { 0 }
    var onScrub: (TimeInterval, Int) -> Void = { _, _ in }
    var onScrubEnded: (Int) -> Void = { _ in }

    /// Opaque, so the partner bars cover the speaker color instead of mixing with it.
    private var agentUnplayed: Color { Color.teal.mix(with: Color.secondary, by: 0.45) }
    private let agentPlayed = Color.teal

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    @State private var samples: [Float] = []
    @State private var sampleKey: SampleKey?
    @State private var pull: CGFloat = 0
    @State private var scrubTime: TimeInterval?
    @State private var dragTime: TimeInterval?
    @State private var downTime: TimeInterval = 0
    @State private var heldGeneration: Int = 0
    @State private var fingerDown = false
    @State private var motionTask: Task<Void, Never>?
    /// Last bar under the needle. A change while scrubbing is one haptic tick.
    @State private var hapticBar: Int?
    @State private var hapticTick = 0

    private static let log = Logger(subsystem: "com.speechapp", category: "WaveformScrubber")
    private static let waveHeight: CGFloat = 56
    /// Room for the time labels, plus a gap before the bars. The prototype draws times only, with no ticks.
    private static let rulerHeight: CGFloat = 22
    /// Prototype bars, a little thicker, with the same gap between them.
    private static let barWidth: CGFloat = 2.5
    private static let barGap: CGFloat = 1.5

    private var shownTime: TimeInterval { scrubTime ?? dragTime ?? currentTime }

    var body: some View {
        let scrolls = duration > TapeLayout.windowSeconds
        GeometryReader { geo in
            let width = geo.size.width
            let layout = TapeLayout(duration: duration, width: width)
            let viewStart = layout.viewStart(time: shownTime, pull: pull)
            let waveTop = scrolls ? Self.rulerHeight : 0
            VStack(spacing: 0) {
                if scrolls {
                    ruler(layout: layout, viewStart: viewStart, width: width)
                        .frame(height: Self.rulerHeight)
                }
                ZStack(alignment: .leading) {
                    waveform(layout: layout, width: width)
                    needle(layout: layout)
                    markerDots(layout: layout, viewStart: viewStart)
                }
                .frame(height: Self.waveHeight)
                .clipped()
            }
            .overlay {
                LanePan(
                    onTap: { point in
                        tapped(point, layout: layout, viewStart: viewStart, waveTop: waveTop)
                    },
                    onBegan: { point in
                        began(at: point, layout: layout)
                    },
                    onChanged: { point, translation in
                        changed(point: point, translation: translation, layout: layout)
                    },
                    onEnded: { velocity in
                        ended(velocity: velocity, layout: layout)
                    },
                    onCancelled: {
                        cancelled(layout: layout)
                    }
                )
            }
            .task(id: analysisID(width: width)) {
                await loadSamples(width: width)
            }
        }
        .frame(height: scrolls ? Self.rulerHeight + Self.waveHeight : Self.waveHeight)
        .onChange(of: audioURL) { _, _ in
            samples = []
            sampleKey = nil
        }
        .sensoryFeedback(.selection, trigger: hapticTick)
        .onChange(of: scrubGeneration) { _, new in
            // beginScrub stores this same value in heldGeneration before SwiftUI delivers the change.
            // A mismatch means a word tap, a marker, or pause replaced the scrub.
            guard new != heldGeneration else { return }
            motionTask?.cancel()
            motionTask = nil
            if !fingerDown {
                pull = 0
                scrubTime = nil
                dragTime = nil
            }
        }
    }

    // MARK: Bars

    @ViewBuilder
    private func waveform(layout: TapeLayout, width: CGFloat) -> some View {
        let current = SampleKey(url: audioURL, width: width, scale: displayScale, duration: duration)
        let picture = Group {
            if sampleKey == current, !samples.isEmpty {
                bars(samples: samples, layout: layout)
            } else if let sampleKey, !samples.isEmpty {
                let old = TapeLayout(duration: sampleKey.duration, width: sampleKey.width)
                let bridge = TapeLayout.widthBridge(oldWidth: sampleKey.width, newWidth: width)
                bars(samples: samples, layout: old)
                    .frame(width: sampleKey.width, height: Self.waveHeight, alignment: .leading)
                    .scaleEffect(
                        x: bridge.scale,
                        y: 1,
                        anchor: UnitPoint(x: layout.scrolls ? TapeLayout.needleFraction : 0, y: 0.5)
                    )
                    .offset(x: layout.scrolls ? bridge.shift : 0)
            }
        }
        .frame(width: width, height: Self.waveHeight, alignment: .leading)
        .clipped()
        if layout.scrolls {
            picture.mask { edgeFade(width: width) }
        } else {
            picture
        }
    }

    /// Vertical bars. In the analyzer, `0` is loudest and `1` is silence, so height uses `1 - sample`.
    private func bars(samples: [Float], layout: TapeLayout) -> some View {
        let played = shownTime
        let shift = pull
        let turns = partnerTurns
        let unplayedPartner = agentUnplayed
        let playedPartner = agentPlayed
        return Canvas { context, size in
            guard layout.window > 0, size.width > 1, layout.duration > 0, !samples.isEmpty else { return }
            let pixelsPerSecond = size.width / CGFloat(layout.window)
            let step = Self.barWidth + Self.barGap
            let viewStart = layout.viewStart(time: played, pull: shift)
            let phase = CGFloat(viewStart) * pixelsPerSecond
            var index = Int(floor(phase / step)) - 1
            let last = index + Int(size.width / step) + 4
            while index <= last {
                let x = CGFloat(index) * step - phase
                index += 1
                if x > size.width { break }
                if x + Self.barWidth < 0 { continue }
                let start = Double(x / pixelsPerSecond) + viewStart
                let end = start + Double(Self.barWidth / pixelsPerSecond)
                let mid = (start + end) / 2
                guard mid >= 0, mid <= layout.duration else { continue }
                let level = Self.loudness(from: start, to: end, samples: samples, duration: layout.duration)
                let height = max(2, level * size.height * 0.86)
                let rect = CGRect(x: x, y: (size.height - height) / 2, width: Self.barWidth, height: height)
                let radius = min(1, Self.barWidth / 2, height / 2)
                let partner = turns.contains { mid >= $0.start && mid < $0.end }
                let heard = mid <= played
                let color: Color
                if partner {
                    color = heard ? playedPartner : unplayedPartner
                } else {
                    color = heard ? Color.primary : Color.primary.opacity(0.22)
                }
                context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(color))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func edgeFade(width: CGFloat) -> some View {
        let fade = min(0.2, 14 / max(width, 1))
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: fade),
                .init(color: .black, location: 1 - fade),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func ruler(layout: TapeLayout, viewStart: TimeInterval, width: CGFloat) -> some View {
        let labels = layout.marks(viewStart: viewStart, every: 15)
        return ZStack(alignment: .topLeading) {
            ForEach(labels, id: \.self) { time in
                Text(timeLabel(time))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .position(x: layout.x(for: time, viewStart: viewStart), y: 8)
            }
        }
        .frame(width: width, height: Self.rulerHeight)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func needle(layout: TapeLayout) -> some View {
        let x = layout.needleX(at: shownTime)
        return ZStack {
            Rectangle()
                .fill(Color.primary)
                .frame(width: 1.5, height: Self.waveHeight)
                .position(x: x, y: Self.waveHeight / 2)
            Circle()
                .fill(Color.primary)
                .frame(width: 7, height: 7)
                .position(x: x, y: 3.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func markerDots(layout: TapeLayout, viewStart: TimeInterval) -> some View {
        ForEach(markers) { marker in
            let x = layout.x(for: marker.start, viewStart: layout.scrolls ? viewStart : 0)
            if x >= 0, x <= layout.width {
                Circle()
                    .fill(markerColor(marker.kind))
                    .frame(width: 10, height: 10)
                    .frame(width: 44, height: 44)
                    .position(x: x, y: Self.waveHeight / 2)
                    .allowsHitTesting(false)
                    .accessibilityElement()
                    .accessibilityLabel(markerAccessibility(marker))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { onMarkerTap(marker) }
            }
        }
    }

    // MARK: Touch

    private func began(at point: CGPoint, layout: TapeLayout) {
        guard layout.width > 0, layout.duration > 0 else { return }
        fingerDown = true
        motionTask?.cancel()
        motionTask = nil
        downTime = shownTime
        if layout.scrolls {
            heldGeneration = onScrubBegan()
            scrubTime = downTime
            pull = 0
            onScrub(downTime, heldGeneration)
        } else {
            dragTime = layout.time(at: point.x, viewStart: 0)
        }
        hapticBar = barUnderNeedle(layout: layout, time: shownTime, pull: pull)
    }

    private func changed(point: CGPoint, translation: CGFloat, layout: TapeLayout) {
        guard layout.width > 0, layout.duration > 0 else { return }
        if layout.scrolls {
            let hold = layout.dragged(from: downTime, translation: translation)
            scrubTime = hold.time
            pull = hold.pull
            onScrub(hold.time, heldGeneration)
        } else {
            dragTime = layout.time(at: point.x, viewStart: 0)
        }
        tickBar(layout: layout, time: shownTime, pull: pull)
    }

    private func ended(velocity: CGFloat, layout: TapeLayout) {
        fingerDown = false
        guard layout.width > 0, layout.duration > 0 else { return }
        if layout.scrolls {
            let motion = layout.release(
                time: scrubTime ?? downTime,
                pull: pull,
                velocity: velocity,
                reduceMotion: reduceMotion
            )
            guard motion.phase != .settled else {
                pull = 0
                onScrub(motion.time, heldGeneration)
                scrubTime = nil
                onScrubEnded(heldGeneration)
                return
            }
            scrubTime = motion.time
            pull = motion.pull
            run(motion, layout: layout, generation: heldGeneration)
        } else if let dragTime {
            onSeek(dragTime)
            self.dragTime = nil
        }
    }

    private func cancelled(layout: TapeLayout) {
        fingerDown = false
        motionTask?.cancel()
        motionTask = nil
        if layout.scrolls {
            let time = min(max(0, scrubTime ?? downTime), duration)
            pull = 0
            onScrub(time, heldGeneration)
            scrubTime = nil
            onScrubEnded(heldGeneration)
        } else if let dragTime {
            onSeek(dragTime)
            self.dragTime = nil
        }
    }

    private func tapped(_ point: CGPoint, layout: TapeLayout, viewStart: TimeInterval, waveTop: CGFloat) {
        guard layout.width > 0, layout.duration > 0 else { return }
        motionTask?.cancel()
        motionTask = nil
        fingerDown = false
        if let marker = marker(at: point, layout: layout, viewStart: viewStart, waveTop: waveTop) {
            pull = 0
            scrubTime = nil
            dragTime = nil
            onMarkerTap(marker)
            return
        }
        let time = layout.time(at: point.x, viewStart: layout.scrolls ? viewStart : 0)
        pull = 0
        scrubTime = nil
        dragTime = nil
        onSeek(time)
    }

    private func marker(at point: CGPoint, layout: TapeLayout, viewStart: TimeInterval, waveTop: CGFloat) -> ReviewMarker? {
        let midY = waveTop + Self.waveHeight / 2
        var best: (ReviewMarker, CGFloat)?
        for marker in markers {
            let x = layout.x(for: marker.start, viewStart: layout.scrolls ? viewStart : 0)
            guard x >= 0, x <= layout.width else { continue }
            let dx = point.x - x
            let dy = point.y - midY
            guard abs(dx) <= 22, abs(dy) <= 22 else { continue }
            let distance = dx * dx + dy * dy
            if best == nil || distance < best!.1 {
                best = (marker, distance)
            }
        }
        return best?.0
    }

    private func run(_ initial: TapeLayout.Motion, layout: TapeLayout, generation: Int) {
        motionTask?.cancel()
        motionTask = Task { @MainActor in
            var motion = initial
            var last = ContinuousClock.now
            while !Task.isCancelled, motion.phase != .settled {
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled else { return }
                let now = ContinuousClock.now
                motion = layout.step(motion, dt: Self.seconds(from: last, to: now))
                last = now
                pull = motion.pull
                scrubTime = motion.time
                onScrub(motion.time, generation)
                tickBar(layout: layout, time: motion.time, pull: motion.pull)
            }
            guard !Task.isCancelled else { return }
            pull = 0
            scrubTime = nil
            onScrubEnded(generation)
        }
    }

    /// One selection tick for each bar that passes the needle. Playback does not call this.
    private func tickBar(layout: TapeLayout, time: TimeInterval, pull: CGFloat) {
        guard let index = barUnderNeedle(layout: layout, time: time, pull: pull) else { return }
        if let previous = hapticBar, index != previous, drawnBar(index, layout: layout, time: time, pull: pull) {
            hapticTick += abs(index - previous)
        }
        hapticBar = index
    }

    /// Bar slot under the needle. The same grid the canvas uses: 2.5pt bar, 1.5pt gap.
    private func barUnderNeedle(layout: TapeLayout, time: TimeInterval, pull: CGFloat) -> Int? {
        let step = Self.barWidth + Self.barGap
        guard layout.pixelsPerSecond > 0, step > 0 else { return nil }
        let phase = CGFloat(layout.viewStart(time: time, pull: pull)) * layout.pixelsPerSecond
        return Int(floor((layout.needleX(at: time) + phase) / step))
    }

    private func drawnBar(_ index: Int, layout: TapeLayout, time: TimeInterval, pull: CGFloat) -> Bool {
        let step = Self.barWidth + Self.barGap
        guard layout.pixelsPerSecond > 0, step > 0, layout.duration > 0 else { return false }
        let viewStart = layout.viewStart(time: time, pull: pull)
        let x = CGFloat(index) * step - CGFloat(viewStart) * layout.pixelsPerSecond
        let start = Double(x / layout.pixelsPerSecond) + viewStart
        let mid = start + Double(Self.barWidth / layout.pixelsPerSecond) / 2
        return mid >= 0 && mid <= layout.duration
    }

    private static func seconds(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> TimeInterval {
        let span = start.duration(to: end)
        return Double(span.components.seconds) + Double(span.components.attoseconds) / 1e18
    }

    // MARK: Samples

    private struct SampleKey: Equatable {
        var url: URL
        var width: CGFloat
        var scale: CGFloat
        var duration: TimeInterval
    }

    private func analysisID(width: CGFloat) -> String {
        "\(audioURL.path)|\(width)|\(displayScale)|\(duration)"
    }

    private func loadSamples(width: CGFloat) async {
        guard width >= 1, duration > 0, displayScale > 0 else { return }
        let window = min(duration, TapeLayout.windowSeconds)
        let count = Int(duration / window * width * displayScale)
        guard count > 0 else { return }
        let key = SampleKey(url: audioURL, width: width, scale: displayScale, duration: duration)
        do {
            let analyzed = try await WaveformAnalyzer().samples(fromAudioAt: key.url, count: count)
            guard !Task.isCancelled, audioURL == key.url else { return }
            samples = analyzed
            sampleKey = key
        } catch {
            guard !Task.isCancelled, audioURL == key.url else { return }
            Self.log.error("waveform failed: \(error.localizedDescription, privacy: .public)")
            samples = []
            sampleKey = nil
        }
    }

    /// Loudest sample in the bar. `1` in the cache is silence, so the result is `0` when the stretch is quiet.
    private static func loudness(
        from start: TimeInterval,
        to end: TimeInterval,
        samples: [Float],
        duration: TimeInterval
    ) -> CGFloat {
        guard duration > 0, !samples.isEmpty, end > start else { return 0 }
        let count = samples.count
        let first = max(0, min(count - 1, Int(floor(start / duration * Double(count)))))
        let last = max(first, min(count - 1, Int(ceil(end / duration * Double(count))) - 1))
        var peak: Float = 1
        for index in first...last {
            peak = min(peak, samples[index])
        }
        return CGFloat(max(0, 1 - peak))
    }

    private func timeLabel(_ time: TimeInterval) -> String {
        let seconds = max(0, Int(time.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
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

/// Horizontal drags scrub. Vertical drags fail this recognizer so the page can scroll.
private struct LanePan: UIViewRepresentable {
    var onTap: (CGPoint) -> Void
    var onBegan: (CGPoint) -> Void
    var onChanged: (CGPoint, CGFloat) -> Void
    var onEnded: (CGFloat) -> Void
    var onCancelled: () -> Void

    func makeUIView(context: Context) -> LaneTouchView {
        LaneTouchView()
    }

    func updateUIView(_ view: LaneTouchView, context: Context) {
        view.onTap = onTap
        view.onBegan = onBegan
        view.onChanged = onChanged
        view.onEnded = onEnded
        view.onCancelled = onCancelled
    }
}

private final class LaneTouchView: UIView, UIGestureRecognizerDelegate {
    var onTap: (CGPoint) -> Void = { _ in }
    var onBegan: (CGPoint) -> Void = { _ in }
    var onChanged: (CGPoint, CGFloat) -> Void = { _, _ in }
    var onEnded: (CGFloat) -> Void = { _ in }
    var onCancelled: () -> Void = {}

    private let pan = UIPanGestureRecognizer()
    private var start: CGPoint = .zero
    private var claimed = false
    private var wentVertical = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        pan.addTarget(self, action: #selector(panned(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) { nil }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        claimed = false
        wentVertical = false
        start = touches.first?.location(in: self) ?? .zero
        super.touchesBegan(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !claimed, !wentVertical {
            onTap(start)
        }
        super.touchesEnded(touches, with: event)
    }

    @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
        let location = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            claimed = true
            onBegan(start)
        case .changed:
            onChanged(location, location.x - start.x)
        case .ended:
            claimed = false
            onEnded(recognizer.velocity(in: self).x)
        case .cancelled:
            claimed = false
            onCancelled()
        case .failed:
            wentVertical = true
        default:
            break
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: self)
        if abs(velocity.y) > abs(velocity.x) {
            wentVertical = true
            return false
        }
        return true
    }
}
