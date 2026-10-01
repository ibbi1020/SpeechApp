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
        case .ageGate, .crisis:
            model.hostedFormat == .conversation
        default:
            false
        }
    }

    private var isOnMonologueStack: Bool {
        switch model.route {
        case .monologue, .monologueReport:
            true
        case .ageGate, .crisis:
            model.hostedFormat == .monologue
        default:
            false
        }
    }

    @ViewBuilder
    private var monologueDestination: some View {
        switch model.route {
        case .ageGate where model.hostedFormat == .monologue:
            AgeAttestationView()
        case .crisis where model.hostedFormat == .monologue:
            CrisisReferralView()
        case .monologueReport(let report):
            MonologueReportView(report: report)
        default:
            MonologueSessionView()
        }
    }

    @ViewBuilder
    private var conversationDestination: some View {
        switch model.route {
        case .ageGate where model.hostedFormat == .conversation:
            AgeAttestationView()
        case .conversationReport(let report):
            ConversationReportView(report: report)
        case .crisis where model.hostedFormat == .conversation:
            CrisisReferralView()
        default:
            ConversationSessionView()
        }
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
