import SwiftUI

/// Shared motion, materials, and chrome for Reading — Apple Design defaults.
enum SpeechMotion {
    /// Critically damped UI settle (damping ~1.0, response ~0.35).
    static let settle = Animation.spring(response: 0.35, dampingFraction: 1.0)
    /// Slightly snappier press / highlight.
    static let press = Animation.spring(response: 0.22, dampingFraction: 1.0)
    /// Karaoke cursor handoff — short ease, not a bouncy spring (CHI flicker risk).
    static let follow = Animation.easeOut(duration: 0.08)
    /// Passage auto-scroll — reading-app ease, not a snap.
    static let scroll = Animation.easeInOut(duration: 0.45)
}

enum SpeechSpacing {
    /// Page gutter.
    static let page: CGFloat = 24
    /// Reading passage gutter (wider than chrome).
    static let reading: CGFloat = 32
    /// Tight grouping inside a header or card cluster.
    static let cluster: CGFloat = 8
    /// Related items in one section.
    static let related: CGFloat = 16
    /// Break between different sections.
    static let section: CGFloat = 36
}

/// Reading start-gate tokens. Fog the page until listening starts.
enum SpeechCountdown {
    /// Soft enough that the page stays present, just not readable.
    static let fogBlurRadius: CGFloat = 7
    static let fogWashOpacity: Double = 0.18
    /// Heavier wash when Reduce Transparency disables blur.
    static let reducedTransparencyWash: Double = 0.52
    static let digitSize: CGFloat = 92
    static let instruction = "Take a deep breath and read at your own pace"
}

struct SpeechScreenBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color(.secondarySystemBackground).opacity(0.55),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

struct SpeechPrimaryButtonStyle: ButtonStyle {
    var tint: Color = .accentColor
    var isDestructive: Bool = false
    /// Tinted glass for the primary go action. Other primaries stay clear glass.
    var showsTint: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let glass: Glass = showsTint
            ? .regular.tint(isDestructive ? .red : tint).interactive()
            : .regular.interactive()
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(showsTint ? AnyShapeStyle(.white) : AnyShapeStyle(isDestructive ? Color.red : Color.primary))
            .glassEffect(glass, in: .rect(cornerRadius: 14))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(SpeechMotion.press, value: configuration.isPressed)
    }
}

struct SpeechSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.primary)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(SpeechMotion.press, value: configuration.isPressed)
    }
}

/// Equal pause / stop circle chrome for live session bars.
struct SpeechGlassCircleLabel: ViewModifier {
    var tint: Color?

    func body(content: Content) -> some View {
        let glass: Glass = if let tint {
            .regular.tint(tint).interactive()
        } else {
            .regular.interactive()
        }
        content
            .font(.body.weight(.semibold))
            .foregroundStyle(tint == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
            .frame(width: 52, height: 52)
            .contentShape(Circle())
            .glassEffect(glass, in: .circle)
    }
}

extension View {
    func speechGlassCircle(tint: Color? = nil) -> some View {
        modifier(SpeechGlassCircleLabel(tint: tint))
    }
}

/// Sharp 3-2-1 over a fogged passage. The number is the only in-focus object.
struct ReadingCountdownOverlay: View {
    let remaining: Int?
    var instruction: String = SpeechCountdown.instruction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accessibilityText: String {
        if let remaining {
            "\(remaining). \(instruction)"
        } else {
            instruction
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            if let remaining {
                Text("\(remaining)")
                    .font(.system(size: SpeechCountdown.digitSize, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .opacity : .numericText())
                    .foregroundStyle(.primary)
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle,
                        value: remaining
                    )
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.primary)
            }

            Text(instruction)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: -12)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityLabel(accessibilityText)
        .allowsHitTesting(false)
    }
}

