import SwiftUI
import SpeechAppKit

struct SessionReportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let report: SessionReport
    var recordingID: UUID? = nil

    @State private var offersSave = false
    @State private var keptThisTake = false

    var body: some View {
        ZStack {
            SpeechScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.bottom, SpeechSpacing.section)

                    if recordingID != nil {
                        RecordingReviewLoader(recordingID: recordingID)
                    }

                    actions
                        .padding(.top, SpeechSpacing.section)
                        .padding(.bottom, 32)
                }
                .padding(.horizontal, SpeechSpacing.page)
                .padding(.top, 20)
            }
        }
        .speechPageTitle("Your reading")
        .toolbar(.visible, for: .navigationBar)
        .speechBottomBlur()
        .onAppear {
            offersSave = recordingID != nil && !RecordingsService.keepRecordings
        }
        .onDisappear {
            discardUnsavedTake(whileStill: { if case .report = model.route { true } else { false } })
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(report.passageTitle)
                .font(.title3.weight(.semibold))
            Text("\(report.scriptWordCount) words · \(durationLabel)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var durationLabel: String {
        let total = max(0, Int(report.durationSeconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button("Read this again") {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
                    model.readAgain()
                }
            }
            .buttonStyle(SpeechPrimaryButtonStyle())

            Button("Choose another passage") {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
                    model.chooseAnotherPassage()
                }
            }
            .buttonStyle(SpeechSecondaryButtonStyle())

            if offersSave, let recordingID {
                SaveThisTakeButton(recordingID: recordingID, kept: $keptThisTake)
            }
        }
    }

    private func discardUnsavedTake(whileStill stillHere: () -> Bool) {
        guard offersSave, !keptThisTake, let recordingID, !stillHere() else { return }
        TakeRetention.discard(recordingID)
    }
}
