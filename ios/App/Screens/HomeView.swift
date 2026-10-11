import SwiftUI
import SpeechAppKit

/// One figure, two words, one verb. The format choice comes after the commitment,
/// not before it.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 0 is the coarse plate, 1 the fine one. The hold resolves it.
    @State private var resolve: Double = 0

    var body: some View {
        ZStack {
            DitherPlate(
                name: "PlateHome",
                coarseName: reduceMotion ? nil : "PlateHomeCoarse",
                resolve: reduceMotion ? 1 : resolve
            )
            DitherPlateScrim()

            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: SpeechSpacing.section)
                HoldToBeginButton(
                    title: "Begin",
                    onHoldChange: resolvePlate,
                    onComplete: model.chooseFormat
                )
            }
            .padding(.horizontal, SpeechSpacing.page)
            .padding(.top, SpeechSpacing.related)
            .padding(.bottom, SpeechSpacing.page)
        }
        .navigationTitle(EntryGreeting.kicker)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { resolve = 0 }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: SpeechSpacing.cluster) {
                Text(EntryGreeting.kicker)
                    .speechType(.label)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text(EntryGreeting.line(hasBegunBefore: model.hasBegunBefore))
                    .speechType(.h1)
                    .foregroundStyle(.primary)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: SpeechSpacing.related)

            Button {
                model.openRecordings()
            } label: {
                Image(systemName: "waveform")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Your recordings")
        }
    }

    private func resolvePlate(_ holding: Bool) {
        guard !reduceMotion else { return }
        withAnimation(
            holding
                ? .linear(duration: HoldToBegin.defaultDuration)
                : SpeechMotion.settle
        ) {
            resolve = holding ? 1 : 0
        }
    }
}
