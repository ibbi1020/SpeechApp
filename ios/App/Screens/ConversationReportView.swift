import SwiftUI
import SpeechAppKit

struct ConversationReportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let report: ConversationReport

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

                    if let logPath = report.captionSyncLogPath {
                        captionSyncSection(path: logPath)
                            .padding(.top, SpeechSpacing.section)
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
        .speechPageTitle("Your conversation")
        .speechBottomBlur()
    }

    private var linesCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(report.lines, id: \.label) { line in
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

    @ViewBuilder
    private func captionSyncSection(path: String) -> some View {
        let url = URL(fileURLWithPath: path)
        VStack(alignment: .leading, spacing: 12) {
            Text("Diagnostics")
                .speechType(.label)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Caption sync log from this conversation. Share it if partner subtitles lagged or stuck.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if FileManager.default.fileExists(atPath: path) {
                        ShareLink(item: url) {
                            Text("Share caption sync log")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(SpeechSecondaryButtonStyle())
                    } else {
                        Text("Log file missing.")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("Caption sync log")
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            .tint(.secondary)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }

    private func goHome() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
            model.goHome()
        }
    }
}
