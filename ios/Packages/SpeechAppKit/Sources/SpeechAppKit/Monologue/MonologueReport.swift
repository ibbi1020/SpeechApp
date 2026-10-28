import Foundation

public struct MonologueReport: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable { case thin, full, crisis }

    public struct Line: Equatable, Hashable, Sendable, Codable {
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
                    MonologueReport.Line(label: MonologueFluency.Label.speakingTime, value: format(wall)),
                    MonologueReport.Line(label: "Takes", value: "\(takes.count)"),
                ],
                comparison: ""
            )
        }

        var lines: [MonologueReport.Line] = []
        var previous: MonologueTake?
        for take in counting {
            lines.append(MonologueReport.Line(label: "Take \(take.index)", value: format(take.wallSeconds)))
            lines.append(contentsOf: profileLines(MonologueFluency.measure(take)))
            if let previous,
               let reuse = MonologueOverlap.verbatimPercent(
                previous: previous.transcript,
                current: take.transcript
               ) {
                lines.append(MonologueReport.Line(
                    label: MonologueFluency.Label.verbatimReuse(versus: previous.index),
                    value: String(format: "%.0f%%", reuse)
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
        let before = MonologueFluency.measure(first)
        let after = MonologueFluency.measure(last)
        let rate = change(
            from: before.speechRate,
            to: after.speechRate,
            same: "the same speech rate",
            higher: "a faster speech rate",
            lower: "a slower speech rate",
            tolerance: 1
        )
        let pauses = change(
            from: before.pauseFrequency,
            to: after.pauseFrequency,
            same: "the same pause frequency",
            higher: "more pauses per minute",
            lower: "fewer pauses per minute",
            tolerance: 0.1
        )
        let parts = [rate, pauses].compactMap { $0 }
        guard !parts.isEmpty else { return "" }
        if rate == "the same speech rate", pauses == "the same pause frequency" {
            return "Take \(last.index) vs take \(first.index): the same speech rate and pause frequency."
        }
        return "Take \(last.index) vs take \(first.index): \(parts.joined(separator: ", "))."
    }

    private static func profileLines(_ profile: MonologueFluency.Profile) -> [MonologueReport.Line] {
        var lines: [MonologueReport.Line] = []
        func add(_ label: String, _ value: String?) {
            guard let value else { return }
            lines.append(MonologueReport.Line(label: label, value: value))
        }
        add(MonologueFluency.Label.speechRate, sylPerMin(profile.speechRate))
        add(MonologueFluency.Label.articulationRate, sylPerMin(profile.articulationRate))
        add(MonologueFluency.Label.meanLengthOfRun, syl(profile.meanLengthOfRun))
        add(MonologueFluency.Label.trimmedSpeechRate, sylPerMin(profile.trimmedSpeechRate))
        if let ratio = profile.phonationTimeRatio {
            add(MonologueFluency.Label.phonationTimeRatio, String(format: "%.2f", ratio))
        }
        if let frequency = profile.pauseFrequency {
            add(MonologueFluency.Label.pauseFrequency, String(format: "%.1f / min", frequency))
        }
        if let mean = profile.meanPause {
            add(MonologueFluency.Label.meanPause, String(format: "%.1f s", mean))
        }
        if let filled = profile.filledPauseFrequency {
            add(MonologueFluency.Label.filledPauses, String(format: "%.1f / min", filled))
        }
        return lines
    }

    private static func sylPerMin(_ value: Double?) -> String? {
        guard let value else { return nil }
        return String(format: "%.0f syl/min", value)
    }

    private static func syl(_ value: Double?) -> String? {
        guard let value else { return nil }
        return String(format: "%.1f syl", value)
    }

    private static func change(
        from earlier: Double?,
        to later: Double?,
        same: String,
        higher: String,
        lower: String,
        tolerance: Double
    ) -> String? {
        guard let earlier, let later else { return nil }
        if abs(later - earlier) < tolerance { return same }
        return later > earlier ? higher : lower
    }

    private static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return "\(s / 60)m \(s % 60)s"
    }
}
