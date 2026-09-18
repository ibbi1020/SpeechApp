import SwiftUI
import SpeechAppKit

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                switch model.route {
                case .consent:
                    ConsentView()
                case .availability:
                    AvailabilitySpikeView()
                case .library:
                    PassageLibraryView()
                case .reading:
                    if let passage = model.currentPassage {
                        ReadingSessionView(passage: passage)
                    } else {
                        ContentUnavailableView(
                            "No passages",
                            systemImage: "text.book.closed",
                            description: Text("The catalog didn’t load.")
                        )
                    }
                case .report(let report):
                    SessionReportView(report: report)
                }
            }
            .animation(SpeechMotion.settle, value: routeIdentity)
        }
        .tint(.accentColor)
    }

    private var routeIdentity: String {
        switch model.route {
        case .consent: return "consent"
        case .availability: return "availability"
        case .library: return "library"
        case .reading: return "reading"
        case .report: return "report"
        }
    }
}
