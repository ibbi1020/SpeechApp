import SwiftUI
import SpeechAppKit

struct SessionReportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let report: SessionReport

    var body: some View {
        ZStack {
            SpeechScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    occupancyGrid
                    deliveryCard
                    analysisCard
                    if !report.contrastFocus.isEmpty {
                        focusCard
                    }
                    if !notableWords.isEmpty {
                        wordsCard
                    }
                    if let logPath = report.diagnosticsLogPath {
                        diagnosticsShareCard(path: logPath)
                    }
                    VStack(spacing: 12) {
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
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
        }
        .navigationTitle("Your reading")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func diagnosticsShareCard(path: String) -> some View {
        let url = URL(fileURLWithPath: path)
        VStack(alignment: .leading, spacing: 10) {
            Label("Session diagnostics", systemImage: "waveform.path.ecg")
                .font(.headline)
            Text("Caret lag log from this reading. Share it to debug freeze / catch-up.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if FileManager.default.fileExists(atPath: path) {
                ShareLink(item: url) {
                    Text("Share session log")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(SpeechSecondaryButtonStyle())
            } else {
                Text("Log file missing at \(path)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(report.passageTitle)
                .font(.title2.weight(.bold))
                .tracking(-0.3)
            Text("\(report.passageLength.capitalized) · \(report.scriptWordCount) words · \(Int(report.durationSeconds))s")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var occupancyGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            SpeechMetricCard(title: "Matched", value: "\(report.matchCount)")
            SpeechMetricCard(title: "Skipped", value: "\(report.skipCount)")
            SpeechMetricCard(title: "Extra words", value: "\(report.extraCount)")
            SpeechMetricCard(title: "Swapped", value: "\(report.substituteCount)")
        }
    }

    private var deliveryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How the reading went")
                .font(.headline)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.0f%%", report.completenessRatio * 100))
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("of the script occupied")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.0f", report.speechRateSyllablesPerMinute))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text("syllables / min")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let average = report.averageSpeechRateSyllablesPerMinute {
                Text(String(format: "Your recent average: %.0f", average))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if report.stallEventCount > 0 {
                Text("Paused \(report.stallEventCount)× for a longer silence — that’s fine.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text("Speed is a note, not a goal.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private var analysisCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("What we analyzed", systemImage: "waveform")
                .font(.headline)
            Text(report.followAlongNote)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(report.gopNote)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if report.pcmCapturedSeconds > 0.2 {
                Text(String(format: "Audio held for analysis: %.1fs (then discarded).", report.pcmCapturedSeconds))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private var focusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This passage practiced")
                .font(.headline)
            Text(report.contrastFocus.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private var notableWords: [WordAnalysis] {
        report.wordAnalyses.filter { $0.occupancy == "skipped" || $0.occupancy == "swapped" }
    }

    private var wordsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Words that stood out")
                .font(.headline)
            ForEach(notableWords.prefix(12)) { word in
                VStack(alignment: .leading, spacing: 2) {
                    Text(word.surface)
                        .font(.subheadline.weight(.semibold))
                    Text("\(word.occupancy) · sounds \(word.canonicalPhones.joined(separator: " ")) · \(word.soundAssessment)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                )
            }
        }
    }
}
