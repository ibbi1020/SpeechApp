import Foundation

/// What the Progress sheet can draw from the ledger and saved recordings.
/// Charts are oldest first. `RecordingStore.list()` is newest first.
public struct ProgressSnapshot: Equatable, Sendable {
    public struct Turn: Equatable, Sendable {
        public var secondsPerTurn: Double
    }

    public struct Talk: Equatable, Sendable {
        /// Breakdown pauses per minute, in take order.
        public var pauseFrequency: [Double]
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

    private let calendar: Calendar
    /// Every saved turn, oldest first. A stretch filters this. All time does too.
    private let datedTurns: [DatedTurn]
    private let datedTalks: [DatedTalk]
    /// Misses, skips, and speeds since dating began. Old totals are not copied here.
    private let datedMisses: [DatedMiss]
    private let datedSkips: [DatedSkip]
    private let datedRates: [DatedRate]

    public init(
        ledger: StruggleLedger,
        recordings: [RecordingManifest],
        catalog: PassageCatalog,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.calendar = calendar
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
        datedTurns = saved.compactMap { recording in
            guard let turn = Self.turn(recording) else { return nil }
            return DatedTurn(date: recording.createdAt, turn: turn)
        }
        datedTalks = saved.compactMap { recording in
            guard let talk = Self.talk(recording) else { return nil }
            return DatedTalk(date: recording.createdAt, talk: talk)
        }
        datedMisses = ledger.missEvents.map {
            DatedMiss(date: $0.date, phone: $0.phone, band: $0.flBand)
        }
        datedSkips = ledger.skipEvents.compactMap { event in
            guard let word = Self.word(for: event.wordId, catalog: catalog) else { return nil }
            return DatedSkip(date: event.date, wordId: event.wordId, word: word)
        }
        datedRates = ledger.speechRateEvents.map {
            DatedRate(date: $0.date, rate: $0.syllablesPerMinute)
        }
        turns = datedTurns.map(\.turn)
        talks = datedTalks.map(\.talk)
        sounds = Self.sounds(in: ledger)
        skips = Self.skips(in: ledger, catalog: catalog)
        readingRates = Array(ledger.recentSpeechRates.suffix(10))
    }

