import SwiftUI
import SpeechAppKit

/// The one ceremony on Home. A press and hold, with the remaining time shown as a
/// white wipe across the capsule and the label flipping to black as the wipe passes it.
///
/// Feedback starts on touch-down and tracks the hold continuously. Releasing early
/// springs the wipe back, critically damped.
struct HoldToBeginButton: View {
    let title: String
    /// Fires true on touch-down and false when the hold ends, either way.
    let onHoldChange: (Bool) -> Void
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pressedAt: Date?
    /// Where the wipe sits when no finger is down, so a release can spring back.
    @State private var residual: Double = 0
    @State private var commitTask: Task<Void, Never>?
    @State private var completions = 0

    private let hold = HoldToBegin()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                label(.white)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    // Glass over pure black reads as an inert dark pill without an edge.
                    .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                wipe(width: proxy.size.width)
            }
            .scaleEffect(pressedAt == nil ? 1 : 0.98)
            .animation(SpeechMotion.press, value: pressedAt == nil)
        }
        .frame(height: SpeechStartMetrics.height)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in begin() }
                .onEnded { _ in cancel() }
        )
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.4), trigger: pressedAt != nil)
        .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.9), trigger: completions)
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityHint("Press and hold")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { complete() }
        .onDisappear { stopClock() }
    }

    /// While a finger is down the wipe reads off a real clock, so what the user sees
    /// is the same fraction the commit is timed against.
    @ViewBuilder
    private func wipe(width: CGFloat) -> some View {
        if let pressedAt {
            TimelineView(.animation) { timeline in
                filled(
                    width: width,
                    fraction: hold.fraction(elapsed: timeline.date.timeIntervalSince(pressedAt))
                )
            }
        } else {
            filled(width: width, fraction: residual)
        }
    }

    private func filled(width: CGFloat, fraction: Double) -> some View {
        label(.black)
            .background(.white, in: .capsule)
            .mask(alignment: .leading) {
                Rectangle().frame(width: width * fraction)
            }
    }

    private func label(_ foreground: Color) -> some View {
        Text(title)
            .font(.system(size: SpeechStartMetrics.labelSize, weight: .medium))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: SpeechStartMetrics.height)
    }

    private func begin() {
        guard pressedAt == nil else { return }
        pressedAt = .now
        onHoldChange(true)
        commitTask = Task {
            try? await Task.sleep(for: .seconds(hold.duration))
            guard !Task.isCancelled else { return }
            complete()
        }
    }

    private func complete() {
        completions += 1
        residual = 1
        stopClock()
        onHoldChange(false)
        onComplete()
    }

    private func cancel() {
        guard let pressedAt else { return }
        residual = hold.fraction(elapsed: Date.now.timeIntervalSince(pressedAt))
        stopClock()
        onHoldChange(false)
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
            residual = 0
        }
    }

    private func stopClock() {
        commitTask?.cancel()
        commitTask = nil
        pressedAt = nil
    }
}
