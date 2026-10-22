import AVFoundation
import Combine
import os
import SwiftUI
import SpeechAppKit

struct ConversationSessionView: View {
    private static let log = Logger(subsystem: "com.speechapp", category: "ConversationSessionView")

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var session: ConversationSession?
    @State private var fakeMouth: FakeConversationMouth?
    @State private var mint: MintClient?
    @State private var conversationID = UUID()
    @State private var didMint = false
    @State private var didPostStarted = false
    @State private var didPostEnded = false
    @State private var errorMessage: String?
    @State private var canRetry = true
    @State private var showStopConfirm = false
    @State private var didRouteFinish = false
    @State private var eventPump: Task<Void, Never>?
    @State private var debugLoop: Task<Void, Never>?
    @State private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    /// Agent audio in flight (`audioDelta` until `responseDone`).
    @State private var agentSpeaking = false
    @State private var floor = ConversationFloor()
    @State private var mouth: (any ConversationMouth)?
    @State private var speechEnergy: Float = 0
    @State private var partnerEnergy: Float = 0
    @State private var levelTask: Task<Void, Never>?
    @State private var listenBack: ConversationListenBack?
    @State private var ambientPlace = AmbientPreference().place
    @State private var voiceID = VoicePreference().voiceID
    @State private var showVoicePicker = false
    @State private var islandStartedAt: Date?
    /// When the connecting orb appeared. The slow line and the hang share this clock.
    @State private var connectingStarted: Date?
    @State private var islandPauseBegan: Date?
    @State private var islandPausedAccumulated: TimeInterval = 0

    private var phase: ConversationPhase {
        session?.phase ?? .idle
    }

    private var isPaused: Bool {
        phase == .paused
    }

    private var showsFailure: Bool {
        errorMessage != nil
    }

    private var showsControls: Bool {
        guard !showsFailure else { return false }
        switch phase {
        case .connecting, .talking, .paused, .wrapping:
            return true
        default:
            return false
        }
    }

    private var showPauseControl: Bool {
        phase.showsPauseButton
    }

    private var orbPhase: VoiceOrb.Phase {
        .conversation(
            phase: phase,
            isCountdown: false,
            floor: floor.owner,
            agentSpeaking: agentSpeaking
        )
    }

