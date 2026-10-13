import SwiftUI
import SpeechAppKit

/// Home, and the ceremony that begins from it. The ceremony is a second state of
/// this same root, not a pushed screen, so the session stack still hangs off here.
struct EntryFlowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motion: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.swap
    }

    var body: some View {
        Group {
            if model.isInCeremony {
                CeremonyScaffold()
                    .transition(.opacity)
            } else {
                home
                    .transition(.opacity)
            }
        }
        .animation(motion, value: model.isInCeremony)
        .navigationTitle(EntryGreeting.appName)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var home: some View {
        ZStack {
            CeremonyPalette.background
                .ignoresSafeArea()

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
            .padding(.bottom, SpeechSpacing.page)
        }
    }

    private var homeHeader: some View {
        HStack(alignment: .top) {
            Text(EntryGreeting.line(hasBegunBefore: model.hasBegunBefore))
                .speechType(.h1)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: SpeechSpacing.related)

            GlassCircleButton(systemName: "waveform", label: "Your recordings") {
                model.openRecordings()
            }
        }
    }
}
