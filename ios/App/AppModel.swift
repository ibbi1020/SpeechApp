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
        case conversationReport(ConversationReport, recordingID: UUID?)
        case monologue
        case monologueReport(MonologueReport, regimenID: UUID?, topic: String)
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
        case home, ceremony
    }

    init() {
        TakeRetention.discardTakesLeftFromLastLaunch()
        sitting = Self.loadSitting()
        closeExerciseLeftFromLastLaunch()
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

    /// The Home entrance plays once, the first time Home is actually shown.
    /// Separate from `hasBegunBefore`, which only flips when a session starts.
    /// The earlier key was stored while this motion still ran under the splash,
    /// so this name lets that install play the visible entrance once.
    var hasPlayedHomeEntrance = UserDefaults.standard.bool(forKey: AppModel.homeEntranceKey)

    private static let homeEntranceKey = "entry.homeEntranceSeen"

    var needsHomeEntrance: Bool { !hasPlayedHomeEntrance }

    var entry: EntrySurface = .home

    /// Where the user is inside the ceremony. Ignored while `entry` is `.home`.
    var ceremonyStep: CeremonyStep = Ceremony.first

    /// The exercise the user settled on. Nil until the exercise step proposes one.
    var chosenKind: PracticeFormat.Kind?

    /// Sessions in the last 7 days. Filled when the ceremony begins.
    var weeklyCounts = WeeklyPracticeCounts()

    /// Set when a ceremony finishes. Later exercises do not move its clock.
    private var sitting = PracticeSitting()

    /// Breath and hum run when this sitting is closed. Read at the tap, so a
    /// half hour that ends while the exercise step is on screen is honored.
    var runsGrounding: Bool {
        sitting.needsGrounding(at: Date())
    }

    var isInCeremony: Bool { entry == .ceremony }

    /// Home opens the gallery full screen. The sheet clears this after it opens.
    var presentGallery = false

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
        noteExerciseStarted()
        route = .reading
    }

    func finish(report: SessionReport, recordingID: UUID? = nil) {
        noteExerciseEnded()
        ledger.record(report: report)
        StruggleLedgerStore.save(ledger)
        route = .report(report, recordingID: recordingID)
    }

    func finishConversation(
        report: ConversationReport,
        possibleMinorFlag: Bool = false,
        recordingID: UUID? = nil
    ) {
        noteExerciseEnded()
        notePossibleMinorIfNeeded(possibleMinorFlag)
        if report.kind == .crisis {
            route = .crisis
            return
        }
        route = .conversationReport(report, recordingID: recordingID)
    }

    func presentCrisis(possibleMinorFlag: Bool = false) {
        noteExerciseEnded()
        notePossibleMinorIfNeeded(possibleMinorFlag)
        route = .crisis
    }

    /// A tap on the island foregrounds the app. It does not start a new conversation,
    /// and it does not leave a report or the crisis screen.
    func openFromLiveActivity(_ url: URL) {
        guard ConversationLiveActivityLink.conversationID(from: url) != nil else { return }
    }

    func readAgain() {
        if currentPassage == nil {
            currentPassage = NextPassagePicker.pick(catalog: catalog, ledger: ledger)
        }
        noteBegun()
        noteExerciseStarted()
        route = .reading
    }

    func chooseAnotherPassage() {
        noteExerciseEnded()
        route = .library
    }

    func goHome() {
        noteExerciseEnded()
        entry = .home
        route = .home
    }

    func beginCeremony() {
        ceremonyStep = Ceremony.first
        chosenKind = nil
        weeklyCounts = weeklyPracticeCounts()
        entry = .ceremony
        route = .home
        Task { await refreshBudget() }
    }

    /// Asks the mint server how many conversations are left. A down server leaves the last snapshot.
    func refreshBudget() async {
        guard let client = MintClient.makeIfConfigured(uuid: account.accountUUID) else { return }
        guard let snapshot = try? await client.budget() else { return }
        budget = snapshot
    }

    func advanceCeremony() {
        guard let next = Ceremony.next(after: ceremonyStep) else { return }
        ceremonyStep = next
    }

    /// Back through the ceremony. The first step returns home.
    func retreatCeremony() {
        if let previous = Ceremony.previous(before: ceremonyStep) {
            ceremonyStep = previous
        } else {
            goHome()
        }
    }

    /// Opens the chosen exercise. The hum does this after a grounding. The
    /// exercise step does it when this sitting is already open.
    func finishCeremony() {
        let kind = chosenKind ?? .conversation
        if kind == .conversation, budget.startEnabled == false { return }
        if runsGrounding {
            sitting = sitting.opened(at: Date())
            saveSitting()
        }
        start(kind)
    }

    /// Sessions in the last 7 days, for the exercise proposal.
    func weeklyPracticeCounts(now: Date = .now) -> WeeklyPracticeCounts {
        let manifests = (try? RecordingsService.store.list()) ?? []
        let stamps = manifests.map { PracticeStamp(format: $0.format, createdAt: $0.createdAt) }
        return ExerciseOfferMaker.counts(of: stamps, now: now)
    }

    /// Popping a pushed screen lands back on the root. The ceremony, if that's
    /// where the session started, is still the root's state.
    func dismissToEntry() {
        noteExerciseEnded()
        route = .home
        guard entry == .ceremony else { return }
        ceremonyStep = Ceremony.first
        chosenKind = nil
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

    func noteHomeEntrancePlayed() {
        guard !hasPlayedHomeEntrance else { return }
        hasPlayedHomeEntrance = true
        UserDefaults.standard.set(true, forKey: Self.homeEntranceKey)
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
        noteExerciseStarted()
        route = .monologue
    }

    func finishMonologue(
        report: MonologueReport,
        possibleMinorFlag: Bool = false,
        regimenID: UUID? = nil,
        topic: String = ""
    ) {
        noteExerciseEnded()
        notePossibleMinorIfNeeded(possibleMinorFlag)
        if report.kind == .crisis {
            route = .crisis
            return
        }
        route = .monologueReport(report, regimenID: regimenID, topic: topic)
    }

    /// Leaves the exercise and opens the home gallery. Not the old recordings list.
    func showGallery() {
        goHome()
        presentGallery = true
    }

    func startConversation() {
        guard budget.startEnabled else { return }
        noteBegun()
        noteExerciseStarted()
        route = .conversation
    }

    /// The app went to the background. A later cold launch treats an exercise
    /// that was still open as having ended here.
    func rememberBackground() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.backgroundedKey)
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

    private static let sittingStartedKey = "ceremony.sitting.startedAt"
    private static let exerciseStartedKey = "ceremony.sitting.exerciseStartedAt"
    private static let exerciseEndedKey = "ceremony.sitting.exerciseEndedAt"
    private static let backgroundedKey = "ceremony.sitting.backgroundedAt"

    private func noteExerciseStarted() {
        sitting = sitting.startedExercise(at: Date())
        saveSitting()
    }

    private func noteExerciseEnded() {
        let next = sitting.endedExercise(at: Date())
        guard next != sitting else { return }
        sitting = next
        saveSitting()
    }

    /// A killed launch comes back on Home with the exercise still marked open.
    /// Close it at the moment the app last backgrounded.
    private func closeExerciseLeftFromLastLaunch() {
        guard let exerciseStartedAt = sitting.exerciseStartedAt else { return }
        if let exerciseEndedAt = sitting.exerciseEndedAt, exerciseEndedAt >= exerciseStartedAt { return }
        let ended = Self.storedDate(Self.backgroundedKey) ?? exerciseStartedAt
        sitting = sitting.endedExercise(at: ended)
        saveSitting()
    }

    private func saveSitting() {
        Self.store(sitting.startedAt, key: Self.sittingStartedKey)
        Self.store(sitting.exerciseStartedAt, key: Self.exerciseStartedKey)
        Self.store(sitting.exerciseEndedAt, key: Self.exerciseEndedKey)
    }

    private static func loadSitting() -> PracticeSitting {
        PracticeSitting(
            startedAt: storedDate(sittingStartedKey),
            exerciseStartedAt: storedDate(exerciseStartedKey),
            exerciseEndedAt: storedDate(exerciseEndedKey)
        )
    }

    private static func storedDate(_ key: String) -> Date? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key) != nil else { return nil }
        return Date(timeIntervalSince1970: defaults.double(forKey: key))
    }

    private static func store(_ date: Date?, key: String) {
        if let date {
            UserDefaults.standard.set(date.timeIntervalSince1970, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
