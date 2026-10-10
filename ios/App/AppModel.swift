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
        case report(SessionReport, recordingID: UUID?)
        case conversation
        case conversationReport(ConversationReport)
        case monologue
        case monologueReport(MonologueReport, regimenID: UUID?)
        case recordings(filter: RecordingManifest.Format?)
        case crisis
    }

    /// Which format owns the crisis screen.
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

    func finish(report: SessionReport, recordingID: UUID? = nil) {
        ledger.record(report: report)
        StruggleLedgerStore.save(ledger)
        route = .report(report, recordingID: recordingID)
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

    func finishMonologue(
        report: MonologueReport,
        possibleMinorFlag: Bool = false,
        regimenID: UUID? = nil
    ) {
        notePossibleMinorIfNeeded(possibleMinorFlag)
        if report.kind == .crisis {
            route = .crisis
            return
        }
        route = .monologueReport(report, regimenID: regimenID)
    }

    func openRecordings(filter: RecordingManifest.Format? = nil) {
        route = .recordings(filter: filter)
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
