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
        /// Conversation only.
        public let partnerTurns: [PartnerTurn]?

        public init(
            index: Int,
            durationSeconds: TimeInterval,
            audioFileName: String,
            words: [RecordedWord],
            markers: [ReviewMarker],
            partnerTurns: [PartnerTurn]? = nil
        ) {
            self.index = index
            self.durationSeconds = durationSeconds
            self.audioFileName = audioFileName
            self.words = words
            self.markers = markers
            self.partnerTurns = partnerTurns
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
    /// False while the take is only on the report. The gallery lists saved takes.
    public var inLibrary: Bool

    public init(
        id: UUID = UUID(),
        format: Format = .monologue,
        createdAt: Date = Date(),
        topic: String,
        reportLines: [MonologueReport.Line],
        comparison: String,
        takes: [Take],
        saveError: String? = nil,
        inLibrary: Bool = true
    ) {
        self.id = id
        self.format = format
        self.createdAt = createdAt
        self.topic = topic
        self.reportLines = reportLines
        self.comparison = comparison
        self.takes = takes
        self.saveError = saveError
        self.inLibrary = inLibrary
    }

    public var takeCount: Int { takes.count }

    private enum CodingKeys: String, CodingKey {
        case id, format, createdAt, topic, reportLines, comparison, takes, saveError, inLibrary
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        format = try container.decodeIfPresent(Format.self, forKey: .format) ?? .monologue
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        topic = try container.decode(String.self, forKey: .topic)
        reportLines = try container.decode([MonologueReport.Line].self, forKey: .reportLines)
        comparison = try container.decode(String.self, forKey: .comparison)
        takes = try container.decode([Take].self, forKey: .takes)
        saveError = try container.decodeIfPresent(String.self, forKey: .saveError)
        inLibrary = try container.decodeIfPresent(Bool.self, forKey: .inLibrary) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(format, forKey: .format)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(topic, forKey: .topic)
        try container.encode(reportLines, forKey: .reportLines)
        try container.encode(comparison, forKey: .comparison)
        try container.encode(takes, forKey: .takes)
        try container.encodeIfPresent(saveError, forKey: .saveError)
        try container.encode(inLibrary, forKey: .inLibrary)
    }
}