    /// Chart rows for an inclusive stretch of civil days.
    /// Sounds, skips, and reading speeds come from the dated log only.
    /// All-time totals stay on the unfiltered snapshot, so an old total is not
    /// counted again inside the stretch.
    public func filtered(from start: Date, through end: Date) -> ProgressSnapshot {
        var copy = self
        let lower = calendar.startOfDay(for: min(start, end))
        let upper = calendar.startOfDay(for: max(start, end))
        func inside(_ date: Date) -> Bool {
            let day = calendar.startOfDay(for: date)
            return day >= lower && day <= upper
        }
        copy.turns = datedTurns.filter { inside($0.date) }.map(\.turn)
        copy.talks = datedTalks.filter { inside($0.date) }.map(\.talk)
        copy.sounds = Self.rankedSounds(datedMisses.filter { inside($0.date) })
        copy.skips = Self.rankedSkipEvents(datedSkips.filter { inside($0.date) })
        copy.readingRates = datedRates
            .filter { inside($0.date) }
            .sorted { $0.date < $1.date }
            .map(\.rate)
        return copy
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
    /// The next pause line belongs to that take. New reports store pauses per
    /// minute. Older reports stored a raw gap count, which is divided by the
    /// take clock when that clock is readable.
    private static func talk(_ recording: RecordingManifest) -> Talk? {
        guard recording.format == .monologue else { return nil }
        var rates: [Double] = []
        var open = false
        var filled = false
        var clock: TimeInterval?
        for line in recording.reportLines {
            if line.label.hasPrefix("Take ") {
                open = true
                filled = false
                clock = takeClock(line.value)
                continue
            }
            guard open, !filled else { continue }
            let rate: Double?
            if line.label == MonologueFluency.Label.pauseFrequency {
                rate = frequency(line.value)
            } else if line.label == "Silent gaps ≥250 ms" {
                rate = legacyGapRate(line.value, clock: clock)
            } else {
                rate = nil
            }
            guard let rate else { continue }
            rates.append(rate)
            filled = true
        }
        guard !rates.isEmpty else { return nil }
        return Talk(pauseFrequency: rates)
    }

    /// `1m 5s` is 65. A bare `2m` is 120.
    private static func takeClock(_ value: String) -> TimeInterval? {
        if let seconds = spokenSeconds(value) { return TimeInterval(seconds) }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix("m"), let minutes = Double(text.dropLast()) {
            return minutes * 60
        }
        if text.hasSuffix("s"), let seconds = Double(text.dropLast()) {
            return seconds
        }
        return nil
    }

    private static func frequency(_ value: String) -> Double? {
        let head = value.split(separator: " ").first.map(String.init) ?? value
        return Double(head)
    }

    private static func legacyGapRate(_ value: String, clock: TimeInterval?) -> Double? {
        guard let count = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        guard let clock, clock > 0 else { return Double(count) }
        return Double(count) / (clock / 60)
    }

    /// High functional load first, then the higher miss count. At most five.
    private static func sounds(in ledger: StruggleLedger) -> [Sound] {
        rankedSounds(ledger.phones.map {
            SoundRow(symbol: $0.phone, misses: $0.missCount, band: $0.flBand)
        })
    }

    private static func rankedSounds(_ rows: [SoundRow]) -> [Sound] {
        rows
            .filter { $0.misses > 0 }
            .sorted { lhs, rhs in
                if lhs.band != rhs.band { return lhs.band > rhs.band }
                if lhs.misses != rhs.misses { return lhs.misses > rhs.misses }
                return lhs.symbol < rhs.symbol
            }
            .prefix(5)
            .map { Sound(symbol: $0.symbol, misses: $0.misses, highLoad: $0.band == .high) }
    }

    private static func rankedSounds(_ events: [DatedMiss]) -> [Sound] {
        var buckets: [String: SoundRow] = [:]
        for event in events {
            if var row = buckets[event.phone] {
                row.misses += 1
                if event.band > row.band { row.band = event.band }
                buckets[event.phone] = row
            } else {
                buckets[event.phone] = SoundRow(symbol: event.phone, misses: 1, band: event.band)
            }
        }
        return rankedSounds(Array(buckets.values))
    }

    /// Word ids are `passageId-index`, and passage ids contain hyphens.
    /// The longest catalog id that is a prefix wins. `surface` is not the word.
    private static func skips(in ledger: StruggleLedger, catalog: PassageCatalog) -> [Skip] {
        let resolved = ledger.skipWords.compactMap { skip -> SkipRow? in
            guard skip.count > 0, let word = word(for: skip.wordId, catalog: catalog) else { return nil }
            return SkipRow(word: word, count: skip.count)
        }
        return rankedSkips(resolved)
    }

    private static func rankedSkipEvents(_ events: [DatedSkip]) -> [Skip] {
        var counts: [String: SkipRow] = [:]
        for event in events {
            if var row = counts[event.wordId] {
                row.count += 1
                counts[event.wordId] = row
            } else {
                counts[event.wordId] = SkipRow(word: event.word, count: 1)
            }
        }
        return rankedSkips(Array(counts.values))
    }

    private static func rankedSkips(_ rows: [SkipRow]) -> [Skip] {
        rows
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.word < rhs.word
            }
            .prefix(5)
            .map { Skip(word: $0.word, count: $0.count) }
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

    private struct DatedTurn: Equatable, Sendable {
        var date: Date
        var turn: Turn
    }

    private struct DatedTalk: Equatable, Sendable {
        var date: Date
        var talk: Talk
    }

    private struct DatedMiss: Equatable, Sendable {
        var date: Date
        var phone: String
        var band: FunctionalLoadBand
    }

    private struct DatedSkip: Equatable, Sendable {
        var date: Date
        var wordId: String
        var word: String
    }

    private struct DatedRate: Equatable, Sendable {
        var date: Date
        var rate: Double
    }

    private struct SoundRow: Equatable, Sendable {
        var symbol: String
        var misses: Int
        var band: FunctionalLoadBand
    }

    private struct SkipRow: Equatable, Sendable {
        var word: String
        var count: Int
    }
}
