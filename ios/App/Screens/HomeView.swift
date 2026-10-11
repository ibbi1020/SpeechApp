import SwiftUI
import SpeechAppKit

/// One figure, one line, one verb. The format choice comes after the commitment,
/// not before it.
struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            DitherPlate(name: "PlateHome")
            DitherPlateScrim()

            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: SpeechSpacing.section)
                Button("Begin", action: model.chooseFormat)
                    .buttonStyle(SpeechStartButtonStyle())
            }
            .padding(.horizontal, SpeechSpacing.page)
            .padding(.top, SpeechSpacing.related)
            .padding(.bottom, SpeechSpacing.page)
        }
        .navigationTitle(EntryGreeting.appName)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(alignment: .top) {
            Text(EntryGreeting.line(hasBegunBefore: model.hasBegunBefore))
                .speechType(.h1)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

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
}
