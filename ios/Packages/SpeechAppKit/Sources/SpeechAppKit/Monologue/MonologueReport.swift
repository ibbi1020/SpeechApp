import Foundation

public struct MonologueReport: Equatable, Sendable, Identifiable {
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
    public let endReason: MonologueEndReason
    public let takeCount: Int
    public let lines: [Line]
    public let comparison: String

    public init(
        id: UUID = UUID(),
        kind: Kind,
        endReason: MonologueEndReason,
        takeCount: Int,
        lines: [Line],
        comparison: String
    ) {
        self.id = id
        self.kind = kind
        self.endReason = endReason
        self.takeCount = takeCount
        self.lines = lines
        self.comparison = comparison
    }
}

public enum MonologueReportBuilder {
    public static func build(
        takes: [MonologueTake],
        endReason: MonologueEndReason
    ) -> MonologueReport {
        if endReason == .crisisReferral {
            return MonologueReport(
                kind: .crisis,
                endReason: endReason,
                takeCount: takes.count,
                lines: [],
                comparison: ""
            )
        }

        let counting = takes.filter(\.counts)
        if counting.count < 2 {
            let wall = takes.reduce(0.0) { $0 + $1.wallSeconds }
            return MonologueReport(
                kind: .thin,
                endReason: endReason,
                takeCount: takes.count,
                lines: [
                    MonologueReport.Line(label: "Time spoken", value: format(wall)),
                    MonologueReport.Line(label: "Takes", value: "\(takes.count)"),
                ],
                comparison: ""
            )
        }

        var lines: [MonologueReport.Line] = []
        var previous: MonologueTake?
        for take in counting {
            lines.append(MonologueReport.Line(label: "Take \(take.index)", value: format(take.wallSeconds)))
            let spoken = take.spokenSeconds
            if let ptr = MonologuePhonation.ratio(spoken: spoken, wall: take.wallSeconds) {
                lines.append(MonologueReport.Line(
                    label: "Phonation-time ratio",
                    value: String(format: "%.2f", ptr)
                ))
            }
            let pause = ConversationPauseTime.seconds(from: take.ranges)
            lines.append(MonologueReport.Line(label: "Pause time", value: String(format: "%.1fs", pause)))
            lines.append(MonologueReport.Line(
                label: "Silent gaps ≥250 ms",
                value: "\(ConversationPauseTime.count(from: take.ranges))"
            ))
            if let pace = ConversationPace.syllablesPerMinute(
                transcript: FillerWords.strippingTranscript(take.transcript),
                speechSeconds: spoken
            ) {
                lines.append(MonologueReport.Line(
                    label: "Pace",
                    value: String(format: "%.0f / min (spelling estimate)", pace)
                ))
            }
            if let previous,
               let overlap = MonologueOverlap.tokenPercent(
                previous: previous.transcript,
                current: take.transcript
               ) {
                lines.append(MonologueReport.Line(
                    label: "Overlap vs take \(previous.index)",
                    value: String(format: "%.0f%%", overlap)
                ))
            }
            previous = take
        }

        let first = counting.first!
        let last = counting.last!
        return MonologueReport(
            kind: .full,
            endReason: endReason,
            takeCount: takes.count,
            lines: lines,
            comparison: comparison(first: first, last: last)
        )
    }

    public static func comparison(first: MonologueTake, last: MonologueTake) -> String {
        let timeWord = last.spokenSeconds >= first.spokenSeconds ? "more" : "less"
        let firstGaps = ConversationPauseTime.count(from: first.ranges)
        let lastGaps = ConversationPauseTime.count(from: last.ranges)
        let gapWord = lastGaps <= firstGaps ? "fewer" : "more"
        return "Take \(last.index) vs take \(first.index): \(timeWord) talking time, \(gapWord) long gaps."
    }

    private static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return "\(s / 60)m \(s % 60)s"
    }
}
