import Foundation
import Testing
@testable import SpeechAppKit

@Suite("Recording store")
struct RecordingStoreTests {
    @Test("saves, lists newest first, loads, and deletes")
    func roundTrip() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeechAppRecordings-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = RecordingStore(rootURL: root)
        let older = makeManifest(topic: "older", createdAt: Date(timeIntervalSince1970: 1_000))
        let newer = makeManifest(topic: "newer", createdAt: Date(timeIntervalSince1970: 2_000))
        try store.save(older)
        try store.save(newer)

        let listed = try store.list()
        #expect(listed.map(\.topic) == ["newer", "older"])
        #expect(try store.load(id: newer.id)?.topic == "newer")

        try store.delete(id: newer.id)
        #expect(try store.list().map(\.topic) == ["older"])

        try store.deleteAll()
        #expect(try store.list().isEmpty)
    }

    @Test("format filter returns only monologue")
    func formatFilter() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeechAppRecordings-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RecordingStore(rootURL: root)
        try store.save(makeManifest(topic: "talk", format: .monologue))
        let filtered = try store.list(format: .monologue)
        #expect(filtered.count == 1)
        #expect(try store.list(format: .reading).isEmpty)
    }

    @Test("crisis delete removes the whole regimen folder")
    func crisisDelete() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeechAppRecordings-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RecordingStore(rootURL: root)
        let manifest = makeManifest(topic: "crisis")
        try store.save(manifest)
        // Simulate a take audio file already on disk.
        let audio = store.regimenDirectory(id: manifest.id).appendingPathComponent("take-1.m4a")
        try Data([0, 1, 2]).write(to: audio)
        try store.delete(id: manifest.id)
        #expect(!FileManager.default.fileExists(atPath: store.regimenDirectory(id: manifest.id).path))
        #expect(try store.list().isEmpty)
    }

    private func makeManifest(
        topic: String,
        format: RecordingManifest.Format = .monologue,
        createdAt: Date = Date()
    ) -> RecordingManifest {
        RecordingManifest(
            format: format,
            createdAt: createdAt,
            topic: topic,
            reportLines: [MonologueReport.Line(label: "Takes", value: "1")],
            comparison: "",
            takes: [
                RecordingManifest.Take(
                    index: 1,
                    durationSeconds: 40,
                    audioFileName: "take-1.m4a",
                    words: [RecordedWord(surface: "hi", start: 0, end: 0.2)],
                    markers: []
                ),
            ]
        )
    }
}
