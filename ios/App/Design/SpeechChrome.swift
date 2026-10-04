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

/// Soft Gaussian where content meets the bottom edge.
/// `ScrollEdgeEffectStyle.soft` is the system effect: sharper farther up,
/// blurrier at the edge. Pass `bar: false` when the screen already has a bottom bar.
struct SpeechSoftEdge: ViewModifier {
    var showsBar: Bool

    func body(content: Content) -> some View {
        if showsBar {
            content
                .scrollEdgeEffectStyle(.soft, for: .bottom)
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    Color.clear
                        .frame(height: 12)
                        .accessibilityHidden(true)
                }
        } else {
            content.scrollEdgeEffectStyle(.soft, for: .bottom)
        }
    }
}

extension View {
    func speechBottomBlur(bar: Bool = true) -> some View {
        modifier(SpeechSoftEdge(showsBar: bar))
    }
}

/// White pill used to start an exercise. Measured from the reference:
/// 61pt tall, capsule ends, black SF Pro at 17pt medium.
enum SpeechStartMetrics {
    static let height: CGFloat = 61
    static let labelSize: CGFloat = 17
    /// Reference sits 36pt from the screen edge. Page chrome is already 24pt.
    static let extraInset: CGFloat = 12
}

struct SpeechStartButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: SpeechStartMetrics.labelSize, weight: .medium))
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity)
            .frame(height: SpeechStartMetrics.height)
            .background(Color.white, in: Capsule())
            .padding(.horizontal, SpeechStartMetrics.extraInset)
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.92 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1)
            .animation(SpeechMotion.press, value: configuration.isPressed)
    }
}

struct SpeechPrimaryButtonStyle: ButtonStyle {
    var tint: Color = .accentColor
    var isDestructive: Bool = false
    /// Tinted glass for the primary go action. Other primaries stay clear glass.
    var showsTint: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        SpeechPillBody(
            configuration: configuration,
            font: .headline,
            verticalPadding: 16,
            foreground: showsTint ? AnyShapeStyle(.white) : AnyShapeStyle(isDestructive ? Color.red : Color.primary),
            tint: showsTint ? (isDestructive ? .red : tint) : nil
        )
    }
}

struct SpeechSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SpeechPillBody(
            configuration: configuration,
            font: .body.weight(.semibold),
            verticalPadding: 14,
            foreground: AnyShapeStyle(.primary),
            tint: nil
        )
    }
}

/// Full-width glass pill shared by the primary and secondary styles.
/// - The whole pill is the hit area (`contentShape`), not just the label glyphs.
/// - Press feedback comes only from interactive glass, so there is one press effect.
/// - Disabled reads as disabled: dimmed, and the glass stops reacting.
private struct SpeechPillBody: View {
    @Environment(\.isEnabled) private var isEnabled
    let configuration: ButtonStyleConfiguration
    let font: Font
    let verticalPadding: CGFloat
    let foreground: AnyShapeStyle
    let tint: Color?

    private static var shape: Capsule { Capsule() }

    var body: some View {
        let base: Glass = if let tint { .regular.tint(tint) } else { .regular }
        configuration.label
            .font(font)
            .frame(maxWidth: .infinity)
            .padding(.vertical, verticalPadding)
            .foregroundStyle(foreground)
            .contentShape(Self.shape)
            .glassEffect(isEnabled ? base.interactive() : base, in: Self.shape)
            .opacity(isEnabled ? 1 : 0.45)
    }
}

enum SpeechFrame {
    /// Suspends long enough for the run loop to commit the current SwiftUI frame, so state set
    /// in a button action is on screen before follow-up work runs on the main actor.
    static func yieldForRender() async {
        try? await Task.sleep(for: .milliseconds(20))
    }
}

/// Drops a second activation that lands within `interval` of the last accepted one.
/// Used on toggles (Pause / Resume, Change topic) so a double tap does not undo itself.
struct TapThrottle {
    private var last: Date = .distantPast

