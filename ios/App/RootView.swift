import SwiftUI
import SpeechAppKit

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            PassageLibraryView()
                .navigationDestination(isPresented: sessionPresented) {
                    sessionDestination
                }
        }
        .tint(.accentColor)
        .preferredColorScheme(.dark)
    }

    private var sessionPresented: Binding<Bool> {
        Binding(
            get: {
                switch model.route {
                case .reading, .report: true
                case .library: false
                }
            },
            set: { presented in
                if !presented {
                    model.chooseAnotherPassage()
                }
            }
        )
    }

    @ViewBuilder
    private var sessionDestination: some View {
        switch model.route {
        case .report(let report):
            SessionReportView(report: report)
        case .reading, .library:
            if let passage = model.currentPassage {
                ReadingSessionView(passage: passage)
            } else {
                ContentUnavailableView(
                    "No passages",
                    systemImage: "text.book.closed",
                    description: Text("The catalog didn’t load.")
                )
            }
        }
    }
}
