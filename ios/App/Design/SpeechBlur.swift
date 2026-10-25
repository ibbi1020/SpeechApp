import SwiftUI
import SpeechAppKit

/// Blur as the transition, rather than slide or scale.
///
/// FocusFlight changes screens by blurring what is leaving up out of focus while
/// what is arriving resolves down into it. Nothing travels. Measurements and the
/// reasoning behind each depth live on `BlurMotion`.
///
/// Three moves, and picking the right one matters more than the numbers:
///
/// - `blurDissolve` — one surface replaced by another. Both ends blur.
/// - `blurBurst` — a control leaving with nothing taking its place. Harder, faster.
/// - `blurBackdrop` — content pushed behind a modal. Stays blurred while it is back there.
enum SpeechBlur {
    /// Content arriving out of focus and leaving back into it.
    static var dissolve: AnyTransition {
        veil(radius: BlurMotion.dissolveRadius)
    }

    /// A control dismissed. Blurs harder and is gone sooner, so the eye releases it
    /// instead of tracking it out.
    static var burst: AnyTransition {
        veil(radius: BlurMotion.burstRadius)
    }

    /// Arriving content resolves at dissolve depth; leaving content bursts. Use when
    /// a surface is replaced by one that is not its peer — a step by a modal, say.
    static var enterSoftLeaveHard: AnyTransition {
        .asymmetric(insertion: dissolve, removal: burst)
    }

    /// Settle curve for a dissolve. The measured ramp was a smooth S with no
    /// overshoot; a bouncing blur reads as a focus hunt.
    static var motion: Animation { .easeInOut(duration: BlurMotion.dissolve) }
    static var burstMotion: Animation { .easeInOut(duration: BlurMotion.burst) }
    static var reducedMotion: Animation { .easeOut(duration: BlurMotion.reducedFade) }

    static func motion(reduceMotion: Bool) -> Animation {
        reduceMotion ? reducedMotion : motion
    }

    private static func veil(radius: CGFloat) -> AnyTransition {
        .modifier(
            active: BlurVeil(radius: radius, opacity: 0),
            identity: BlurVeil(radius: 0, opacity: 1)
        )
    }
}

/// Blur and opacity together. Reads Reduce Motion itself so every transition built
/// from it degrades the same way, rather than each caller remembering to check.
private struct BlurVeil: ViewModifier {
    var radius: CGFloat
    var opacity: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .blur(radius: reduceMotion ? 0 : radius)
            .opacity(opacity)
    }
}

// MARK: - Text and content that changes in place

/// Content that dissolves through blur when its value changes.
///
/// Only one value is ever on screen. Cross-fading two strings in a `ZStack` would
/// size the container to the taller of them, so a two-line heading replacing a
/// one-line heading would leave a gap below it for the whole transition — and the
/// whole point of this move is that nothing shifts.
///
/// So the old value blurs out, then the new one resolves in. Split just under half
/// and just over, which lands on the 290ms the reference header took end to end.
struct BlurDissolve<Value: Equatable, Content: View>: View {
    let value: Value
    var radius: CGFloat = BlurMotion.dissolveRadius
    @ViewBuilder var content: (Value) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Value?
    @State private var phase: BlurPhase = .sharp
    @State private var generation = 0

    private static var outShare: Double { 0.45 }

    private var outDuration: TimeInterval {
        (reduceMotion ? BlurMotion.reducedFade : BlurMotion.dissolve) * Self.outShare
    }

    private var inDuration: TimeInterval {
        (reduceMotion ? BlurMotion.reducedFade : BlurMotion.dissolve) * (1 - Self.outShare)
    }

    var body: some View {
        content(shown ?? value)
            .blur(radius: phase.radius)
            .opacity(phase.opacity)
            .onAppear { shown = value }
            .onChange(of: value) { _, next in
                dissolve(to: next)
            }
    }

