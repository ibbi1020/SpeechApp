import SwiftUI
import SpeechAppKit

struct SessionReportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let report: SessionReport

    @State private var showAllWords = false
    @State private var expandedWordIDs: Set<String> = []

    private let wordPreviewCount = 3

    var body: some View {
        ZStack {
            SpeechScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.bottom, SpeechSpacing.section)

                    resultsSection

                    notesSection
                        .padding(.top, SpeechSpacing.section)

                    if !notableWords.isEmpty {
                        wordsSection
                            .padding(.top, SpeechSpacing.section)
                    }

                    if let logPath = report.diagnosticsLogPath {
                        diagnosticsSection(path: logPath)
                            .padding(.top, SpeechSpacing.section)
                    }

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
                    }
                    .padding(.top, SpeechSpacing.section)
                    .padding(.bottom, 32)
                }
                .padding(.horizontal, SpeechSpacing.page)
                .padding(.top, 20)
            }
        }
        .navigationTitle("Your reading")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(report.passageTitle)
                .font(.system(.title2, design: .serif).weight(.semibold))
            Text("\(report.scriptWordCount) words · \(durationLabel)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var durationLabel: String {
        let minutes = max(1, Int((report.durationSeconds / 60.0).rounded()))
        return "~\(minutes) min"
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("This reading")

            VStack(alignment: .leading, spacing: 20) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    metric(title: "Matched", value: "\(report.matchCount)")
                    metric(title: "Skipped", value: "\(report.skipCount)")
                    metric(title: "Extra", value: "\(report.extraCount)")
                    metric(title: "Swapped", value: "\(report.substituteCount)")
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String(format: "%.0f%%", report.completenessRatio * 100))
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("followed along")
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
                        Text(String(format: "Recent average %.0f", average))
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }

                    if report.stallEventCount > 0 {
                        Text("A longer silence was paused \(report.stallEventCount)×. That’s fine.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Text("Speed is a note, not a goal.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("What this means")

            VStack(alignment: .leading, spacing: SpeechSpacing.related) {
                Text(report.followAlongNote)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(report.gopNote)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !report.contrastFocus.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("This passage practiced")
                            .font(.subheadline.weight(.semibold))
                        Text(report.contrastFocus.joined(separator: " · "))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
        }
    }

    private var notableWords: [WordAnalysis] {
        report.wordAnalyses.filter { $0.occupancy == "skipped" || $0.occupancy == "swapped" }
    }

    private var visibleWords: [WordAnalysis] {
        showAllWords ? notableWords : Array(notableWords.prefix(wordPreviewCount))
    }

    private var hiddenWordCount: Int {
        max(0, notableWords.count - wordPreviewCount)
    }

    private var wordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Words that stood out")

            VStack(spacing: 0) {
                ForEach(Array(visibleWords.enumerated()), id: \.element.id) { index, word in
                    if index > 0 {
                        Divider().padding(.leading, 20)
                    }
                    notableWordRow(word)
                }

                if notableWords.count > wordPreviewCount {
                    Divider().padding(.leading, 20)
                    Button {
                        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
                            showAllWords.toggle()
                            if !showAllWords {
                                expandedWordIDs = Set(
                                    notableWords.prefix(wordPreviewCount).map(\.id)
                                ).intersection(expandedWordIDs)
                            }
                        }
                    } label: {
                        Text(showAllWords ? "Show less" : "Show \(hiddenWordCount) more")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(cardBackground)
        }
    }

    private func notableWordRow(_ word: WordAnalysis) -> some View {
        let expanded = expandedWordIDs.contains(word.id)
        return Button {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
                if expanded {
                    expandedWordIDs.remove(word.id)
                } else {
                    expandedWordIDs.insert(word.id)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text(word.surface)
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 12)
                    Text(occupancyTitle(word.occupancy))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }

                if expanded {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(occupancyDetail(word.occupancy))
                        if !word.canonicalPhones.isEmpty {
                            Text("Sounds \(word.canonicalPhones.joined(separator: " "))")
                        }
                        if word.soundAssessment != "not assessed" {
                            Text(word.soundAssessment.capitalized)
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(expanded ? "Hides details" : "Shows details")
    }

    private func occupancyTitle(_ occupancy: String) -> String {
        switch occupancy {
        case "skipped": "Skipped"
        case "swapped": "Swapped"
        default: occupancy.capitalized
        }
    }

    private func occupancyDetail(_ occupancy: String) -> String {
        switch occupancy {
        case "skipped": "We didn’t hear this word in the passage."
        case "swapped": "A different word landed here."
        default: "Marked during follow-along."
        }
    }

    @ViewBuilder
    private func diagnosticsSection(path: String) -> some View {
        let url = URL(fileURLWithPath: path)
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Diagnostics")

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Session lag log from this reading. Share it if follow-along felt stuck.")
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
                        Text("Log file missing.")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("Session log")
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            .tint(.secondary)
            .padding(20)
            .background(cardBackground)
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.6)
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(.secondarySystemBackground))
    }
}
