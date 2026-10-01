import SwiftUI
import SpeechAppKit

struct MonologueReportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let report: MonologueReport

    var body: some View {
        ZStack {
            SpeechScreenBackground()

            ScrollView {
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

                    Button("Back to home", action: goHome)
                        .buttonStyle(SpeechPrimaryButtonStyle())
                        .padding(.top, SpeechSpacing.section)
                        .padding(.bottom, 32)
                }
                .padding(.horizontal, SpeechSpacing.page)
                .padding(.top, 20)
            }
        }
        .navigationTitle("Your talk")
        .navigationBarTitleDisplayMode(.inline)
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
