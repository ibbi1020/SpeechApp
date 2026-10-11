import SwiftUI
import SpeechAppKit

/// Home and the format chooser are both pre-session surfaces, so they share one
/// navigation root. Every existing push path hangs off this view unchanged.
struct EntryFlowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if model.isChoosingFormat {
                FormatChooserView()
                    .transition(.opacity)
            } else {
                HomeView()
                    .transition(.opacity)
            }
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle,
            value: model.isChoosingFormat
        )
    }
}
