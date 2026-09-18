import Foundation
import Observation
import SpeechAppKit

@MainActor
@Observable
final class AppModel {
    enum Route: Equatable {
        case consent
        case availability
        case library
        case reading
        case report(SessionReport)
    }

    var route: Route = .consent
    var catalog = PassageCatalog.loadBundled()
    var ledger = StruggleLedgerStore.loadOrCreate()
    var currentPassage: Passage?
    var speechEngineKind: LiveTranscriptionEngine.EngineKind = .unknown
    var availabilityMessage: String = ""

    func acceptConsent() {
        route = .availability
    }

    func openLibrary() {
        route = .library
    }

    func beginSuggestedReading() {
        currentPassage = NextPassagePicker.pick(catalog: catalog, ledger: ledger)
        route = .reading
    }

    func selectPassage(_ passage: Passage) {
        currentPassage = passage
        route = .reading
    }

    /// Kept for older call sites — opens the library so you can choose length/variant.
    func beginReading() {
        route = .library
    }

    func finish(report: SessionReport) {
        ledger.record(report: report)
        StruggleLedgerStore.save(ledger)
        route = .report(report)
    }

    func readAgain() {
        if currentPassage == nil {
            currentPassage = NextPassagePicker.pick(catalog: catalog, ledger: ledger)
        }
        route = .reading
    }

    func chooseAnotherPassage() {
        route = .library
    }
}