    var body: some View {
        ZStack {
            SpeechScreenBackground()

            if showsFailure {
                failureView
            } else {
                liveCanvas
                    .safeAreaBar(edge: .bottom, spacing: 0) {
                        bottomChrome
                    }
                    .accessibilityHidden(showStopConfirm)
                    .allowsHitTesting(!showStopConfirm)
                    // The stop card does not sit on a flat scrim: the conversation
                    // behind it blurs and dims as one layer.
                    .blurBackdrop(showStopConfirm)
            }

            if showStopConfirm {
                SessionStopModal(
                    title: "Stop this conversation?",
                    confirmTitle: "Stop",
                    dismissTitle: "Keep talking",
                    onConfirm: {
                        showStopConfirm = false
                        Task { await confirmStop() }
                    },
                    onDismiss: { showStopConfirm = false }
                )
                .transition(SpeechBlur.dissolve)
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsControls && !showStopConfirm {
                VStack(alignment: .trailing, spacing: 12) {
                    ambientMenu
                    voiceButton
                    AIPartnerBadge()
                }
                .padding(.trailing, 16)
                .padding(.top, 12)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle, value: phase)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle, value: showStopConfirm)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .speechBarChrome()
        .speechBottomBlur(bar: false)
        .navigationSubtitle("\(model.budget.label) used this month")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                SpeechBarButton(systemName: "chevron.left", label: "Back") {
                    dismiss()
                }
            }
        }
        .toolbar(showStopConfirm || showsFailure ? .hidden : .automatic, for: .navigationBar)
        .background {
            NavigationPopLock(isLocked: showStopConfirm)
        }
        .task {
            VoiceOrbPreloader.warmup()
            installIslandStop()
            await beginSession()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            Task { await onWallClockTick() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { note in
            handleRouteChange(note)
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { note in
            if SessionInterruption.shouldPause(note) {
                session?.pause()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhase(phase)
        }
        .onChange(of: phase) { old, new in
            noteIslandClock(from: old, to: new)
            routeIfFinished()
            syncAmbient()
            Task { await syncIsland() }
        }
        .onChange(of: session?.countsAsBudgetStart) { _, started in
            if started == true, islandStartedAt == nil {
                islandStartedAt = Date()
            }
            Task { await syncIsland() }
        }
        .onChange(of: session?.stageLine) { _, _ in
            Task { await syncIsland() }
        }
        .onChange(of: floor) { _, _ in
            Task { await syncIsland() }
        }
        .onChange(of: agentSpeaking) { _, _ in
            Task { await syncIsland() }
        }
        .sheet(isPresented: $showVoicePicker) {
            PartnerVoiceSheet(selection: voiceID) { id in
                selectVoice(id)
            }
        }
        .onDisappear {
            Task {
                await syncIsland(leaving: true)
                ConversationLiveActivityController.shared.releaseStop()
            }
            tearDownIfLeaving()
        }
    }

    private var liveCanvas: some View {
        ZStack {
            if isPaused {
                Text("Paused — still here.")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, SpeechSpacing.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var voiceButton: some View {
        Button {
            showVoicePicker = true
        } label: {
            Image(systemName: "music.note")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Voice")
        .accessibilityValue(PartnerVoice.named(voiceID)?.name ?? voiceID)
    }

    private var failureView: some View {
        VStack(spacing: SpeechSpacing.related) {
            Text(errorMessage ?? UserFacingFailure.connectionDropped)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if canRetry {
                Button("Try again") {
                    Task { await retrySession() }
                }
                .buttonStyle(SpeechPrimaryButtonStyle(showsTint: true))
            }

            Button("Back to home") {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
                    model.goHome()
                }
            }
            .buttonStyle(SpeechSecondaryButtonStyle())
        }
        .padding(SpeechSpacing.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bottomChrome: some View {
        actionRow
            .padding(.horizontal, SpeechSpacing.page)
            .padding(.top, 12)
            .padding(.bottom, 16)
    }

    @ViewBuilder
    private var actionRow: some View {
        if showsControls {
            liveControlRow
        }
    }

    private var liveControlRow: some View {
        VStack(spacing: 4) {
            SpeechSubtitle(text: session?.subtitleLine ?? "")
            conversationOrbBar
        }
    }

    /// Background bed. Sits with the voice button at the top trailing edge.
    private var ambientMenu: some View {
        Menu {
            ForEach(AmbientPlace.allCases, id: \.self) { place in
                Button {
                    selectAmbient(place)
                } label: {
                    if place == ambientPlace {
                        Label(place.title, systemImage: "checkmark")
                    } else {
                        Text(place.title)
                    }
                }
            }
        } label: {
            Image(systemName: ambientPlace == .off ? "speaker.slash" : "speaker.wave.2")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Background")
        .accessibilityValue(ambientPlace.title)
    }

    private func selectAmbient(_ place: AmbientPlace) {
        ambientPlace = place
        AmbientPreference().place = place
        syncAmbient()
    }

    private func selectVoice(_ id: String) {
        let resolved = PartnerVoice.canonical(id)
        voiceID = resolved
        VoicePreference().voiceID = resolved
        let mouth = mouth
        Task { await mouth?.updateVoice(resolved) }
    }

    /// The bed follows the phase. Picking a place does not pause the clock.
    private func syncAmbient() {
        let command = AmbientBedPolicy.command(place: ambientPlace, phase: phase)
        let mouth = mouth
        switch command {
        case .play(let place):
            Task { await mouth?.setAmbient(place: place, playing: true) }
        case .stop:
            Task { await mouth?.setAmbient(place: ambientPlace, playing: false) }
        }
    }

    private var conversationOrbBar: some View {
        SessionOrbBar(
            phase: orbPhase,
            connectingStarted: phase == .connecting ? connectingStarted : nil,
            inputVolume: orbPhase == .listening ? speechEnergy : 0,
            outputVolume: orbPhase == .speaking ? partnerEnergy : 0,
            animating: !isPaused
        ) {
            Button {
                if isPaused {
                    session?.resume()
                } else {
                    session?.pause()
                }
            } label: {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .speechGlassCircle()
            }
            .buttonStyle(.plain)
            .opacity(showPauseControl ? 1 : 0)
            .allowsHitTesting(showPauseControl)
            .accessibilityHidden(!showPauseControl)
            .accessibilityLabel(isPaused ? "Resume" : "Pause")
        } trailing: {
            Button {
                session?.requestStop()
                showStopConfirm = true
            } label: {
                Image(systemName: "stop.fill")
                    .speechGlassCircle(tint: .red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop")
        }
    }

    private func beginSession() async {
        guard session == nil else { return }
        errorMessage = nil
        canRetry = true
        didRouteFinish = false
        conversationID = UUID()
        didMint = false
        didPostStarted = false
        didPostEnded = false
        agentSpeaking = false
        floor = ConversationFloor()
        speechEnergy = 0
        partnerEnergy = 0

        do {
            let built = try makeSession()
            session = built.session
            mouth = built.mouth
            fakeMouth = built.fake
            mint = built.mint
            startEventPump(session: built.session, mouth: built.mouth)
            startLevelPump()
            await startListenBack(session: built.session, mouth: built.mouth)

            let started = Date()
            connectingStarted = started
            built.session.enterConnecting()

            let prepareTask = Task {
                try await built.mouth.prepare()
            }
            try Task.checkCancellation()
            try await prepareTask.value

            if let apiKey = XAIDirectKey.load() {
                do {
                    try await built.session.countdownReachedZero(
                        ephemeralKey: apiKey,
                        timeout: ConnectionWaitPolicy.remaining(since: started, now: Date())
                    )
                } catch {
                    await built.session.handle(.failed)
                    throw error
                }
            } else if let fake = built.fake {
                try await built.session.countdownReachedZero(ephemeralKey: "debug")
                try await Task.sleep(for: .milliseconds(300))
                try Task.checkCancellation()
                fake.emit(.ready)
                fake.emit(.responseStarted)
                fake.emit(.audioDelta)
                #if DEBUG
                startDebugUserLoop(session: built.session, mouth: fake)
                #endif
            } else {
                throw ConversationSessionError.missingAPIKey
            }
        } catch is CancellationError {
            await mouth?.close()
            await postEndedIfNeeded()
        } catch {
            await mouth?.close()
            await postEndedIfNeeded()
            if let mintError = error as? MintError, mintError == .budget {
                model.budget.used = model.budget.limit
                canRetry = false
            }
            UserFacingFailure.log(error, context: "conversation start")
            errorMessage = ShownError.text(for: error)
            clearLiveSession()
        }
    }

    private func retrySession() async {
        await postEndedIfNeeded()
        clearLiveSession()
        errorMessage = nil
        canRetry = true
        await beginSession()
    }

    /// Records the user's side for the report player (live mouth only).
    private func startListenBack(session: ConversationSession, mouth: any ConversationMouth) async {
        listenBack?.discard()
        listenBack = nil
        guard RecordingsService.keepRecordings,
              let live = mouth as? LiveConversationMouth,
              let apiKey = XAIDirectKey.load()
        else { return }
        let recorder = ConversationListenBack(mouth: live, apiKey: apiKey)
        recorder.onLanguageSlip = { end in
            session.noteOtherLanguageSpan(end: end)
        }
        listenBack = recorder
        await recorder.start {
            session.phase == .talking || session.phase == .wrapping
        }
    }

    private func clearLiveSession() {
        listenBack?.discard()
        listenBack = nil
        connectingStarted = nil
        eventPump?.cancel()
        eventPump = nil
        levelTask?.cancel()
        levelTask = nil
        debugLoop?.cancel()
        debugLoop = nil
        session = nil
        mouth = nil
        fakeMouth = nil
        mint = nil
    }

    /// Mouth owns the mic and partner audio; the orb reads both levels.
    private func startLevelPump() {
        levelTask?.cancel()
        levelTask = Task { @MainActor in
            while !Task.isCancelled {
                switch orbPhase {
                case .listening:
                    let level = await mouth?.currentInputLevel() ?? 0
                    if Task.isCancelled { return }
                    let next = ListenDrive.normalized(rms: level)
                    if abs(next - speechEnergy) >= 0.008 {
                        speechEnergy = next
                    }
                case .speaking:
                    let level = await mouth?.currentOutputLevel() ?? 0
                    if Task.isCancelled { return }
                    let next = ListenDrive.normalized(rms: level)
                    if abs(next - partnerEnergy) >= 0.008 {
                        partnerEnergy = next
                    }
                default:
                    break
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func makeSession() throws -> SessionStart {
        let deck = try StanceDeck.loadBundled()
        let bank = try OpenPromptBank.loadBundled()
        guard !bank.prompts.isEmpty else {
            throw ConversationSessionError.missingOpens
        }

        var rng = SplitMix64(seed: UInt64.random(in: 1...UInt64.max))
        let stance = deck.sample(rng: &rng).views.joined(separator: "\n")
        let openQuestion = bank.prompts[Int(rng.next() % UInt64(bank.prompts.count))]
        let client = MintClient.makeIfConfigured(uuid: model.account.accountUUID)
        let mouth: any ConversationMouth
        let fake: FakeConversationMouth?
        if XAIDirectKey.load() != nil {
            mouth = LiveConversationMouth(voiceID: voiceID)
            fake = nil
        } else {
            let prototype = FakeConversationMouth()
            mouth = prototype
            fake = prototype
        }

        let cap: TimeInterval = 15 * 60

        let session = ConversationSession(
            time: SystemTimeSource(),
            mouth: mouth,
            cap: cap,
            prefix: FrozenPersona.prefix,
            stance: stance,
            openQuestion: openQuestion
        )
        return SessionStart(
            session: session,
            mouth: mouth,
            fake: fake,
            mint: client
        )
    }

    private func startEventPump(session: ConversationSession, mouth: any ConversationMouth) {
        eventPump?.cancel()
        eventPump = Task { @MainActor in
            for await event in mouth.events {
                switch event {
                case .responseStarted, .audioDelta:
                    agentSpeaking = true
                case .responseDone:
                    agentSpeaking = false
                default:
                    break
                }
                floor.apply(event)
                await session.handle(event)
                await postStartedIfNeeded(session)
                routeIfFinished()
            }
        }
    }

    #if DEBUG
    private func startDebugUserLoop(session: ConversationSession, mouth: FakeConversationMouth) {
        debugLoop?.cancel()
        debugLoop = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled, session.phase == .talking else { continue }
                mouth.emit(.speechStarted)
                await session.handle(.speechStarted)
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, session.phase == .talking else { continue }
                session.ingestUserText("hello")
                session.noteUserSpeech(seconds: 1)
                mouth.emit(.speechStopped)
            }
        }
    }
    #endif

    private func postStartedIfNeeded(_ session: ConversationSession) async {
        guard session.countsAsBudgetStart, !didPostStarted, let mint else { return }
        didPostStarted = true
        do {
            let remaining = try await mint.started(sessionID: conversationID)
            model.budget.used = max(0, model.budget.limit - remaining)
        } catch MintError.budget {
            model.budget.used = model.budget.limit
        } catch {
            // Keep talking; budget is recorded on the next successful started.
        }
    }

    private func postEndedIfNeeded() async {
        guard didMint, !didPostEnded, let mint else { return }
        didPostEnded = true
        try? await mint.ended()
    }

    private func onWallClockTick() async {
        await session?.tick()
        routeIfFinished()
    }

    private func installIslandStop() {
        guard let session else { return }
        ConversationLiveActivityController.shared.bindStop {
            await session.confirmStop()
            routeIfFinished()
        }
        ConversationLiveActivityController.shared.bindPause {
            if session.phase == .paused {
                session.resume()
            } else {
                session.pause()
            }
        }
    }

    private func noteIslandClock(from old: ConversationPhase, to new: ConversationPhase) {
        if session?.countsAsBudgetStart == true, islandStartedAt == nil {
            islandStartedAt = Date()
        }
        if new == .paused, old != .paused {
            islandPauseBegan = Date()
        }
        if old == .paused, new != .paused, let began = islandPauseBegan {
            islandPausedAccumulated += Date().timeIntervalSince(began)
            islandPauseBegan = nil
        }
    }

    private func syncIsland(leaving: Bool = false) async {
        installIslandStop()
        let input = ConversationLiveActivityInput(
            exercise: .conversation,
            phase: phase,
            floor: floor.owner,
            agentSpeaking: agentSpeaking,
            startedAt: islandStartedAt,
            pausedAccumulated: islandPausedAccumulated,
            pauseBeganAt: islandPauseBegan,
            phrase: session?.stageLine ?? "",
            phraseIsPartner: true,
            activityIsLive: ConversationLiveActivityController.shared.isLive,
            leaving: leaving
        )
        await ConversationLiveActivityController.shared.sync(input, id: conversationID)
    }

    private func handleRouteChange(_ note: Notification) {
        let raw: UInt
        if let value = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt {
            raw = value
        } else if let number = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber {
            raw = number.uintValue
        } else {
            return
        }
        if ConversationRoutePause.shouldPause(reason: raw) {
            session?.pause()
        }
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            beginConversationBackgroundTask()
        case .active:
            endConversationBackgroundTask()
            ConversationLiveActivityController.shared.allowStart()
            Task { await syncIsland() }
        default:
            break
        }
    }

    private func beginConversationBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "conversation-tick") {
            Task { @MainActor in
                endConversationBackgroundTask()
            }
        }
    }

    private func endConversationBackgroundTask() {
        let identifier = backgroundTask
        backgroundTask = .invalid
        if identifier != .invalid {
            UIApplication.shared.endBackgroundTask(identifier)
        }
    }

    private func confirmStop() async {
        debugLoop?.cancel()
        await session?.confirmStop()
        await ConversationLiveActivityController.shared.end()
        routeIfFinished()
    }

    private func routeIfFinished() {
        guard !didRouteFinish, let session else { return }
        switch session.phase {
        case .crisis:
            listenBack?.discard()
            listenBack = nil
            markRoutedAndPostEnded()
            model.presentCrisis(possibleMinorFlag: session.possibleMinorFlag)
        case .report, .dropped:
            guard let report = session.report else { return }
            Self.log.info(
                "conversation end reason=\(String(describing: report.endReason), privacy: .public) turns=\(report.userTurns) present=\(session.shouldPresentReport)"
            )
            if !session.shouldPresentReport {
                listenBack?.discard()
                listenBack = nil
                if errorMessage == nil {
                    errorMessage = UserFacingFailure.connectionDropped
                    canRetry = true
                }
                markRoutedAndPostEnded()
                return
            }
            markRoutedAndPostEnded()
            let recordingID = report.kind == .crisis ? nil : listenBack?.finish(report: report)
            if recordingID == nil { listenBack?.discard() }
            listenBack = nil
            model.finishConversation(
                report: report,
                possibleMinorFlag: session.possibleMinorFlag,
                recordingID: recordingID
            )
        default:
            break
        }
    }

    private func markRoutedAndPostEnded() {
        didRouteFinish = true
        Task { await postEndedIfNeeded() }
    }

    private func tearDownIfLeaving() {
        eventPump?.cancel()
        eventPump = nil
        levelTask?.cancel()
        levelTask = nil
        debugLoop?.cancel()
        debugLoop = nil
        endConversationBackgroundTask()

        switch model.route {
        case .conversationReport, .crisis:
            Task { await postEndedIfNeeded() }
            return
        default:
            break
        }

        didRouteFinish = true
        listenBack?.discard()
        listenBack = nil
        Task { await postEndedIfNeeded() }
        guard let session else { return }
        switch session.phase {
        case .idle, .report, .crisis, .dropped:
            break
        default:
            Task { await session.confirmStop() }
        }
    }
}

private struct SessionStart {
    let session: ConversationSession
    let mouth: any ConversationMouth
    let fake: FakeConversationMouth?
    let mint: MintClient?
}

private enum ConversationSessionError: LocalizedError {
    case missingOpens
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .missingOpens, .missingAPIKey: UserFacingFailure.practiceDidNotStart
        }
    }
}
