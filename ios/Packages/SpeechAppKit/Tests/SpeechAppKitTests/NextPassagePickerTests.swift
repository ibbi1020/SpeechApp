import Foundation
import Testing
@testable import SpeechAppKit

@Suite("StruggleLedger")
struct StruggleLedgerTests {
    @Test("records skips and speech rate")
    func recordReport() {
        var ledger = StruggleLedger()
        let report = SessionReport(
            passageID: "p1",
            passageTitle: "Test",
            marks: [
                LiveMarkCodable(kind: .skip, scriptWordID: "w0", message: "Skipped"),
                LiveMarkCodable(kind: .extra, spokenSurface: "um", message: "+um"),
            ],
            matchCount: 3,
            skipCount: 1,
            extraCount: 1,
            substituteCount: 0,
            speechRateSyllablesPerMinute: 140,
            averageSpeechRateSyllablesPerMinute: nil,
            durationSeconds: 10,
            missedPhoneTags: [MissedPhoneTag(phone: "ɪ", flBand: .high)],
            engineKind: "dictationTranscriber"
        )
        ledger.record(report: report)
        #expect(ledger.skipWords.count == 1)
        #expect(ledger.skipWords[0].count == 1)
        #expect(ledger.extras["um"] == 1)
        #expect(ledger.phones.first?.phone == "ɪ")
        #expect(ledger.recentSpeechRates == [140])
        #expect(ledger.seenPassageIDs == ["p1"])
    }

    @Test("record keeps the running totals and the 10-speed cap, and appends every dated event")
    func recordAppendsDatedEvents() {
        var ledger = StruggleLedger()
        let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
        for index in 0..<12 {
            let when = start.addingTimeInterval(Double(index) * 86_400)
            ledger.record(
                report: readingReport(
                    rate: Double(100 + index),
                    miss: index < 3 ? "ɪ" : nil,
                    skip: index < 4 ? "w0" : nil
                ),
                at: when
            )
        }
        #expect(ledger.recentSpeechRates == (2..<12).map { Double(100 + $0) })
        #expect(ledger.speechRateEvents.map(\.syllablesPerMinute) == (0..<12).map { Double(100 + $0) })
        #expect(ledger.speechRateEvents.map(\.date) == (0..<12).map {
            start.addingTimeInterval(Double($0) * 86_400)
        })
        #expect(ledger.phones.first?.missCount == 3)
        #expect(ledger.missEvents.count == 3)
        #expect(ledger.missEvents.map(\.date) == (0..<3).map {
            start.addingTimeInterval(Double($0) * 86_400)
        })
        #expect(ledger.skipWords.first?.count == 4)
        #expect(ledger.skipEvents.count == 4)
    }

    @Test("an old ledger JSON with no event arrays still loads its counts")
    func legacyLedgerJSON() throws {
        let saved = Date(timeIntervalSinceReferenceDate: 20)
        let legacy = StruggleLedger(
            phones: [PhoneStruggle(phone: "r", flBand: .high, missCount: 4, lastSession: saved)],
            skipWords: [SkipWordStruggle(wordId: "w0", surface: "ship", count: 3)],
            extras: ["um": 2],
            recentSpeechRates: [120, 130],
            seenPassageIDs: ["p1"]
        )
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String: Any]
        object.removeValue(forKey: "missEvents")
        object.removeValue(forKey: "skipEvents")
        object.removeValue(forKey: "speechRateEvents")
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(StruggleLedger.self, from: data)
        #expect(decoded.phones.first?.phone == "r")
        #expect(decoded.phones.first?.missCount == 4)
        #expect(decoded.skipWords.first?.count == 3)
        #expect(decoded.extras["um"] == 2)
        #expect(decoded.recentSpeechRates == [120, 130])
        #expect(decoded.seenPassageIDs == ["p1"])
        #expect(decoded.missEvents.isEmpty)
        #expect(decoded.skipEvents.isEmpty)
        #expect(decoded.speechRateEvents.isEmpty)
    }

    @Test("round-trips through JSON encode/decode")
    func codableRoundTrip() throws {
        var ledger = StruggleLedger()
        ledger.phones = [PhoneStruggle(phone: "r", flBand: .high, missCount: 2)]
        let when = Date(timeIntervalSinceReferenceDate: 30)
        ledger.missEvents = [PhoneMissEvent(phone: "r", flBand: .high, date: when)]
        ledger.skipEvents = [SkipEvent(wordId: "w0", surface: "ship", date: when)]
        ledger.speechRateEvents = [SpeechRateEvent(syllablesPerMinute: 140, date: when)]
        let data = try JSONEncoder().encode(ledger)
        let decoded = try JSONDecoder().decode(StruggleLedger.self, from: data)
        #expect(decoded.phones == ledger.phones)
        #expect(decoded.missEvents == ledger.missEvents)
        #expect(decoded.skipEvents == ledger.skipEvents)
        #expect(decoded.speechRateEvents == ledger.speechRateEvents)
    }

    private func readingReport(rate: Double, miss: String?, skip: String?) -> SessionReport {
        var marks: [LiveMarkCodable] = []
        if let skip {
            marks.append(LiveMarkCodable(kind: .skip, scriptWordID: skip, message: "Skipped"))
        }
        return SessionReport(
            passageID: "p1",
            passageTitle: "Test",
            marks: marks,
            matchCount: 1,
            skipCount: skip == nil ? 0 : 1,
            extraCount: 0,
            substituteCount: 0,
            speechRateSyllablesPerMinute: rate,
            averageSpeechRateSyllablesPerMinute: nil,
            durationSeconds: 10,
            missedPhoneTags: miss.map { [MissedPhoneTag(phone: $0, flBand: .high)] } ?? [],
            engineKind: "dictationTranscriber"
        )
    }
}

