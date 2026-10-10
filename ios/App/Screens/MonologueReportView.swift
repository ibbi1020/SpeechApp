import SwiftUI
import SpeechAppKit

struct MonologueReportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let report: MonologueReport
    let regimenID: UUID?

    @State private var manifest: RecordingManifest?
    @State private var isLoadingManifest = false

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

                    if RecordingsService.keepRecordings {
                        Group {
                            if let manifest {
                                TakeReviewSection(manifest: manifest, saveError: manifest.saveError)
                            } else if isLoadingManifest {
                                TakeReviewSection(
                                    manifest: RecordingManifest(
                                        id: regimenID ?? UUID(),
                                        topic: "",
                                        reportLines: [],
                                        comparison: "",
                                        takes: []
                                    ),
                                    saveError: nil
                                )
                            }
                        }
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
        .speechPageTitle("Your talk")
        .speechBottomBlur()
        .task(id: regimenID) {
            await loadManifest()
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

    private func loadManifest() async {
        guard let regimenID else { return }
        isLoadingManifest = true
        // Brief retry — the last take may still be writing.
        for _ in 0..<20 {
            if let loaded = try? RecordingsService.store.load(id: regimenID) {
                manifest = loaded
                isLoadingManifest = false
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        isLoadingManifest = false
    }

    private func goHome() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
            model.goHome()
        }
    }
}
