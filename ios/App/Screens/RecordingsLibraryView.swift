import SwiftUI
import SpeechAppKit

struct RecordingsLibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let filter: RecordingManifest.Format?

    @State private var manifests: [RecordingManifest] = []
    @State private var keepEnabled = RecordingsService.keepRecordings
    @State private var confirmDeleteAll = false
    @State private var selected: RecordingManifest?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            SpeechScreenBackground()

            List {
                Section {
                    Toggle("Keep recordings", isOn: $keepEnabled)
                        .onChange(of: keepEnabled) { _, value in
                            RecordingsService.keepRecordings = value
                        }
                    Text("When on, topic talks stay on this phone so you can listen back. Turning off stops new ones; existing ones stay until you delete them.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    if manifests.isEmpty {
                        Text("No recordings yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(manifests) { item in
                            Button {
                                selected = item
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.topic)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Text(rowSubtitle(item))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }

                if !manifests.isEmpty {
                    Section {
                        Button("Delete all recordings", role: .destructive) {
                            confirmDeleteAll = true
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .speechPageTitle(filter == .monologue ? "Your talks" : "Your recordings")
        .speechBottomBlur()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { model.goHome() }
            }
        }
        .task { reload() }
        .confirmationDialog(
            "Delete all recordings on this phone?",
            isPresented: $confirmDeleteAll,
            titleVisibility: .visible
        ) {
            Button("Delete all", role: .destructive) {
                try? RecordingsService.store.deleteAll()
                reload()
            }
            Button("Cancel", role: .cancel) {}
        }
        .navigationDestination(item: $selected) { item in
            savedReport(for: item)
        }
    }

    private func reload() {
        do {
            manifests = try RecordingsService.store.list(format: filter)
        } catch {
            errorMessage = error.localizedDescription
            manifests = []
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let id = manifests[index].id
            try? RecordingsService.store.delete(id: id)
        }
        reload()
    }

    private func rowSubtitle(_ item: RecordingManifest) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let date = formatter.string(from: item.createdAt)
        switch item.format {
        case .monologue:
            let takes = item.takeCount == 1 ? "1 take" : "\(item.takeCount) takes"
            return "Talk · \(date) · \(takes)"
        case .reading:
            return "Reading · \(date)"
        case .conversation:
            return "Conversation · \(date)"
        }
    }

    @ViewBuilder
    private func savedReport(for item: RecordingManifest) -> some View {
        switch item.format {
        case .monologue:
            MonologueReportView(
                report: MonologueReport(
                    kind: item.takes.isEmpty ? .thin : .full,
                    endReason: .completed,
                    takeCount: item.takeCount,
                    lines: item.reportLines,
                    comparison: item.comparison
                ),
                regimenID: item.id
            )
        case .reading, .conversation:
            SavedRecordingView(manifest: item)
        }
    }
}

/// A saved Reading or Conversation: the report lines, then the player.
private struct SavedRecordingView: View {
    let manifest: RecordingManifest

    var body: some View {
        ZStack {
            SpeechScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(manifest.topic)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, SpeechSpacing.related)

                    if !manifest.reportLines.isEmpty {
                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(Array(manifest.reportLines.enumerated()), id: \.offset) { _, line in
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

                    TakeReviewSection(manifest: manifest, saveError: manifest.saveError)
                        .padding(.top, SpeechSpacing.section)
                        .padding(.bottom, 32)
                }
                .padding(.horizontal, SpeechSpacing.page)
                .padding(.top, 20)
            }
        }
        .speechPageTitle(manifest.format == .reading ? "Your reading" : "Your conversation")
        .speechBottomBlur()
    }
}
