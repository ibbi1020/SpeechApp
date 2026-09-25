import SwiftUI
import UIKit
import WebKit
import SpeechAppKit

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
        remaining != nil && !instruction.isEmpty
    }

    private var accessibilityText: String {
        if let remaining {
            showsInstruction ? "\(remaining). \(instruction)" : "\(remaining)"
        } else {
            "Preparing"
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
                    .transition(.opacity)
            }
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle,
            value: remaining == nil
        )
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
    /// Same three looks as `OrbVisualPhase`: connecting / listening / speaking.
    typealias Phase = OrbVisualPhase

    var phase: Phase
    var inputVolume: Float = 0
    var outputVolume: Float = 0
    var animating: Bool = true

    /// 25% larger than the original 120pt homepage orb.
    static let box: CGFloat = 150
    /// orb-ui cloud theme draws the sphere at this fraction of `box`.
    private static let diameterRatio: CGFloat = 0.55
    /// Clear space between each glass button and the drawn sphere.
    private static let controlGap: CGFloat = 16

    /// HStack spacing that leaves `controlGap` between the buttons and the cloud.
    /// The web view is wider than the sphere, so this is negative without overlapping it.
    static var controlSpacing: CGFloat {
        let halo = box * (1 - diameterRatio) / 2
        return controlGap - halo
    }

    private var level: Double {
        let raw = phase == .speaking ? outputVolume : inputVolume
        return min(1, max(0, Double(raw)))
    }

    var body: some View {
        OrbWebView(
            phase: phase,
            inputVolume: phase == .listening ? level : 0,
            outputVolume: phase == .speaking ? level : 0,
            paused: !animating
        )
        .frame(width: Self.box, height: Self.box)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var label: String {
        if !animating { return "Paused." }
        switch phase {
        case .speaking: return "Speaking."
        case .connecting: return "Connecting."
        case .listening: return level > 0.28 ? "Hearing you." : "Listening."
        }
    }
}

/// Starts loading the orb HTML as soon as a window exists so the first
/// session chrome does not wait on WebKit + WebGL.
@MainActor
enum VoiceOrbPreloader {
    static func warmup() {
        Host.shared.warmup()
    }

    fileprivate static func borrow() -> WKWebView {
        Host.shared.borrow()
    }

    fileprivate static func park(_ webView: WKWebView) {
        Host.shared.park(webView)
    }

    fileprivate static func loadOrbHTML(into webView: WKWebView) {
        guard let url = Bundle.main.url(forResource: "voice-orb", withExtension: "html") else { return }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    @MainActor
    private final class Host {
        static let shared = Host()

        private let parkView = UIView(
            frame: CGRect(x: 0, y: 0, width: VoiceOrb.box, height: VoiceOrb.box)
        )
        private var webView: WKWebView?

        func warmup() {
            _ = preparedWebView()
            attachPark()
        }

        func borrow() -> WKWebView {
            let webView = preparedWebView()
            webView.removeFromSuperview()
            return webView
        }

        func park(_ webView: WKWebView) {
            guard webView === self.webView else { return }
            attachPark()
            if webView.superview !== parkView {
                parkView.addSubview(webView)
                webView.frame = parkView.bounds
                webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            }
        }

        private func preparedWebView() -> WKWebView {
            if let webView { return webView }
            let webView = Self.makeWebView()
            self.webView = webView
            attachPark()
            parkView.addSubview(webView)
            webView.frame = parkView.bounds
            webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            VoiceOrbPreloader.loadOrbHTML(into: webView)
            return webView
        }

        private func attachPark() {
            guard parkView.superview == nil, let window = Self.keyWindow else { return }
            parkView.frame = CGRect(
                x: -VoiceOrb.box,
                y: -VoiceOrb.box,
                width: VoiceOrb.box,
                height: VoiceOrb.box
            )
            // Keep alpha at 1 off-screen. Alpha 0 can drop the WebGL context while parked.
            parkView.alpha = 1
            parkView.isUserInteractionEnabled = false
            window.insertSubview(parkView, at: 0)
        }

        private static var keyWindow: UIWindow? {
            let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
            return windows.first(where: \.isKeyWindow) ?? windows.first
        }

        private static func makeWebView() -> WKWebView {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let webView = WKWebView(
                frame: CGRect(x: 0, y: 0, width: VoiceOrb.box, height: VoiceOrb.box),
                configuration: configuration
            )
            webView.isOpaque = false
            webView.backgroundColor = .clear
            webView.underPageBackgroundColor = .clear
            webView.isUserInteractionEnabled = false
            webView.scrollView.isScrollEnabled = false
            webView.scrollView.bounces = false
            webView.scrollView.backgroundColor = .clear
            return webView
        }
    }
}

private struct OrbWebView: UIViewRepresentable {
    var phase: VoiceOrb.Phase
    var inputVolume: Double
    var outputVolume: Double
    var paused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = VoiceOrbPreloader.borrow()
        webView.navigationDelegate = context.coordinator
        if webView.url != nil, !webView.isLoading {
            context.coordinator.markReady()
            context.coordinator.push(to: webView)
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.phase = phase
        context.coordinator.inputVolume = inputVolume
        context.coordinator.outputVolume = outputVolume
        context.coordinator.paused = paused
        context.coordinator.push(to: webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
        VoiceOrbPreloader.park(webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var phase: VoiceOrb.Phase = .listening
        var inputVolume = 0.0
        var outputVolume = 0.0
        var paused = false
        private var pageReady = false
        private var lastScript: String?
        private var isReloading = false

        func markReady() {
            pageReady = true
            isReloading = false
            lastScript = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            markReady()
            push(to: webView)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            reloadOrb(in: webView)
        }

        /// Pushes the latest signal once the page is ready.
        /// Skips identical scripts; reloads if WebGL reports a lost context.
        func push(to webView: WKWebView) {
            guard pageReady, !isReloading else { return }
            webView.evaluateJavaScript("!!window.orbContextLost") { [weak self] result, _ in
                guard let self else { return }
                if result as? Bool == true {
                    self.reloadOrb(in: webView)
                } else {
                    self.applySignal(to: webView)
                }
            }
        }

        private func applySignal(to webView: WKWebView) {
            let script = makeScript()
            guard script != lastScript else { return }
            lastScript = script
            webView.evaluateJavaScript(script)
        }

        private func reloadOrb(in webView: WKWebView) {
            guard !isReloading else { return }
            isReloading = true
            pageReady = false
            lastScript = nil
            VoiceOrbPreloader.loadOrbHTML(into: webView)
        }

        private func makeScript() -> String {
            if paused {
                // Leave the last frame in place. A new signal would move the cloud when it resumes.
                return "window.orbFrozen=true;document.documentElement.classList.add('paused');"
            }
            let input = String(format: "%.3f", inputVolume)
            let output = String(format: "%.3f", outputVolume)
            return """
            window.orbFrozen=false;\
            document.documentElement.classList.remove('paused');\
            window.orbSetSignal&&window.orbSetSignal('\(phase.webState)',\(input),\(output));
            """
        }
    }
}

private extension OrbVisualPhase {
    /// Connecting keeps the cloud and fades the spinner on top.
    var webState: String {
        switch self {
        case .connecting: "connecting"
        case .listening: "listening"
        case .speaking: "speaking"
        }
    }
}

