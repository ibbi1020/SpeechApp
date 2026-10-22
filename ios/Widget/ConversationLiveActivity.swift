import SwiftUI
import WidgetKit
import SpeechAppKit

struct ConversationLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ConversationAttributes.self) { context in
            IslandControls(state: context.state, surface: .lockScreen, button: 44, orb: 36)
                .padding(16)
                .widgetURL(ConversationLiveActivityLink.url(for: context.attributes.conversationID))
                .activityBackgroundTint(Color.black.opacity(0.92))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandOrb(look: context.state.orb, size: ExpandedFit.mark)
                        .frame(maxHeight: .infinity, alignment: .center)
                        .accessibilityLabel("Conversation. This partner is AI, not a person.")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandActions(
                        state: context.state,
                        surface: .expanded,
                        button: ExpandedFit.mark,
                        spacing: ExpandedFit.padding
                    )
                    .frame(maxHeight: .infinity, alignment: .center)
                }
            } compactLeading: {
                CompactOrb(look: context.state.orb)
            } compactTrailing: {
                CompactTimer(state: context.state)
            } minimal: {
                MinimalMark(state: context.state)
            }
            .widgetURL(ConversationLiveActivityLink.url(for: context.attributes.conversationID))
            .keylineTint(Color(red: 0.48, green: 0.56, blue: 0.985))
            // Same inset on every edge, so the circles sit in the middle of the pill.
            .contentMargins(.all, ExpandedFit.padding, for: .expanded)
            // Outer edges of the compact pill. Only the outside edge, so left and right match.
            .contentMargins(.leading, CompactFit.inset, for: .compactLeading)
            .contentMargins(.trailing, CompactFit.inset, for: .compactTrailing)
            .contentMargins(.all, 0, for: .minimal)
        }
    }
}

/// Expanded island corner radius. A circle inset by `padding` shares that center.
private enum ExpandedFit {
    static let cornerRadius: CGFloat = 44
    static let padding: CGFloat = 12
    static let mark: CGFloat = (cornerRadius - padding) * 2
}

/// Distance from the compact pill edge to the orb, and from the other edge to the timer.
private enum CompactFit {
    static let inset: CGFloat = 8
}

/// One row for the Lock Screen. The island uses the two halves separately.
private struct IslandControls: View {
    var state: ConversationAttributes.ContentState
    var surface: ConversationLiveActivitySurface
    var button: CGFloat
    var orb: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            IslandIdentity(state: state, orb: orb)
            Spacer(minLength: 12)
            IslandActions(state: state, surface: surface, button: button)
        }
    }
}

private struct IslandIdentity: View {
    var state: ConversationAttributes.ContentState
    var orb: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            IslandOrb(look: state.orb, size: orb)
            VStack(alignment: .leading, spacing: 1) {
                Text("Conversation")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                IslandTimer(state: state, width: 52, alignment: .leading)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Conversation. This partner is AI, not a person.")
    }
}

private struct IslandActions: View {
    var state: ConversationAttributes.ContentState
    var surface: ConversationLiveActivitySurface
    var button: CGFloat
    var spacing: CGFloat = 12

    var body: some View {
        HStack(spacing: spacing) {
            if ConversationLiveActivityPolicy.showsPause(on: surface, phase: islandPhase(state.phase)) {
                IslandPauseButton(paused: state.phase == .paused, diameter: button)
            }
            if ConversationLiveActivityPolicy.showsStop(on: surface) {
                IslandStopButton(diameter: button)
            }
        }
    }
}

private func islandPhase(_ phase: ConversationActivityPhase) -> ConversationIslandPhase {
    switch phase {
    case .talking: .talking
    case .paused: .paused
    case .wrapping: .wrapping
    }
}

/// Compact leading. A small chip, the same size as a call glyph, so the pill stays narrow.
private struct CompactOrb: View {
    var look: ConversationActivityOrb

    var body: some View {
        IslandWidth { limited in
            IslandOrb(look: look, size: limited ? 28 : 16)
        }
    }
}

/// Compact trailing. A fixed width stops `Text(timerInterval:)` from stretching the island.
private struct CompactTimer: View {
    var state: ConversationAttributes.ContentState

    var body: some View {
        IslandWidth { limited in
            if ConversationLiveActivityPolicy.showsTimer(on: .compact, limitedWidth: limited) {
                IslandTimer(state: state, width: 38, alignment: .trailing)
                    .font(.system(size: 12, weight: .semibold))
            }
        }
    }
}

private struct MinimalMark: View {
    var state: ConversationAttributes.ContentState

    var body: some View {
        IslandWidth { limited in
            if ConversationLiveActivityPolicy.showsTimer(on: .minimal, limitedWidth: limited) {
                IslandTimer(state: state, width: 36, alignment: .center)
                    .font(.system(size: 11, weight: .semibold))
            } else {
                IslandOrb(look: state.orb, size: limited ? 28 : 16)
                    .frame(width: limited ? 28 : 18, height: limited ? 28 : 18)
            }
        }
    }
}

/// `isDynamicIslandLimitedInWidth` arrived in iOS 27. Older phones keep the timer.
private struct IslandWidth<Content: View>: View {
    @ViewBuilder var content: (Bool) -> Content

    var body: some View {
        if #available(iOS 27, *) {
            IslandWidthProbe(content: content)
        } else {
            content(false)
        }
    }
}

@available(iOS 27, *)
private struct IslandWidthProbe<Content: View>: View {
    @Environment(\.isDynamicIslandLimitedInWidth) private var limitedWidth
    @ViewBuilder var content: (Bool) -> Content

    var body: some View {
        content(limitedWidth)
    }
}

private struct IslandTimer: View {
    var state: ConversationAttributes.ContentState
    var width: CGFloat
    var alignment: Alignment

    var body: some View {
        if state.timerEnd > state.timerStart {
            Text(
                timerInterval: state.timerStart...state.timerEnd,
                pauseTime: state.pauseTime,
                countsDown: false,
                showsHours: false
            )
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(.white)
            .frame(width: width, alignment: alignment)
        }
    }
}

private struct IslandPauseButton: View {
    var paused: Bool
    var diameter: CGFloat

    var body: some View {
        Button(intent: PauseConversationIntent()) {
            Image(systemName: paused ? "play.fill" : "pause.fill")
                .font(.system(size: diameter * 0.38, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(Color.white.opacity(0.18)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(paused ? "Resume" : "Pause")
    }
}

private struct IslandStopButton: View {
    var diameter: CGFloat

    var body: some View {
        Button(intent: StopConversationIntent()) {
            Image(systemName: "stop.fill")
                .font(.system(size: diameter * 0.36, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(Color.red))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop")
    }
}
