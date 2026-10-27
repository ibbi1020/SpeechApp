import SwiftUI
import SpeechAppKit

/// Home, and the ceremony that begins from it. The ceremony is a second state of
/// this same root, not a pushed screen, so the session stack still hangs off here.
struct EntryFlowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progressLift: CGFloat = 0
    @State private var galleryLift: CGFloat = 0

    private var motion: Animation {
        SpeechBlur.motion(reduceMotion: reduceMotion)
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
                    Spacer(minLength: SpeechSpacing.section)
                    Button {
                        model.beginCeremony()
                    } label: {
                        Text("Begin")
                    }
                    .buttonStyle(SpeechStartButtonStyle())
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
                .offset(y: -top)
                .zIndex(progressLift > 0.62 ? 2 : 0)

                GallerySheet(
                    topInset: top,
                    bottomInset: bottom,
                    containerHeight: geo.size.height + top + bottom,
                    lift: $galleryLift,
                    otherLift: progressLift,
                    startOpen: model.presentGallery
                )
                .frame(width: geo.size.width, height: geo.size.height + top + bottom)
                .offset(y: -top)
                .zIndex(1)
                .opacity(progressLift > 0.62 ? 0 : 1)
                .allowsHitTesting(progressLift <= 0.62)
            }
        }
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
