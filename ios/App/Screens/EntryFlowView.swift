import SwiftUI
import SpeechAppKit

/// Home, and the ceremony that begins from it. The ceremony is a second state of
/// this same root, not a pushed screen, so the session stack still hangs off here.
struct EntryFlowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.splashRevealed) private var splashRevealed
    @State private var progressLift: CGFloat = 0
    @State private var galleryLift: CGFloat = 0
    /// Greeting and Begin. Starts at rest so a later open never flashes hidden.
    @State private var copyOpacity = 1.0
    @State private var galleryShift: CGFloat = 0
    @State private var progressShift: CGFloat = 0
    @State private var entranceArmed = false
    /// False while the first-open entrance is moving. State jumps to the end
    /// pose as soon as the animation starts, so the clock, not the values, decides when Home can be used.
    @State private var entranceInteractive = true

    private var motion: Animation {
        SpeechBlur.motion(reduceMotion: reduceMotion)
    }

    /// First frame of a first open, before the entrance has been armed.
    /// The settled values stay in state so a later open has nothing to animate.
    private var entranceConcealed: Bool {
        model.needsHomeEntrance && !reduceMotion && !entranceArmed
    }

    private var copyOpacityShown: Double {
        entranceConcealed ? 0 : copyOpacity
    }

    private var galleryShiftShown: CGFloat {
        entranceConcealed ? galleryTravel : galleryShift
    }

    private var progressShiftShown: CGFloat {
        entranceConcealed ? progressTravel : progressShift
    }

    private var galleryTravel: CGFloat {
        HomeEntrance.travel(cardHeight: GallerySheet.peek)
    }

    private var progressTravel: CGFloat {
        HomeEntrance.travel(cardHeight: ProgressSheet.lip + GallerySheet.peek)
    }

    /// Begin and the sheets stay still until the fade, the longest of the three, has finished.
    private var homeCanBeUsed: Bool {
        !entranceConcealed && entranceInteractive
    }

    var body: some View {
        Group {
            // Home and the ceremony are the same surface in two states, so neither
            // slides. Home blurs out of focus and the ceremony resolves into it.
            if model.isInCeremony {
                CeremonyScaffold()
                    .transition(SpeechBlur.dissolve)
            } else {
                home
                    .transition(SpeechBlur.dissolve)
            }
        }
        .animation(motion, value: model.isInCeremony)
        .navigationTitle(EntryGreeting.appName)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: splashRevealed) { await beginEntranceIfNeeded() }
    }

    private var home: some View {
        // Read the insets on a reader that still sits in the safe area.
        // Ignoring safe area on the reader itself reports them as zero, and
        // then the greeting and the gallery controls land in the status bar.
        GeometryReader { geo in
            let top = geo.safeAreaInsets.top
            let bottom = geo.safeAreaInsets.bottom
            ZStack(alignment: .top) {
                CeremonyPalette.background
                    .ignoresSafeArea()

                // The sheet is taller than this column so it can cover the status bar
                // when it opens. Pin the column to the reader, or the stack grows with
                // the sheet and Begin slides down under the glass.
                VStack(alignment: .leading, spacing: 0) {
                    homeHeader
                        .opacity(copyOpacityShown)
                        .accessibilityHidden(copyOpacityShown < 0.01)
                    Spacer(minLength: SpeechSpacing.section)
                    Button {
                        model.beginCeremony()
                    } label: {
                        Text("Begin")
                    }
                    .buttonStyle(SpeechStartButtonStyle())
                    .opacity(copyOpacityShown)
                    .accessibilityHidden(copyOpacityShown < 0.01)
                    .allowsHitTesting(homeCanBeUsed)
                }
                .padding(.horizontal, SpeechSpacing.page)
                .padding(.top, SpeechSpacing.related)
                .padding(.bottom, GallerySheet.homeClearance(bottomInset: bottom) + ProgressSheet.lip)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)

                ProgressSheet(
                    topInset: top,
                    bottomInset: bottom,
                    containerHeight: geo.size.height + top + bottom,
                    lift: $progressLift,
                    otherLift: galleryLift
                )
                .frame(width: geo.size.width, height: geo.size.height + top + bottom)
                .offset(y: -top + progressShiftShown)
                .zIndex(progressLift > 0.02 ? 2 : 0)
                .allowsHitTesting(homeCanBeUsed)

                GallerySheet(
                    topInset: top,
                    bottomInset: bottom,
                    containerHeight: geo.size.height + top + bottom,
                    lift: $galleryLift,
                    otherLift: progressLift,
                    startOpen: model.presentGallery
                )
                .frame(width: geo.size.width, height: geo.size.height + top + bottom)
                .offset(y: -top + galleryShiftShown)
                .zIndex(1)
                .opacity(progressLift > 0.02 ? 0 : 1)
                .allowsHitTesting(homeCanBeUsed && progressLift <= 0.02)
            }
        }
    }

    /// Starts only once `splashRevealed` is true, which is after the mark has
    /// left the screen. The hidden pose is committed first, then the next turn
    /// animates, so the motion is not spent under the splash and the settled
    /// Home never flashes for a frame.
    /// Reduce Motion shows Home immediately and still marks the entrance played.
    private func beginEntranceIfNeeded() async {
        guard splashRevealed else { return }
        guard model.needsHomeEntrance, !entranceArmed else { return }
        if reduceMotion {
            model.noteHomeEntrancePlayed()
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            copyOpacity = 0
            galleryShift = galleryTravel
            progressShift = progressTravel
        }

        await Task.yield()
        guard !Task.isCancelled, splashRevealed, !entranceArmed else { return }

        entranceArmed = true
        entranceInteractive = false
        model.noteHomeEntrancePlayed()
        // Separate transactions so the fade and the two slides keep their own curves.
        withAnimation(HomeEntranceMotion.fade) {
            copyOpacity = 1
        }
        withAnimation(HomeEntranceMotion.gallery) {
            galleryShift = 0
        }
        withAnimation(HomeEntranceMotion.progress) {
            progressShift = 0
        }

        try? await Task.sleep(for: .seconds(HomeEntrance.fadeDuration))
        guard !Task.isCancelled else { return }
        entranceInteractive = true
    }

    private var homeHeader: some View {
        HomeGreetingTitle(line: EntryGreeting.line(hasBegunBefore: model.hasBegunBefore))
    }
}

