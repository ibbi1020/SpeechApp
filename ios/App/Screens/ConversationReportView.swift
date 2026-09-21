import SwiftUI
import SpeechAppKit

struct ConversationReportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let report: ConversationReport

    private var displayLines: [ConversationReport.Line] {
        report.lines.filter { $0.label == "Time spoken" || $0.label == "Turns" }
    }

    var body: some View {
        ZStack {
            SpeechScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Your conversation")
                        .font(.system(.title2, design: .serif).weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, SpeechSpacing.section)

                    linesCard

                    if report.kind == .thin {
                        Text("Too little speech to score the rest.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, SpeechSpacing.related)
                    }

                    Button("Done", action: goHome)
                        .buttonStyle(SpeechPrimaryButtonStyle())
                        .padding(.top, SpeechSpacing.section)

                    Button("Back to home", action: goHome)
                        .buttonStyle(SpeechSecondaryButtonStyle())
                        .padding(.top, 10)
                        .padding(.bottom, 32)
                }
                .padding(.horizontal, SpeechSpacing.page)
                .padding(.top, 20)
            }
        }
        .navigationTitle("Your conversation")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var linesCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(displayLines, id: \.label) { line in
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
