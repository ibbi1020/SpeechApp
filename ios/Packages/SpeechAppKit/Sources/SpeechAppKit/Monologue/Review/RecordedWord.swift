import Foundation

/// One spoken word on the saved take's timeline (pause gaps already removed).
public struct RecordedWord: Equatable, Hashable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let surface: String
    public let start: TimeInterval
    public let end: TimeInterval
    public let isFiller: Bool

    public init(
        id: UUID = UUID(),
        surface: String,
        start: TimeInterval,
        end: TimeInterval,
        isFiller: Bool? = nil
    ) {
        self.id = id
        self.surface = surface
        self.start = start
        self.end = end
        self.isFiller = isFiller ?? FillerWords.isFiller(surface)
    }

    public var duration: TimeInterval { max(0, end - start) }
}
