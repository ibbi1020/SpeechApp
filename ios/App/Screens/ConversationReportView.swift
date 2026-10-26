import SwiftUI
import SpeechAppKit

struct ConversationReportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let report: ConversationReport
    var recordingID: UUID? = nil

    @State private var offersSave = false
    @State private var keptThisTake = false
    @State private var showCeremony = false
    @State private var didCelebrate = false
    @State private var ceremonyBlur: CGFloat = 0

    var body: some View {
        ZStack {
            SpeechScreenBackground()

            FeedbackPageScroll {
                feedback
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } actions: {
                actions
            }
            .id(report.id)
            .blur(radius: ceremonyBlur)
            .accessibilityHidden(showCeremony)

            if showCeremony {
                PerfectTakeCeremony(contentBlur: $ceremonyBlur) {
                    showCeremony = false
                }
            }
        }
        .speechPageTitle("Your conversation")
        .onAppear {
            offersSave = recordingID != nil && !RecordingsService.keepRecordings
        }
        .onChange(of: recordingID) { _, _ in
            didCelebrate = false
            showCeremony = false
            ceremonyBlur = 0
        }
        .onDisappear {
            guard offersSave, !keptThisTake, let recordingID else { return }
            if case .conversationReport = model.route { return }
            TakeRetention.discard(recordingID)
        }
    }

    @ViewBuilder
    private var feedback: some View {
        if let recordingID {
            RecordingReviewLoader(
                recordingID: recordingID,
                stats: FeedbackStatRows.conversation(report),
                showsPerfectLine: report.kind == .full,
                celebratesCleanTake: report.kind == .full,
                onCleanTake: beginCeremony
            )
        } else {
            FeedbackPreparing(message: "This take didn't come through.")
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button("Back to home", action: goHome)
                .buttonStyle(SpeechPrimaryButtonStyle())

            if offersSave, let recordingID {
                SaveThisTakeButton(recordingID: recordingID, kept: $keptThisTake)
            }
        }
    }

    private func beginCeremony() {
        guard !didCelebrate else { return }
        didCelebrate = true
        showCeremony = true
    }

    private func goHome() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
            model.goHome()
        }
    }
}
