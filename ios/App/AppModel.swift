import Foundation
import Observation
import SpeechAppKit

@MainActor
@Observable
final class AppModel {
    enum Route: Equatable {
        case home
        case formats
        case library
        case reading
        case report(SessionReport, recordingID: UUID?)
        case conversation
        case conversationReport(ConversationReport, recordingID: UUID?)
        case monologue
        case monologueReport(MonologueReport, regimenID: UUID?)
        case recordings(filter: RecordingManifest.Format?)
        case crisis
    }

    /// Which format owns the crisis screen.
    enum HostedFormat: Equatable {
        case conversation, monologue
    }

    /// Which pre-session surface the navigation stack is rooted on. Held separately
    /// from `route` so popping a session returns to the screen it was started from.
    enum EntrySurface: Equatable {
        case home, formats
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

    /// Drives Home's two-word line. Set when a session actually starts, so
    /// "Once more" only ever appears to someone who has practised.
    var hasBegunBefore = UserDefaults.standard.bool(forKey: AppModel.hasBegunKey)

    private static let hasBegunKey = "entry.hasBegun"

    var entry: EntrySurface = .home

    var isChoosingFormat: Bool { entry == .formats }

    var featuredPassage: Passage? {
        NextPassagePicker.pick(catalog: catalog, ledger: ledger)
    }

    var morePassages: [Passage] {
        let featuredID = featuredPassage?.id
        return catalog.pickerPassages.filter { $0.id != featuredID }
    }

    func selectPassage(_ passage: Passage) {
        currentPassage = passage
        noteBegun()
        route = .reading
    }

    func finish(report: SessionReport, recordingID: UUID? = nil) {
        ledger.record(report: report)
        StruggleLedgerStore.save(ledger)
        route = .report(report, recordingID: recordingID)
    }

    func finishConversation(
        report: ConversationReport,
        possibleMinorFlag: Bool = false,
        recordingID: UUID? = nil
    ) {
        notePossibleMinorIfNeeded(possibleMinorFlag)
        if report.kind == .crisis {
            route = .crisis
            return
        }
        route = .conversationReport(report, recordingID: recordingID)
    }

    func presentCrisis(possibleMinorFlag: Bool = false) {
        notePossibleMinorIfNeeded(possibleMinorFlag)
        route = .crisis
    }

    func readAgain() {
        if currentPassage == nil {
            currentPassage = NextPassagePicker.pick(catalog: catalog, ledger: ledger)
        }
        noteBegun()
        route = .reading
    }

    func chooseAnotherPassage() {
        route = .library
    }

    func goHome() {
        entry = .home
        route = .home
    }

    func chooseFormat() {
        entry = .formats
        route = .formats
    }

    /// Popping a pushed screen lands back on whichever entry surface opened it.
    func dismissToEntry() {
        route = entry == .formats ? .formats : .home
    }

    func start(_ kind: PracticeFormat.Kind) {
        switch kind {
        case .reading: chooseAnotherPassage()
        case .monologue: requestStartMonologue()
        case .conversation: requestStartConversation()
        }
    }

    private func noteBegun() {
        guard !hasBegunBefore else { return }
        hasBegunBefore = true
        UserDefaults.standard.set(true, forKey: Self.hasBegunKey)
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
        noteBegun()
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
        noteBegun()
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
