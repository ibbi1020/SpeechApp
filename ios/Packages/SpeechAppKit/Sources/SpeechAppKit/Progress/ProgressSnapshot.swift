import Foundation

/// What the Progress sheet can draw from the ledger and saved recordings.
/// Charts are oldest first. `RecordingStore.list()` is newest first.
public struct ProgressSnapshot: Equatable, Sendable {
    public struct Turn: Equatable, Sendable {
        public var secondsPerTurn: Double
    }

    public struct Talk: Equatable, Sendable {
        /// Long silences in take order. Takes with no gap line are left out.
        public var longSilences: [Int]
    }

    public struct Sound: Equatable, Sendable {
        public var symbol: String
        public var misses: Int
        public var highLoad: Bool
    }

    public struct Skip: Equatable, Sendable {
        public var word: String
        public var count: Int
    }

    /// Start of each day that has a saved recording, in `calendar`.
    public var practicedDays: Set<Date>
    /// Start of the day of the earliest saved recording.
    public var earliestDay: Date?
    /// First month the calendar may show. This month when nothing is saved.
    public var firstMonth: Date
    /// This month. The calendar does not go past it.
    public var latestMonth: Date
    /// Start of today in `calendar`.
    public var today: Date
    public var turns: [Turn]
    public var talks: [Talk]
    public var sounds: [Sound]
    public var skips: [Skip]
    /// Oldest on the left. At most ten.
    public var readingRates: [Double]

    public init(
        ledger: StruggleLedger,
        recordings: [RecordingManifest],
        catalog: PassageCatalog,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let saved = recordings.filter(\.inLibrary).sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let days = Set(saved.map { calendar.startOfDay(for: $0.createdAt) })
        practicedDays = days
        earliestDay = days.min()
        today = calendar.startOfDay(for: now)
        let anchor = earliestDay ?? today
        firstMonth = Self.startOfMonth(anchor, calendar: calendar)
        latestMonth = Self.startOfMonth(today, calendar: calendar)
        turns = saved.compactMap(Self.turn)
        talks = saved.compactMap(Self.talk)
        sounds = Self.sounds(in: ledger)
        skips = Self.skips(in: ledger, catalog: catalog)
        readingRates = Array(ledger.recentSpeechRates.suffix(10))
    }

    private static func startOfMonth(_ date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    /// Seconds from a `Time spoken` value. `1m 5s (uncertain)` is 65.
    static func spokenSeconds(_ value: String) -> Int? {
        let text = value
            .replacingOccurrences(of: " (uncertain)", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = text.split(separator: " ")
        guard parts.count == 2,
              parts[0].hasSuffix("m"),
              parts[1].hasSuffix("s"),
              let minutes = Int(parts[0].dropLast()),
              let seconds = Int(parts[1].dropLast())
        else { return nil }
        return minutes * 60 + seconds
    }

    private static func turn(_ recording: RecordingManifest) -> Turn? {
        guard recording.format == .conversation else { return nil }
        var spoken: Int?
        var turns: Int?
        for line in recording.reportLines {
            if line.label == "Time spoken" {
                spoken = spokenSeconds(line.value)
            } else if line.label == "Your turns" {
                turns = Int(line.value.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        guard let spoken, let turns, turns > 0 else { return nil }
        return Turn(secondsPerTurn: Double(spoken) / Double(turns))
    }

    /// A `Take ` label opens a take. The singular prefix matters: `Takes` does not.
    /// The next `Silent gaps ≥250 ms` line belongs to that take.
    private static func talk(_ recording: RecordingManifest) -> Talk? {
        guard recording.format == .monologue else { return nil }
        var counts: [Int] = []
        var open = false
        var filled = false
        for line in recording.reportLines {
            if line.label.hasPrefix("Take ") {
                open = true
                filled = false
                continue
            }
            guard open, !filled, line.label == "Silent gaps ≥250 ms" else { continue }
            guard let count = Int(line.value.trimmingCharacters(in: .whitespacesAndNewlines)) else { continue }
            counts.append(count)
            filled = true
        }
        guard !counts.isEmpty else { return nil }
        return Talk(longSilences: counts)
    }

    /// High functional load first, then the higher miss count. At most five.
    private static func sounds(in ledger: StruggleLedger) -> [Sound] {
        let ranked = ledger.phones
            .filter { $0.missCount > 0 }
            .sorted { lhs, rhs in
                if lhs.flBand != rhs.flBand { return lhs.flBand > rhs.flBand }
                if lhs.missCount != rhs.missCount { return lhs.missCount > rhs.missCount }
                return lhs.phone < rhs.phone
            }
            .prefix(5)
        return ranked.map { phone in
            Sound(symbol: phone.phone, misses: phone.missCount, highLoad: phone.flBand == .high)
        }
    }

    /// Word ids are `passageId-index`, and passage ids contain hyphens.
    /// The longest catalog id that is a prefix wins. `surface` is not the word.
    private static func skips(in ledger: StruggleLedger, catalog: PassageCatalog) -> [Skip] {
        let resolved = ledger.skipWords.compactMap { skip -> Skip? in
            guard skip.count > 0, let word = word(for: skip.wordId, catalog: catalog) else { return nil }
            return Skip(word: word, count: skip.count)
        }
        return resolved
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.word < rhs.word
            }
            .prefix(5)
            .map { $0 }
    }

    static func word(for wordId: String, catalog: PassageCatalog) -> String? {
        guard let passage = catalog.passages
            .filter({ wordId.hasPrefix($0.id + "-") })
            .max(by: { $0.id.count < $1.id.count })
        else { return nil }
        let rest = wordId.dropFirst(passage.id.count + 1)
        guard let index = Int(rest), passage.words.indices.contains(index) else { return nil }
        return passage.words[index].surface
    }
}