@Suite("NextPassagePicker")
struct NextPassagePickerTests {
    @Test("picks balanced default when ledger empty")
    func emptyLedger() {
        let catalog = PassageCatalog(passages: PassageCatalog.fallbackPassages)
        let pick = NextPassagePicker.pick(catalog: catalog, ledger: StruggleLedger())
        #expect(pick?.isBalancedDefault == true)
    }

    @Test("prefers passages covering high-FL missed phones")
    func prefersHighFL() {
        var ledger = StruggleLedger()
        ledger.phones = [PhoneStruggle(phone: "l", flBand: .high, missCount: 3)]
        // Also add contrast tag style miss that river light covers via phoneTags
        let catalog = PassageCatalog(passages: PassageCatalog.fallbackPassages)
        let pick = NextPassagePicker.pick(catalog: catalog, ledger: ledger)
        #expect(pick?.id == "l-r-1" || pick?.phoneTagsContain("l") == true)
    }

    @Test("empty bundled ledger features the long Harbor Morning")
    func emptyBundledLedgerPicksLongHarbor() {
        let catalog = PassageCatalog.loadBundled()
        let pick = NextPassagePicker.pick(catalog: catalog, ledger: StruggleLedger())
        #expect(pick?.family == "ship-sheep")
        #expect(pick?.length == .long)
    }
}

private extension Passage {
    func phoneTagsContain(_ phone: String) -> Bool {
        words.contains { $0.phoneTags.contains(phone) }
    }
}

@Suite("NotAssessedGOPScorer")
struct GOPScorerTests {
    @Test("always returns notAssessed")
    func stub() async {
        let scorer = NotAssessedGOPScorer()
        let word = ScriptWord(id: "1", surface: "ship")
        let result = await scorer.score(scriptWord: word, pcmSlice: [0.1, 0.2])
        #expect(result == .notAssessed)
    }

    @Test("specialized scorer stays notAssessed without a model")
    func specializedPending() async {
        let scorer = SpecializedSoundScorer()
        let word = ScriptWord(
            id: "1",
            surface: "ship",
            canonicalPhones: ["ʃ", "ɪ", "p"]
        )
        let result = await scorer.score(scriptWord: word, pcmSlice: Array(repeating: 0.1, count: 1600))
        #expect(result == .notAssessed)
    }
}

@Suite("PhoneLexicon")
struct PhoneLexiconTests {
    @Test("known words resolve to phones")
    func known() {
        #expect(PhoneLexicon.phones(for: "ship") == ["ʃ", "ɪ", "p"])
        #expect(PhoneLexicon.phones(for: "sheep") == ["ʃ", "i", "p"])
    }
}

@Suite("PassageCatalog")
struct PassageCatalogTests {
    @Test("bundled catalog includes full passages")
    func bundledLengths() {
        let catalog = PassageCatalog.loadBundled()
        #expect(catalog.passages.count >= 20)
        #expect(catalog.passages.contains { $0.length == .long })
        #expect(catalog.passages.contains { $0.family == "ship-sheep" && $0.length == .long })
        #expect(catalog.passages(inFamily: "ship-sheep").count >= 1)
        #expect(!catalog.passages[0].words[0].resolvedPhones.isEmpty)
    }

    @Test("pickerPassages keeps only full passages")
    func pickerPassagesFullOnly() {
        let catalog = PassageCatalog.loadBundled()
        let picker = catalog.pickerPassages
        #expect(!picker.isEmpty)
        #expect(picker.count >= 12)
        #expect(picker.allSatisfy { $0.length == .long })
        #expect(!picker.contains { $0.title.contains("\u{2014}") || $0.text.contains("\u{2014}") })
    }
}

@Suite("PCMStore")
struct PCMStoreTests {
    @Test("captures and slices then clears")
    func captureSliceClear() {
        let store = PCMStore()
        store.append(AudioChunk(samples: Array(repeating: 0.5, count: 100), sampleRate: 16_000, hostTime: 0))
        store.append(AudioChunk(samples: Array(repeating: -0.5, count: 100), sampleRate: 16_000, hostTime: 0.01))
        #expect(store.sampleCount == 200)
        let firstHalf = store.slice(startFraction: 0, endFraction: 0.5)
        #expect(firstHalf.count == 100)
        store.secureClear()
        #expect(store.sampleCount == 0)
    }
}