    private func dissolve(to next: Value) {
        generation += 1
        let gate = generation
        let gone = BlurPhase.dissolved(radius: radius, reduceMotion: reduceMotion)

        withAnimation(.easeIn(duration: outDuration)) {
            phase = gone
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(outDuration))
            guard gate == generation else { return }
            // Swap underneath the blur, unanimated, so the new value is never seen
            // sharp in the old one's place.
            var swap = Transaction()
            swap.disablesAnimations = true
            withTransaction(swap) {
                shown = next
                phase = gone
            }
            withAnimation(.easeOut(duration: inDuration)) {
                phase = .sharp
            }
        }
    }
}

extension BlurDissolve where Value == String {
    /// A line of copy that dissolves when it changes. Blur scales with the type size,
    /// because a radius that erases a caption leaves a headline readable.
    init(
        _ text: String,
        size: CGFloat,
        @ViewBuilder content: @escaping (String) -> Content
    ) {
        self.value = text
        self.radius = BlurMotion.textRadius(forSize: size)
        self.content = content
    }
}

// MARK: - Modal depth

/// Pushes content behind something else: blurred, and dimmed by a scrim.
///
/// The blur alone will not darken — a Gaussian preserves mean brightness — so
/// without the scrim the background stays just as bright and competes with the panel.
/// Reduce Transparency gets no blur, so its scrim carries the whole separation.
private struct BlurBackdrop: ViewModifier {
    var isActive: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var radius: CGFloat {
        isActive && !reduceTransparency ? BlurMotion.backdropRadius : 0
    }

    private var dim: Double {
        guard isActive else { return 0 }
        return reduceTransparency ? BlurMotion.opaqueBackdropDim : BlurMotion.backdropDim
    }

    func body(content: Content) -> some View {
        content
            .blur(radius: radius)
            .overlay {
                Color.black
                    .opacity(dim)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .animation(
                reduceMotion
                    ? SpeechBlur.reducedMotion
                    : .easeInOut(duration: BlurMotion.backdrop),
                value: isActive
            )
    }
}

extension View {
    /// Blur and dim this content while something sits in front of it.
    func blurBackdrop(_ isActive: Bool) -> some View {
        modifier(BlurBackdrop(isActive: isActive))
    }

    /// Resolve into focus on arrival and dissolve back out on departure.
    func blurDissolveTransition() -> some View {
        transition(SpeechBlur.dissolve)
    }

    /// Rolls the digits that changed. SwiftUI's `numericText` is the system
    /// digit move: each changed glyph blurs and travels, and the rest stay put.
    /// A line dissolve would blur the whole number at once.
    ///
    /// `countsDown` aims the travel. A countdown passes `true` so the old digit
    /// climbs off the top, the same direction as the take clock. A count-up
    /// passes `false`, and the digit climbs as the number grows.
    /// Reduce Motion fades. A blur ramp is the motion that setting exists to avoid.
    func digitRoll<Value: Equatable>(
        _ value: Value,
        countsDown: Bool,
        reduceMotion: Bool
    ) -> some View {
        modifier(DigitRoll(value: value, countsDown: countsDown, reduceMotion: reduceMotion))
    }
}

// MARK: - Pause veil

extension View {
    /// Blur this exercise and lay a rising gray wash over it while it is paused.
    ///
    /// The blur and the wash run together. The pause mark fades in only after both
    /// have finished. The wash does not take taps.
    ///
    /// Put bars and buttons on *after* this modifier. Blur wraps the view it is
    /// applied to, so chrome added afterwards stays sharp and receives the taps.
    func pauseVeil(_ isPaused: Bool) -> some View {
        modifier(PauseVeil(isPaused: isPaused))
    }
}

/// Exercise content pushed back for pause: blurred, then covered by a wash that
/// climbs from the bottom. The mark is a separate step so it does not appear
/// while the wash is still moving.
private struct PauseVeil: ViewModifier {
    var isPaused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var veil: CGFloat = 0
    @State private var showsMark = false
    @State private var generation = 0

    private var blurRadius: CGFloat {
        guard !reduceMotion, !reduceTransparency else { return 0 }
        return veil * PauseVeilMotion.blurRadius
    }

    private var veilAnimation: Animation {
        .easeOut(duration: reduceMotion ? BlurMotion.reducedFade : PauseVeilMotion.veil)
    }

