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

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 15))!
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
        #expect(picture.talks.map(\.longSilences) == [[4, 2]])
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
}
