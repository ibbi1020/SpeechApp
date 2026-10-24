import SwiftUI
import SpeechAppKit

struct ConversationReportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let report: ConversationReport
    var recordingID: UUID? = nil

    @State private var offersSave = false
    @State private var keptThisTake = false

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
        }
        .speechPageTitle("Your conversation")
        .onAppear {
            offersSave = recordingID != nil && !RecordingsService.keepRecordings
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
            RecordingReviewLoader(recordingID: recordingID)
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

    private func goHome() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
            model.goHome()
        }
    }
}
