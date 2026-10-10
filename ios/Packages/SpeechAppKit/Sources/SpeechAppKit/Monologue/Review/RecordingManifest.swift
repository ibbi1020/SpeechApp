import Foundation

public struct RecordingManifest: Equatable, Hashable, Sendable, Codable, Identifiable {
    public enum Format: String, Equatable, Sendable, Codable {
        case monologue
        case reading
        case conversation
    }

    public struct Take: Equatable, Hashable, Sendable, Codable, Identifiable {
        public var id: Int { index }
        public let index: Int
        public let durationSeconds: TimeInterval
        public let audioFileName: String
        public let words: [RecordedWord]
        public let markers: [ReviewMarker]

        public init(
            index: Int,
            durationSeconds: TimeInterval,
            audioFileName: String,
            words: [RecordedWord],
            markers: [ReviewMarker]
        ) {
            self.index = index
            self.durationSeconds = durationSeconds
            self.audioFileName = audioFileName
            self.words = words
            self.markers = markers
        }
    }

    public let id: UUID
    public let format: Format
    public let createdAt: Date
    public let topic: String
    public let reportLines: [MonologueReport.Line]
    public let comparison: String
    public let takes: [Take]
    /// Set when audio could not be saved (e.g. disk full).
    public let saveError: String?

    public init(
        id: UUID = UUID(),
        format: Format = .monologue,
        createdAt: Date = Date(),
        topic: String,
        reportLines: [MonologueReport.Line],
        comparison: String,
        takes: [Take],
        saveError: String? = nil
    ) {
        self.id = id
        self.format = format
        self.createdAt = createdAt
        self.topic = topic
        self.reportLines = reportLines
        self.comparison = comparison
        self.takes = takes
        self.saveError = saveError
    }

    public var takeCount: Int { takes.count }
}