/// Home title. Same size, weight, tracking, and line height as h1, in New York.
///
/// One line when it fits. When it does not, only the last word drops, so
/// "Speak with poise" becomes "Speak with" over "poise".
private struct HomeGreetingTitle: View {
    var line: String

    @ScaledMetric(relativeTo: SpeechType.metrics(.h1).relativeTo)
    private var size = SpeechType.metrics(.h1).size

    var body: some View {
        ViewThatFits(in: .horizontal) {
            title(line)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
            title(lastWordOnNextLine)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
    }

    /// "Speak with poise" → "Speak with\npoise".
    private var lastWordOnNextLine: String {
        guard let space = line.lastIndex(of: " ") else { return line }
        var text = line
        text.replaceSubrange(space...space, with: "\n")
        return text
    }

    private func title(_ text: String) -> some View {
        let metrics = SpeechType.metrics(.h1)
        let face = SpeechReading.uiFont(size: size, weight: .semibold)
        let leading = max(0, size * metrics.lineHeight - face.lineHeight)
        return Text(text)
            .font(SpeechReading.font(size: size, weight: metrics.systemWeight))
            .tracking(size * metrics.trackingEm)
            .lineSpacing(leading)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .accessibilityLabel(line)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Timing curves for the first-open Home entrance. Durations live on `HomeEntrance`.
private enum HomeEntranceMotion {
    static var fade: Animation {
        curve(HomeEntrance.fadeCurve, duration: HomeEntrance.fadeDuration)
    }

    static var gallery: Animation {
        curve(HomeEntrance.slideCurve, duration: HomeEntrance.galleryDuration)
    }

    static var progress: Animation {
        curve(HomeEntrance.slideCurve, duration: HomeEntrance.progressDuration)
    }

    private static func curve(_ curve: HomeEntrance.Curve, duration: TimeInterval) -> Animation {
        .timingCurve(curve.x1, curve.y1, curve.x2, curve.y2, duration: duration)
    }
}
