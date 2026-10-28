import Foundation
import Testing
@testable import SpeechAppKit

@Suite("Progress snapshot")
struct ProgressSnapshotTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var now: Date {
        date(2026, 10, 26)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 15) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func recording(
        _ format: RecordingManifest.Format,
        on day: Date,
        lines: [(String, String)] = [],
        inLibrary: Bool = true
    ) -> RecordingManifest {
        RecordingManifest(
            format: format,
            createdAt: day,
            topic: "Topic",
            reportLines: lines.map { MonologueReport.Line(label: $0.0, value: $0.1) },
            comparison: "",
            takes: [],
            inLibrary: inLibrary
        )
    }

    private func snapshot(
        ledger: StruggleLedger = StruggleLedger(),
        recordings: [RecordingManifest] = [],
        catalog: PassageCatalog = PassageCatalog(passages: [])
    ) -> ProgressSnapshot {
        ProgressSnapshot(
            ledger: ledger,
            recordings: recordings,
            catalog: catalog,
            now: now,
            calendar: calendar
        )
    }

    @Test("an empty phone shows this month and no pictures")
    func empty() {
        let picture = snapshot()
        #expect(picture.turns.isEmpty)
        #expect(picture.talks.isEmpty)
        #expect(picture.sounds.isEmpty)
        #expect(picture.skips.isEmpty)
        #expect(picture.readingRates.isEmpty)
        #expect(picture.practicedDays.isEmpty)
        #expect(picture.earliestDay == nil)
        #expect(picture.firstMonth == calendar.date(from: DateComponents(year: 2026, month: 10)))
        #expect(picture.latestMonth == picture.firstMonth)
        #expect(picture.today == calendar.startOfDay(for: now))
    }

    @Test("time spoken is minutes and seconds, and the uncertain suffix is dropped")
    func timeSpoken() {
        #expect(ProgressSnapshot.spokenSeconds("0m 2s") == 2)
        #expect(ProgressSnapshot.spokenSeconds("1m 5s (uncertain)") == 65)

        let picture = snapshot(recordings: [
            recording(.conversation, on: date(2026, 10, 2), lines: [
                ("Time spoken", "1m 5s (uncertain)"),
                ("Your turns", "1"),
            ]),
        ])
        #expect(picture.turns.map(\.secondsPerTurn) == [65])
    }

    @Test("a conversation with zero turns is left out")
    func zeroTurns() {
        let picture = snapshot(recordings: [
            recording(.conversation, on: date(2026, 10, 2), lines: [
                ("Time spoken", "0m 40s"),
                ("Your turns", "0"),
            ]),
        ])
        #expect(picture.turns.isEmpty)
    }

    @Test("saved talks keep each take's long silences, and Takes does not start a take")
    func talks() {
        let counted = recording(.monologue, on: date(2026, 10, 3), lines: [
            ("Take 1", "1m"),
            ("Pause time", "4s"),
            ("Silent gaps ≥250 ms", "4"),
            ("Take 2", "2m"),
            ("Silent gaps ≥250 ms", "2"),
            ("Silent gaps ≥250 ms", "9"),
        ])
        let thin = recording(.monologue, on: date(2026, 10, 4), lines: [
            ("Takes", "2"),
            ("Silent gaps ≥250 ms", "8"),
        ])
        let picture = snapshot(recordings: [thin, counted])
        #expect(picture.talks.map(\.pauseFrequency) == [[4, 1]])
    }

    @Test("skip ids keep the longest passage id, even when it contains hyphens")
    func skipIds() {
        let ship = Passage(
            id: "ship",
            title: "Short",
            words: [ScriptWord(id: "ship-0", surface: "nope")]
        )
        let harbor = Passage(
            id: "ship-sheep-1",
            title: "Harbor",
            words: [
                ScriptWord(id: "ship-sheep-1-0", surface: "ship"),
                ScriptWord(id: "ship-sheep-1-1", surface: "sheep"),
            ]
        )
        let catalog = PassageCatalog(passages: [ship, harbor])
        #expect(ProgressSnapshot.word(for: "ship-sheep-1-0", catalog: catalog) == "ship")
        #expect(ProgressSnapshot.word(for: "ship-0", catalog: catalog) == "nope")
        #expect(ProgressSnapshot.word(for: "missing-passage-0", catalog: catalog) == nil)

        let ledger = StruggleLedger(skipWords: [
            SkipWordStruggle(wordId: "ship-sheep-1-1", surface: "Skipped", count: 2),
            SkipWordStruggle(wordId: "gone-1-0", surface: "Skipped", count: 9),
            SkipWordStruggle(wordId: "ship-sheep-1-0", surface: "Skipped", count: 4),
        ])
        let picture = snapshot(ledger: ledger, catalog: catalog)
        #expect(picture.skips.map(\.word) == ["ship", "sheep"])
        #expect(picture.skips.map(\.count) == [4, 2])
        #expect(!picture.skips.contains { $0.word == "Skipped" })
    }

    @Test("charts run from the earliest save to the latest, and hidden saves stay out")
    func orderAndLibrary() {
        let later = recording(.conversation, on: date(2026, 10, 20), lines: [
            ("Your turns", "2"),
            ("Time spoken", "0m 10s"),
        ])
        let earlier = recording(.conversation, on: date(2026, 8, 12), lines: [
            ("Time spoken", "0m 4s"),
            ("Your turns", "2"),
        ])
        let hidden = recording(.conversation, on: date(2026, 9, 1), lines: [
            ("Time spoken", "0m 50s"),
            ("Your turns", "1"),
        ], inLibrary: false)
        let reading = recording(.reading, on: date(2026, 10, 26))
        var ledger = StruggleLedger()
        ledger.recentSpeechRates = [140, 160, 150]
        let picture = snapshot(
            ledger: ledger,
            recordings: [later, hidden, reading, earlier]
        )
        #expect(picture.turns.map(\.secondsPerTurn) == [2, 5])
        #expect(picture.readingRates == [140, 160, 150])
        #expect(picture.earliestDay == calendar.startOfDay(for: date(2026, 8, 12)))
        #expect(picture.firstMonth == calendar.date(from: DateComponents(year: 2026, month: 8)))
        #expect(picture.practicedDays == [
            calendar.startOfDay(for: date(2026, 8, 12)),
            calendar.startOfDay(for: date(2026, 10, 20)),
            calendar.startOfDay(for: date(2026, 10, 26)),
        ])
        #expect(!picture.practicedDays.contains(calendar.startOfDay(for: date(2026, 9, 1))))
    }

    @Test("sounds put the high band first, then the higher miss count, and stop at five")
    func sounds() {
        let ledger = StruggleLedger(phones: [
            PhoneStruggle(phone: "l", flBand: .medium, missCount: 9),
            PhoneStruggle(phone: "ɪ", flBand: .high, missCount: 2),
            PhoneStruggle(phone: "i", flBand: .high, missCount: 6),
            PhoneStruggle(phone: "z", flBand: .low, missCount: 8),
            PhoneStruggle(phone: "s", flBand: .medium, missCount: 3),
            PhoneStruggle(phone: "t", flBand: .low, missCount: 7),
            PhoneStruggle(phone: "n", flBand: .low, missCount: 0),
        ])
        let picture = snapshot(ledger: ledger)
        #expect(picture.sounds.map(\.symbol) == ["i", "ɪ", "l", "s", "z"])
        #expect(picture.sounds.map(\.highLoad) == [true, true, false, false, false])
    }

    @Test("all-time sounds and skips use the running totals, and a stretch uses only the dated log")
    func stretchIgnoresOldTotals() {
        let day = date(2026, 10, 2)
        let other = date(2026, 10, 4)
        var ledger = StruggleLedger(
            phones: [PhoneStruggle(phone: "i", flBand: .high, missCount: 9)],
            skipWords: [SkipWordStruggle(wordId: "ship-0", surface: "Skipped", count: 7)],
            recentSpeechRates: [140, 150, 160]
        )
        ledger.missEvents = [
            PhoneMissEvent(phone: "l", flBand: .medium, date: day),
            PhoneMissEvent(phone: "l", flBand: .medium, date: day),
            PhoneMissEvent(phone: "i", flBand: .high, date: day),
        ]
        ledger.skipEvents = [
            SkipEvent(wordId: "ship-0", surface: "Skipped", date: day),
        ]
        ledger.speechRateEvents = [
            SpeechRateEvent(syllablesPerMinute: 180, date: day),
        ]
        let catalog = PassageCatalog(passages: [
            Passage(
                id: "ship",
                title: "Short",
                words: [ScriptWord(id: "ship-0", surface: "ship")]
            ),
        ])
        let all = snapshot(ledger: ledger, catalog: catalog)
        #expect(all.sounds.map(\.symbol) == ["i"])
        #expect(all.sounds.map(\.misses) == [9])
        #expect(all.skips.map(\.word) == ["ship"])
        #expect(all.skips.map(\.count) == [7])
        #expect(all.readingRates == [140, 150, 160])

        let one = all.filtered(from: day, through: day)
        #expect(one.sounds.map(\.symbol) == ["i", "l"])
        #expect(one.sounds.map(\.misses) == [1, 2])
        #expect(one.sounds.map(\.highLoad) == [true, false])
        #expect(one.skips.map(\.word) == ["ship"])
        #expect(one.skips.map(\.count) == [1])
        #expect(one.readingRates == [180])
        #expect(one.practicedDays == all.practicedDays)

        let missed = all.filtered(from: other, through: other)
        #expect(missed.sounds.isEmpty)
        #expect(missed.skips.isEmpty)
        #expect(missed.readingRates.isEmpty)
    }

    @Test("a stretch with no dated reading speeds is empty, and all time stays the last 10")
    func readingWindow() {
        var ledger = StruggleLedger()
        let start = date(2026, 9, 1, 12)
        for index in 0..<12 {
            let when = calendar.date(byAdding: .day, value: index, to: start)!
            ledger.record(report: readingReport(rate: Double(100 + index)), at: when)
        }
        let all = snapshot(ledger: ledger)
        #expect(all.readingRates == (2..<12).map { Double(100 + $0) })
        let covered = all.filtered(from: start, through: calendar.date(byAdding: .day, value: 11, to: start)!)
        #expect(covered.readingRates == (0..<12).map { Double(100 + $0) })

        var totalsOnly = StruggleLedger()
        totalsOnly.recentSpeechRates = Array(1...10).map(Double.init)
        let picture = snapshot(ledger: totalsOnly)
        #expect(picture.readingRates == Array(1...10).map(Double.init))
        let empty = picture.filtered(from: date(2026, 10, 1), through: date(2026, 10, 5))
        #expect(empty.readingRates.isEmpty)
    }

    @Test("turns and talks keep every recording on the inclusive days, oldest first")
    func inclusiveDays() {
        let first = recording(.conversation, on: date(2026, 10, 1, 9), lines: [
            ("Time spoken", "0m 4s"),
            ("Your turns", "2"),
        ])
        let morning = recording(.conversation, on: date(2026, 10, 2, 9), lines: [
            ("Time spoken", "0m 10s"),
            ("Your turns", "2"),
        ])
        let evening = recording(.conversation, on: date(2026, 10, 2, 23), lines: [
            ("Time spoken", "0m 6s"),
            ("Your turns", "1"),
        ])
        let next = recording(.conversation, on: date(2026, 10, 3, 1), lines: [
            ("Time spoken", "0m 8s"),
            ("Your turns", "1"),
        ])
        let hidden = recording(.conversation, on: date(2026, 10, 2, 12), lines: [
            ("Time spoken", "0m 50s"),
            ("Your turns", "1"),
        ], inLibrary: false)
        let talkFirst = recording(.monologue, on: date(2026, 10, 1, 8), lines: [
            ("Take 1", "1m"),
            ("Silent gaps ≥250 ms", "4"),
        ])
        let talkMorning = recording(.monologue, on: date(2026, 10, 2, 10), lines: [
            ("Take 1", "1m"),
            ("Silent gaps ≥250 ms", "2"),
        ])
        let talkEvening = recording(.monologue, on: date(2026, 10, 2, 18), lines: [
            ("Take 1", "1m"),
            ("Silent gaps ≥250 ms", "3"),
        ])
        let talkNext = recording(.monologue, on: date(2026, 10, 3, 2), lines: [
            ("Take 1", "1m"),
            ("Silent gaps ≥250 ms", "9"),
        ])
        let picture = snapshot(recordings: [
            next, evening, hidden, talkNext, first, talkEvening, morning, talkFirst, talkMorning,
        ])
        #expect(picture.turns.map(\.secondsPerTurn) == [2, 5, 6, 8])
        #expect(picture.talks.map(\.pauseFrequency) == [[4], [2], [3], [9]])

        let window = picture.filtered(from: date(2026, 10, 1), through: date(2026, 10, 2))
        #expect(window.turns.map(\.secondsPerTurn) == [2, 5, 6])
        #expect(window.talks.map(\.pauseFrequency) == [[4], [2], [3]])
        #expect(window.practicedDays == picture.practicedDays)

        let oneDay = picture.filtered(from: date(2026, 10, 2, 1), through: date(2026, 10, 2, 20))
        #expect(oneDay.turns.map(\.secondsPerTurn) == [5, 6])
        #expect(oneDay.talks.map(\.pauseFrequency) == [[2], [3]])
    }

    private func readingReport(rate: Double) -> SessionReport {
        SessionReport(
            passageID: "p1",
            passageTitle: "Test",
            marks: [],
            matchCount: 1,
            skipCount: 0,
            extraCount: 0,
            substituteCount: 0,
            speechRateSyllablesPerMinute: rate,
            averageSpeechRateSyllablesPerMinute: nil,
            durationSeconds: 10,
            missedPhoneTags: [],
            engineKind: "dictationTranscriber"
        )
    }
}