    mutating func allow(interval: TimeInterval = 0.35, now: Date = .now) -> Bool {
        guard now.timeIntervalSince(last) >= interval else { return false }
        last = now
        return true
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
        ZStack {
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
                    .offset(y: SpeechCountdown.digitSize / 2 + 22)
                    .transition(.opacity)
            }
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle,
            value: remaining == nil
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
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
    private static let controlGap: CGFloat = 28

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

/// Live session bar: leading control, the shared orb, trailing control.
/// Reading, Conversation, and Monologue all mount this. The orb is one WebGL view.
struct SessionOrbBar<Leading: View, Trailing: View>: View {
    var phase: VoiceOrb.Phase
    var inputVolume: Float = 0
    var outputVolume: Float = 0
    var animating: Bool = true
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: VoiceOrb.controlSpacing) {
            leading()
            VoiceOrb(
                phase: phase,
                inputVolume: inputVolume,
                outputVolume: outputVolume,
                animating: animating
            )
            trailing()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Starts loading the orb HTML as soon as a window exists so the first
/// session chrome does not wait on WebKit + WebGL.
@MainActor
enum VoiceOrbPreloader {
    static func warmup() {
        Host.shared.warmup()
    }

    fileprivate static func borrow() -> (webView: WKWebView, generation: Int) {
        Host.shared.borrow()
    }

    /// Parks only if `generation` is still the latest borrow. A stale dismantle
    /// must not pull the web view off screen after a newer orb has taken it.
    fileprivate static func park(_ webView: WKWebView, generation: Int) {
        Host.shared.park(webView, generation: generation)
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
        private var generation = 0

        func warmup() {
            _ = preparedWebView()
            // Inserting into the window during its open transition throws
            // "Failed to preempt running transition" and the first frame stays black.
            DispatchQueue.main.async {
                self.attachPark()
            }
        }

        func borrow() -> (webView: WKWebView, generation: Int) {
            let webView = preparedWebView()
            webView.removeFromSuperview()
            generation += 1
            return (webView, generation)
        }

        func park(_ webView: WKWebView, generation: Int) {
            // SwiftUI can dismantle the previous representable after the next
            // one has already borrowed this view. Parking then hides the orb
            // for the rest of the take, and a reload only updates the parked copy.
            guard webView === self.webView, generation == self.generation else { return }
            webView.navigationDelegate = nil
            // Stop the page's animation loops while it sits off screen; the borrower un-parks on its first push.
            webView.evaluateJavaScript("window.orbSetParked&&window.orbSetParked(true);")
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
        let borrowed = VoiceOrbPreloader.borrow()
        context.coordinator.borrowGeneration = borrowed.generation
        let webView = borrowed.webView
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
        VoiceOrbPreloader.park(webView, generation: coordinator.borrowGeneration)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var phase: VoiceOrb.Phase = .listening
        var inputVolume = 0.0
        var outputVolume = 0.0
        var paused = false
        var borrowGeneration = 0
        private var pageReady = false
        private var lastScript: String?
        private var isReloading = false
        /// How many times this appearance has reloaded after WebGL died.
        /// A take loses the context twice: once when the shared web view is
        /// mounted for the countdown, again when the mic audio session starts.
        /// One reload left the orb blank for the rest of the round.
        private var contextLossReloads = 0
        private static let maxContextLossReloads = 3

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
            reloadOrb(in: webView, force: true)
        }

        /// Pushes the latest signal once the page is ready, in one script call.
        /// Skips identical scripts; the same call reports a lost WebGL context, and the orb
        /// reloads a few times for it, then stops so a dead canvas cannot reload forever.
        func push(to webView: WKWebView) {
            guard pageReady, !isReloading else { return }
            let script = makeScript()
            guard script != lastScript else { return }
            lastScript = script
            let wrapped = "(function(){if(window.orbContextLost){return true;}window.orbSetParked&&window.orbSetParked(false);\(script)return false;})()"
            webView.evaluateJavaScript(wrapped) { [weak self] result, _ in
                guard let self else { return }
                if result as? Bool == true, self.contextLossReloads < Self.maxContextLossReloads {
                    self.reloadOrb(in: webView, force: false)
                }
            }
        }

        private func reloadOrb(in webView: WKWebView, force: Bool) {
            guard !isReloading else { return }
            guard force || contextLossReloads < Self.maxContextLossReloads else { return }
            isReloading = true
            pageReady = false
            lastScript = nil
            if !force { contextLossReloads += 1 }
            VoiceOrbPreloader.loadOrbHTML(into: webView)
        }

        private func makeScript() -> String {
            if paused {
                // Leave the last frame in place. A new signal would move the cloud when it resumes.
                return "window.orbFrozen=true;document.documentElement.classList.add('paused');"
            }
            let input = String(format: "%.3f", inputVolume)
            let output = String(format: "%.3f", outputVolume)
            let state = phase.webState
            return """
            window.orbFrozen=false;\
            document.documentElement.classList.remove('paused');\
            document.documentElement.dataset.orbState='\(state)';\
            window.orbSetSignal&&window.orbSetSignal('\(state)',\(input),\(output));
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

