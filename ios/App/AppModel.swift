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
    }

    /// Which format owns the crisis screen.
    enum HostedFormat: Equatable {
        case conversation, monologue
    }

    var hostedFormat: HostedFormat = .conversation

    var route: Route = .home
    /// Filled off the main thread right after launch (JSON decode + file read), so the
    /// first frame and the first taps never wait on disk.
    var catalog = PassageCatalog(passages: [])
    var ledger = StruggleLedger()
    private(set) var isLoaded = false
    private var ledgerChangedBeforeLoad = false
    private var ledgerSave: Task<Void, Never>?
    var currentPassage: Passage?
    var speechEngineKind: LiveTranscriptionEngine.EngineKind = .unknown
    var account = AccountStore()
    var budget = ConversationBudgetSnapshot(
        limit: 20,
        used: 0,
        month: currentCalendarMonth()
    )

    init() {
        Task { await loadStores() }
    }

    private func loadStores() async {
        let loaded = await Task.detached(priority: .userInitiated) {
            (PassageCatalog.loadBundled(), StruggleLedgerStore.loadOrCreate())
        }.value
        catalog = loaded.0
        if !ledgerChangedBeforeLoad {
            ledger = loaded.1
        }
        isLoaded = true
    }

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
        if !isLoaded { ledgerChangedBeforeLoad = true }
        route = .report(report)
        // Write the ledger off the main thread, one save after another.
        let snapshot = ledger
        let previous = ledgerSave
        ledgerSave = Task.detached(priority: .utility) {
            await previous?.value
            StruggleLedgerStore.save(snapshot)
        }
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
        startConversation()
    }

    func requestStartMonologue() {
        hostedFormat = .monologue
        startMonologue()
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

    private static func currentCalendarMonth(now: Date = .now, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: now)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }
}
