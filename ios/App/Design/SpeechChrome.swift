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
    /// One surface or piece of copy replacing another. Measured off FocusFlight, whose
    /// screen changes land in about a quarter second.
    static let swap = Animation.spring(duration: 0.25, bounce: 0)
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

/// Keeps the edge swipe after the navigation bar is hidden.
///
/// Hiding the bar also hides the system back button, and the navigation
/// controller then refuses the swipe. Home and the ceremony use a solid
/// circle back control instead, so the swipe has to be turned back on by hand.
struct SpeechEdgeSwipe: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.claim()
    }

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        private weak var claimed: UIGestureRecognizer?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        override func viewIsAppearing(_ animated: Bool) {
            super.viewIsAppearing(animated)
            claim()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            guard isMovingFromParent || isBeingDismissed else { return }
            claimed?.delegate = nil
            claimed = nil
        }

        func claim() {
            guard let gesture = navigationController?.interactivePopGestureRecognizer else { return }
            let canPop = (navigationController?.viewControllers.count ?? 0) > 1
            if claimed !== gesture {
                gesture.delegate = self
                claimed = gesture
            }
            gesture.isEnabled = canPop
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
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
            .modifier(SpeechWideCapsule(
                isEnabled: isEnabled,
                isPressed: configuration.isPressed,
                fill: .white,
                foreground: .black
            ))
    }
}

struct SpeechPrimaryButtonStyle: ButtonStyle {
    var tint: Color = .accentColor
    var isDestructive: Bool = false
    /// Solid accent capsule and a white label. Off for the plain white capsule.
    var showsTint: Bool = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(SpeechWideCapsule(
                isEnabled: isEnabled,
                isPressed: configuration.isPressed,
                fill: enabledFill,
                foreground: enabledForeground
            ))
    }

    /// Destructive keeps the white capsule and a red label, including when
    /// `showsTint` is also set. A tint without that flag is the accent fill.
    private var enabledFill: Color {
        if isDestructive || !showsTint { return .white }
        return tint
    }

    private var enabledForeground: Color {
        if isDestructive { return .red }
        if showsTint { return .white }
        return .black
    }
}

struct SpeechSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(SpeechWideCapsule(
                isEnabled: isEnabled,
                isPressed: configuration.isPressed,
                fill: .white,
                foreground: .black
            ))
    }
}

/// The wide capsule shared by start, primary, and secondary.
private struct SpeechWideCapsule: ViewModifier {
    var isEnabled: Bool
    var isPressed: Bool
    var fill: Color
    var foreground: Color

    func body(content: Content) -> some View {
        content
            .font(.system(size: SpeechStartMetrics.labelSize, weight: .medium))
            // Disabled dims the fill rather than the whole button. Fading the button
            // to 45% let whatever sat behind it show straight through the capsule.
            .foregroundStyle(isEnabled ? foreground : Color(white: 0.26))
            .frame(maxWidth: .infinity)
            .frame(height: SpeechStartMetrics.height)
            .background(isEnabled ? fill : Color(white: 0.58), in: Capsule())
            .padding(.horizontal, SpeechStartMetrics.extraInset)
            .contentShape(Capsule())
            .opacity(isEnabled && isPressed ? 0.92 : 1)
            .scaleEffect(isPressed && isEnabled ? 0.97 : 1)
            .animation(SpeechMotion.press, value: isPressed)
    }
}

/// Solid icon circle. White glyph, white fill at 12% opacity.
/// Gallery chrome is 44pt. Ceremony, voice, and background are 48pt.
/// Pause, stop, and done beside the orb stay 52pt. 44pt is the floor.
struct SpeechIconCircleStyle: ButtonStyle {
    static let gallery: CGFloat = 44
    static let standard: CGFloat = 48
    static let session: CGFloat = 52

    var diameter: CGFloat = gallery

    @Environment(\.isEnabled) private var isEnabled

    private var side: CGFloat { max(diameter, Self.gallery) }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.white)
            .frame(width: side, height: side)
            .background(Color.white.opacity(0.12), in: Circle())
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1)
            .animation(SpeechMotion.press, value: configuration.isPressed)
    }
}

/// A navigation-bar icon. Same solid circle as the other icon buttons.
struct SpeechBarButton: View {
    var systemName: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(SpeechIconCircleStyle(diameter: SpeechIconCircleStyle.gallery))
        .accessibilityLabel(label)
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
    /// The connecting orb has already been up long enough to need a sentence.
    var showsSlowLine: Bool = false

    /// 25% larger than the original 120pt homepage orb.
    static let box: CGFloat = 150
    /// orb-ui cloud theme draws the sphere at this fraction of `box`.
    private static let diameterRatio: CGFloat = 0.55
    /// Clear space between each circle button and the drawn sphere.
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
        case .connecting:
            if showsSlowLine {
                return "Connecting. \(ConnectionWaitPolicy.slowLine)"
            }
            return "Connecting."
        case .listening: return level > 0.28 ? "Hearing you." : "Listening."
        }
    }
}

/// Live session bar: leading control, the shared orb, trailing control.
/// Reading, Conversation, and Monologue all mount this. The orb is one WebGL view.
struct SessionOrbBar<Leading: View, Trailing: View>: View {
    var phase: VoiceOrb.Phase
    /// When the connecting orb appeared. Nil once the model is up or the wait has ended.
    var connectingStarted: Date? = nil
    var inputVolume: Float = 0
    var outputVolume: Float = 0
    var animating: Bool = true
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsSlowLine = false

    private var slowLineID: String {
        guard phase == .connecting, let connectingStarted else { return "off" }
        return String(connectingStarted.timeIntervalSinceReferenceDate)
    }

    var body: some View {
        HStack(spacing: VoiceOrb.controlSpacing) {
            leading()
            VoiceOrb(
                phase: phase,
                inputVolume: inputVolume,
                outputVolume: outputVolume,
                animating: animating,
                showsSlowLine: showsSlowLine
            )
            trailing()
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) {
            Text(ConnectionWaitPolicy.slowLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, SpeechSpacing.page)
                .opacity(showsSlowLine ? 1 : 0)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
                .alignmentGuide(.top) { dimensions in
                    dimensions[.bottom] + 8
                }
                .transaction { $0.disablesAnimations = false }
                .animation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.35), value: showsSlowLine)
        }
        .task(id: slowLineID) {
            showsSlowLine = false
            guard phase == .connecting, let connectingStarted else { return }
            let elapsed = Date().timeIntervalSince(connectingStarted)
            let wait = ConnectionWaitPolicy.slowLineDelay - elapsed
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
            }
            guard !Task.isCancelled else { return }
            showsSlowLine = ConnectionWaitPolicy.showsSlowLine(
                elapsed: Date().timeIntervalSince(connectingStarted)
            )
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

        /// Pushes the latest signal once the page is ready.
        /// Skips identical scripts. Reloads a few times if WebGL reports a lost
        /// context, then stops so a dead canvas cannot reload forever.
        func push(to webView: WKWebView) {
            guard pageReady, !isReloading else { return }
            webView.evaluateJavaScript("!!window.orbContextLost") { [weak self] result, _ in
                guard let self else { return }
                let contextLost = result as? Bool == true
                if contextLost, self.contextLossReloads < Self.maxContextLossReloads {
                    self.reloadOrb(in: webView, force: false)
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

