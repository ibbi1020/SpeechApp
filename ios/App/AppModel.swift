import Foundation
import Observation
import SpeechAppKit

@MainActor
@Observable
final class AppModel {
    enum Route: Equatable {
        case home
        case library
        case reading
        case report(SessionReport)
        case conversation
        case conversationReport(ConversationReport)
        case crisis
        case ageGate
    }

    var route: Route = .home
    var catalog = PassageCatalog.loadBundled()
    var ledger = StruggleLedgerStore.loadOrCreate()
    var currentPassage: Passage?
    var speechEngineKind: LiveTranscriptionEngine.EngineKind = .unknown
    var budget = ConversationBudgetSnapshot(
        limit: 20,
        used: 0,
        month: currentCalendarMonth()
    )

    var featuredPassage: Passage? {
        NextPassagePicker.pick(catalog: catalog, ledger: ledger)
    }

    var morePassages: [Passage] {
        let featuredID = featuredPassage?.id
        return catalog.pickerPassages.filter { $0.id != featuredID }
    }

    func selectPassage(_ passage: Passage) {
        currentPassage = passage
        route = .reading
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

    func goHome() {
        route = .home
    }

    func startConversation() {
        route = .conversation
    }

    private static func currentCalendarMonth(now: Date = .now, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: now)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }
}
