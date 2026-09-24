import SwiftUI
import WebKit

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

    private var showsInstruction: Bool {
        !instruction.isEmpty
    }

    private var accessibilityText: String {
        if let remaining {
            showsInstruction ? "\(remaining). \(instruction)" : "\(remaining)"
        } else {
            showsInstruction ? instruction : "Preparing"
        }
    }

    var body: some View {
        VStack(spacing: showsInstruction ? 14 : 0) {
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

            if showsInstruction {
                Text(instruction)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: -12)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityLabel(accessibilityText)
        .allowsHitTesting(false)
    }
}

/// [orb-ui](https://orb-ui.com) cloud theme, the orb on the homepage.
/// Session chrome uses this instead of `AuroraPill`.
struct VoiceOrb: View {
    enum Phase: Equatable {
        case idle
        case connecting
        case listening
        case speaking
    }

    var phase: Phase
    var inputVolume: Float = 0
    var outputVolume: Float = 0
    var animating: Bool = true

    /// 25% larger than the original 120pt homepage orb.
    static let box: CGFloat = 150
    /// orb-ui cloud theme draws the sphere at this fraction of `box`.
    private static let diameterRatio: CGFloat = 0.55
    /// How far the glass buttons overlap the drawn sphere.
    private static let controlOverlap: CGFloat = 14

    /// Negative spacing that pulls pause and stop through the clear margin onto the cloud.
    static var controlSpacing: CGFloat {
        let halo = box * (1 - diameterRatio) / 2
        return -(halo + controlOverlap)
    }

    /// Idle hides a non-interactive cloud. Pause keeps the sphere and desaturates it.
    private var shownPhase: Phase { animating ? phase : .listening }

    private var level: Double {
        guard animating else { return 0 }
        let raw = shownPhase == .speaking ? outputVolume : inputVolume
        return min(1, max(0, Double(raw)))
    }

    var body: some View {
        OrbWebView(
            phase: shownPhase,
            inputVolume: shownPhase == .listening ? level : 0,
            outputVolume: shownPhase == .speaking ? level : 0,
            paused: !animating
        )
        .frame(width: Self.box, height: Self.box)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var label: String {
        if !animating { return "Paused." }
        switch shownPhase {
        case .speaking: return "Speaking."
        case .connecting: return "Connecting."
        case .listening: return level > 0.28 ? "Hearing you." : "Listening."
        case .idle: return "Listening."
        }
    }
}

private struct OrbWebView: UIViewRepresentable {
    var phase: VoiceOrb.Phase
    var inputVolume: Double
    var outputVolume: Double
    var paused: Bool

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.underPageBackgroundColor = .clear
        webView.isUserInteractionEnabled = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.backgroundColor = .clear
        if let url = Bundle.main.url(forResource: "voice-orb", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let state: String
        switch phase {
        case .idle: state = "idle"
        case .connecting: state = "connecting"
        case .listening: state = "listening"
        case .speaking: state = "speaking"
        }
        let input = String(format: "%.3f", inputVolume)
        let output = String(format: "%.3f", outputVolume)
        let pausedFlag = paused ? "true" : "false"
        let script = """
        document.documentElement.classList.toggle('paused', \(pausedFlag));
        window.orbSetSignal && window.orbSetSignal('\(state)', \(input), \(output));
        """
        webView.evaluateJavaScript(script)
    }
}

