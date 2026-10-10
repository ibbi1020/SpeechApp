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
        let takes = item.takeCount == 1 ? "1 take" : "\(item.takeCount) takes"
        return "\(date) · \(takes)"
    }

    @ViewBuilder
    private func savedReport(for item: RecordingManifest) -> some View {
        let report = MonologueReport(
            kind: item.takes.isEmpty ? .thin : .full,
            endReason: .completed,
            takeCount: item.takeCount,
            lines: item.reportLines,
            comparison: item.comparison
        )
        MonologueReportView(report: report, regimenID: item.id)
    }
}

extension RecordingManifest: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