    private var markAnimation: Animation {
        .easeOut(duration: reduceMotion ? BlurMotion.reducedFade : PauseVeilMotion.mark)
    }

    func body(content: Content) -> some View {
        content
            .blur(radius: blurRadius)
            .overlay {
                ZStack {
                    PauseWash(
                        progress: veil,
                        reduceMotion: reduceMotion,
                        bottomOpacity: reduceTransparency
                            ? PauseVeilMotion.opaqueWashOpacity
                            : PauseVeilMotion.washOpacity
                    )
                    if showsMark {
                        PauseMark()
                            .transition(.opacity)
                    }
                }
                .allowsHitTesting(false)
            }
            // Tied to `veil` and `showsMark`, not the exercise phase. A spring on
            // the screen would otherwise climb the wash on the phase's curve and
            // bring the mark in at the same time.
            .animation(veilAnimation, value: veil)
            .animation(markAnimation, value: showsMark)
            .onAppear { settle(isPaused, animated: false) }
            .onChange(of: isPaused) { _, paused in
                settle(paused, animated: true)
            }
    }

    /// `animated` is false when the screen appears already paused, so a rotation
    /// does not replay the climb.
    private func settle(_ paused: Bool, animated: Bool) {
        generation += 1
        let gate = generation

        guard animated else {
            var snap = Transaction()
            snap.disablesAnimations = true
            withTransaction(snap) {
                veil = paused ? 1 : 0
                showsMark = paused
            }
            return
        }

        if paused {
            withAnimation(veilAnimation) {
                veil = 1
            } completion: {
                guard gate == generation else { return }
                withAnimation(markAnimation) {
                    showsMark = true
                }
            }
        } else if showsMark {
            withAnimation(markAnimation) {
                showsMark = false
            } completion: {
                guard gate == generation else { return }
                withAnimation(veilAnimation) {
                    veil = 0
                }
            }
        } else {
            withAnimation(veilAnimation) {
                veil = 0
            }
        }
    }
}

/// Gray wash, clear at its top edge and darkest at the bottom of the screen.
///
/// The gradient is always drawn at full height. What changes is a soft mask that
/// uncovers it from the bottom. Growing the gradient's own frame squishes the
/// fade into a thin strip, so the body reads as a slab until the last moment.
/// Reduce Motion fades the full wash in place. The climb is the motion that
/// setting exists to avoid.
private struct PauseWash: View {
    var progress: CGFloat
    var reduceMotion: Bool
    var bottomOpacity: Double

    var body: some View {
        let pigment = Color(white: PauseVeilMotion.washWhite)
        let revealProgress = reduceMotion ? 1 : progress
        GeometryReader { geo in
            let reach = geo.size.height * PauseVeilMotion.reach
            LinearGradient(
                stops: PauseVeilMotion.stops(bottomOpacity: bottomOpacity).map { stop in
                    Gradient.Stop(color: pigment.opacity(stop.opacity), location: stop.location)
                },
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: reach)
            .mask {
                LinearGradient(
                    stops: PauseVeilMotion.revealStops(progress: revealProgress).map { stop in
                        Gradient.Stop(color: .white.opacity(stop.opacity), location: stop.location)
                    },
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .opacity(reduceMotion ? progress : 1)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// White filled pause glyph, with a gray word under it. Both sit in the center.
private struct PauseMark: View {
    @ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 60

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "pause.fill")
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(.white)
                .accessibilityHidden(true)
            Text("Paused")
                .font(.title3.weight(.medium))
                .foregroundStyle(Color(white: PauseVeilMotion.labelWhite))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Paused")
    }
}

/// The roll has to be a modifier so the animation is attached to the text
/// whose value changed. Putting it on a parent animates the wrong thing.
private struct DigitRoll<Value: Equatable>: ViewModifier {
    var value: Value
    var countsDown: Bool
    var reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .opacity : .numericText(countsDown: countsDown))
            .animation(
                reduceMotion ? SpeechBlur.reducedMotion : SpeechMotion.settle,
                value: value
            )
    }
}
