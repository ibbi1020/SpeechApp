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
                    conversationDestination
                }
                .navigationDestination(isPresented: monologuePresented) {
                    monologueDestination
                }
                .navigationDestination(isPresented: recordingsPresented) {
                    if case .recordings(let filter) = model.route {
                        RecordingsLibraryView(filter: filter)
                    } else {
                        RecordingsLibraryView(filter: nil)
                    }
                }
        }
        .tint(.accentColor)
        .preferredColorScheme(.dark)
    }

    private var recordingsPresented: Binding<Bool> {
        Binding(
            get: {
                if case .recordings = model.route { return true }
                return false
            },
            set: { if !$0, case .recordings = model.route { model.goHome() } }
        )
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
            get: { isOnConversationStack },
            set: { if !$0, isOnConversationStack { model.goHome() } }
        )
    }

    private var monologuePresented: Binding<Bool> {
        Binding(
            get: { isOnMonologueStack },
            set: { if !$0, isOnMonologueStack { model.goHome() } }
        )
    }

    private var isOnConversationStack: Bool {
        switch model.route {
        case .conversation, .conversationReport:
            true
        case .crisis:
            model.hostedFormat == .conversation
        default:
            false
        }
    }

    private var isOnMonologueStack: Bool {
        switch model.route {
        case .monologue, .monologueReport:
            true
        case .crisis:
            model.hostedFormat == .monologue
        default:
            false
        }
    }

    @ViewBuilder
    private var monologueDestination: some View {
        switch model.route {
        case .crisis where model.hostedFormat == .monologue:
            CrisisReferralView()
        case .monologueReport(let report, let regimenID):
            MonologueReportView(report: report, regimenID: regimenID)
        default:
            MonologueSessionView()
        }
    }

    @ViewBuilder
    private var conversationDestination: some View {
        switch model.route {
        case .conversationReport(let report, let recordingID):
            ConversationReportView(report: report, recordingID: recordingID)
        case .crisis where model.hostedFormat == .conversation:
            CrisisReferralView()
        default:
            ConversationSessionView()
        }
    }

    @ViewBuilder
    private var sessionDestination: some View {
        switch model.route {
        case .report(let report, let recordingID):
            SessionReportView(report: report, recordingID: recordingID)
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
