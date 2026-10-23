import SwiftUI
import SpeechAppKit

struct MonologueReportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let report: MonologueReport
    let regimenID: UUID?
    var topic: String = ""
    /// The gallery keeps the profile lines. The report after a talk does not.
    var showsLines: Bool = false

    @State private var offersSave = false
    @State private var keptThisTake = false

    var body: some View {
        ZStack {
            SpeechScreenBackground()

            FeedbackPageScroll {
                if showsLines {
                    libraryContent
                } else {
                    exerciseContent
                }
            } actions: {
                actions
            }
        }
        .speechPageTitle("Your talk")
        .speechBottomBlur(bar: false)
        .onAppear {
            offersSave = !showsLines && regimenID != nil && !RecordingsService.keepRecordings
        }
        .onDisappear {
            guard offersSave, !keptThisTake, let regimenID else { return }
            if case .monologueReport = model.route { return }
            TakeRetention.discard(regimenID)
        }
    }

    private var exerciseContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !topic.isEmpty {
                Text(topic)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !report.comparison.isEmpty {
                Text(report.comparison)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, topic.isEmpty ? 0 : SpeechSpacing.related)
            }

            feedback
                .padding(.top, SpeechSpacing.section)
        }
    }

    @ViewBuilder
    private var feedback: some View {
        if let regimenID {
            RecordingReviewLoader(recordingID: regimenID)
        } else {
            FeedbackPreparing(message: "This take didn't come through.", showsSpinner: false)
        }
    }

    private var libraryContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            linesCard

            if report.kind == .thin {
                Text("Too little speech to score the rest.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, SpeechSpacing.related)
            }

            if !report.comparison.isEmpty {
                Text(report.comparison)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, SpeechSpacing.related)
            }

            if regimenID != nil {
                RecordingReviewLoader(recordingID: regimenID)
                    .padding(.top, SpeechSpacing.section)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button("Back to home", action: goHome)
                .buttonStyle(SpeechPrimaryButtonStyle())

            if offersSave, let regimenID {
                SaveThisTakeButton(recordingID: regimenID, kept: $keptThisTake)
            }
        }
    }

    private var linesCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(Array(report.lines.enumerated()), id: \.offset) { _, line in
                VStack(alignment: .leading, spacing: 4) {
                    Text(line.label)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(line.value)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func goHome() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
            model.goHome()
        }
    }
}
