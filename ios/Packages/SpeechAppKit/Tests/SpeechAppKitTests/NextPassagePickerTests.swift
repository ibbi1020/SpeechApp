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

    @Test("round-trips through JSON encode/decode")
    func codableRoundTrip() throws {
        var ledger = StruggleLedger()
        ledger.phones = [PhoneStruggle(phone: "r", flBand: .high, missCount: 2)]
        let data = try JSONEncoder().encode(ledger)
        let decoded = try JSONDecoder().decode(StruggleLedger.self, from: data)
        #expect(decoded.phones == ledger.phones)
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
