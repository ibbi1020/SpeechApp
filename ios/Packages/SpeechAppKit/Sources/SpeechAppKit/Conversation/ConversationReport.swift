import Foundation

public struct ConversationReport: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable { case thin, full, crisis }
    public struct Line: Equatable, Sendable {
        public let label: String
        public let value: String
        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
    }

    public let id: UUID
    public let kind: Kind
    public let endReason: ConversationEndReason
    public let userSpeechSeconds: TimeInterval
    public let userTurns: Int
    public let lines: [Line]
    public let limitedAnalysis: Bool
    /// Caption↔audio JSONL from this hang-up, if the live mouth wrote one.
    public let captionSyncLogPath: String?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        endReason: ConversationEndReason,
        userSpeechSeconds: TimeInterval,
        userTurns: Int,
        lines: [Line],
        limitedAnalysis: Bool = false,
        captionSyncLogPath: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.endReason = endReason
        self.userSpeechSeconds = userSpeechSeconds
        self.userTurns = userTurns
        self.lines = lines
        self.limitedAnalysis = limitedAnalysis
        self.captionSyncLogPath = captionSyncLogPath
    }
}

public enum ConversationReportBuilder {
    public static let minSpeech: TimeInterval = 45
    public static let minTurns = 3

    public static func build(
        userSpeechSeconds: TimeInterval,
        userTurns: Int,
        endReason: ConversationEndReason,
        extraFullLines: [ConversationReport.Line] = [],
        limitedAnalysis: Bool = false,
        captionSyncLogPath: String? = nil
    ) -> ConversationReport {
        if endReason == .crisisReferral {
            return ConversationReport(
                kind: .crisis,
                endReason: endReason,
                userSpeechSeconds: userSpeechSeconds,
                userTurns: userTurns,
                lines: [],
                captionSyncLogPath: captionSyncLogPath
            )
        }
        let timeValue = limitedAnalysis
            ? "\(Self.format(userSpeechSeconds)) (uncertain)"
            : Self.format(userSpeechSeconds)
        let time = ConversationReport.Line(
            label: "Time spoken",
            value: timeValue
        )
        let turns = ConversationReport.Line(
            label: "Turns",
            value: "\(userTurns)"
        )
        let thin = userSpeechSeconds < minSpeech || userTurns < minTurns
        if thin {
            return ConversationReport(
                kind: .thin,
                endReason: endReason,
                userSpeechSeconds: userSpeechSeconds,
                userTurns: userTurns,
                lines: [time, turns],
                limitedAnalysis: limitedAnalysis,
                captionSyncLogPath: captionSyncLogPath
            )
        }
        return ConversationReport(
            kind: .full,
            endReason: endReason,
            userSpeechSeconds: userSpeechSeconds,
            userTurns: userTurns,
            lines: [time, turns] + extraFullLines,
            limitedAnalysis: limitedAnalysis,
            captionSyncLogPath: captionSyncLogPath
        )
    }

    private static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return "\(s / 60)m \(s % 60)s"
    }
}
