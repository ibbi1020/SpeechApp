import SwiftUI
import SpeechAppKit

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            HomeView()
                .navigationDestination(isPresented: libraryPresented) {
                    PassageLibraryView()
                        .navigationDestination(isPresented: sessionPresented) {
                            sessionDestination
                        }
                }
                .navigationDestination(isPresented: conversationPresented) {
                    ConversationSessionView()
                }
        }
        .tint(.accentColor)
        .preferredColorScheme(.dark)
    }

    private var libraryPresented: Binding<Bool> {
        Binding(
            get: {
                switch model.route {
                case .library, .reading, .report: true
                default: false
                }
            },
            set: { presented in
                if !presented {
                    switch model.route {
                    case .library, .reading, .report:
                        model.goHome()
                    default:
                        break
                    }
                }
            }
        )
    }

    private var sessionPresented: Binding<Bool> {
        Binding(
            get: {
                switch model.route {
                case .reading, .report: true
                default: false
                }
            },
            set: { presented in
                if !presented {
                    switch model.route {
                    case .reading, .report:
                        model.chooseAnotherPassage()
                    default:
                        break
                    }
                }
            }
        )
    }

    private var conversationPresented: Binding<Bool> {
        Binding(
            get: { model.route == .conversation },
            set: { presented in
                if !presented, model.route == .conversation {
                    model.goHome()
                }
            }
        )
    }

    @ViewBuilder
    private var sessionDestination: some View {
        switch model.route {
        case .report(let report):
            SessionReportView(report: report)
        default:
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
