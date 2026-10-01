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
        case monologue
        case monologueReport(MonologueReport)
        case crisis
        case ageGate
    }

    /// Which format owns age gate / crisis, and which to start after attestation.
    enum HostedFormat: Equatable {
        case conversation, monologue
    }

    var hostedFormat: HostedFormat = .conversation

    var route: Route = .home
    var catalog = PassageCatalog.loadBundled()
    var ledger = StruggleLedgerStore.loadOrCreate()
    var currentPassage: Passage?
    var speechEngineKind: LiveTranscriptionEngine.EngineKind = .unknown
    var account = AccountStore()
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

    func finishConversation(report: ConversationReport, possibleMinorFlag: Bool = false) {
        notePossibleMinorIfNeeded(possibleMinorFlag)
        if report.kind == .crisis {
            route = .crisis
            return
        }
        route = .conversationReport(report)
    }

    func presentCrisis(possibleMinorFlag: Bool = false) {
        notePossibleMinorIfNeeded(possibleMinorFlag)
        route = .crisis
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

    func requestStartConversation() {
        guard budget.startEnabled else { return }
        hostedFormat = .conversation
        if !account.attested18 {
            route = .ageGate
            return
        }
        continueAfterAgeGate()
    }

    func requestStartMonologue() {
        hostedFormat = .monologue
        if !account.attested18 {
            route = .ageGate
            return
        }
        continueAfterAgeGate()
    }

    func startMonologue() {
        route = .monologue
    }

    func finishMonologue(report: MonologueReport, possibleMinorFlag: Bool = false) {
        notePossibleMinorIfNeeded(possibleMinorFlag)
        if report.kind == .crisis {
            route = .crisis
            return
        }
        route = .monologueReport(report)
    }

    func confirmAgeAttestation() {
        account.attested18 = true
        continueAfterAgeGate()
    }

    func startConversation() {
        guard budget.startEnabled else { return }
        route = .conversation
    }

    private func notePossibleMinorIfNeeded(_ flagged: Bool) {
        guard flagged else { return }
        account.possibleMinorFlag = true
        guard let client = MintClient.makeIfConfigured(uuid: account.accountUUID) else { return }
        Task {
            await client.possibleMinor()
        }
    }

    private func continueAfterAgeGate() {
        switch hostedFormat {
        case .conversation:
            startConversation()
        case .monologue:
            startMonologue()
        }
    }

    private static func currentCalendarMonth(now: Date = .now, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: now)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }
}
