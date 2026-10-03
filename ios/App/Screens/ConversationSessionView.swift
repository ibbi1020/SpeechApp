import AVFoundation
import Combine
import os
import SwiftUI
import SpeechAppKit

struct ConversationSessionView: View {
    private static let log = Logger(subsystem: "com.speechapp", category: "ConversationSessionView")

    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var session: ConversationSession?
    @State private var fakeMouth: FakeConversationMouth?
    @State private var mint: MintClient?
    @State private var conversationID = UUID()
    @State private var didMint = false
    @State private var didPostStarted = false
    @State private var didPostEnded = false
    @State private var errorMessage: String?
    @State private var canRetry = true
    @State private var countdownRemaining: Int?
    @State private var showStopConfirm = false
    @State private var isStopping = false
    @State private var pauseThrottle = TapThrottle()
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

    private var phase: ConversationPhase {
        session?.phase ?? .idle
    }

    private var isPaused: Bool {
        phase == .paused
    }

    private var isFogged: Bool {
        countdownRemaining != nil
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
            isCountdown: isFogged,
            floor: floor.owner,
            agentSpeaking: agentSpeaking
        )
    }

    private var fogBlurRadius: CGFloat {
        isFogged && !reduceTransparency ? SpeechCountdown.fogBlurRadius : 0
    }

    private var fogWashOpacity: Double {
        guard isFogged else { return 0 }
        return reduceTransparency
            ? SpeechCountdown.reducedTransparencyWash
            : SpeechCountdown.fogWashOpacity
    }

    var body: some View {
        ZStack {
            SpeechScreenBackground()

            if showsFailure {
                failureView
            } else {
                liveCanvas
                    .blur(radius: fogBlurRadius)
                    .overlay {
                        Color.black.opacity(fogWashOpacity)
                            .allowsHitTesting(false)
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        bottomChrome
                    }
                    .accessibilityHidden(isFogged || showStopConfirm)
                    .allowsHitTesting(!isFogged && !showStopConfirm)
            }

            if isFogged {
                ReadingCountdownOverlay(
                    remaining: countdownRemaining,
                    instruction: "Take a deep breath. Talk when you're ready."
                )
            }

            if showStopConfirm {
                SessionStopModal(
                    title: "Stop this conversation?",
                    confirmTitle: "Stop",
                    dismissTitle: "Keep talking",
                    onConfirm: {
                        guard !isStopping else { return }
                        isStopping = true
                        showStopConfirm = false
                        Task { await confirmStop() }
                    },
                    onDismiss: { showStopConfirm = false }
                )
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle, value: isFogged)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle, value: phase)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle, value: showStopConfirm)
        .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.65), trigger: countdownRemaining)
        .navigationTitle("Conversation")
        .navigationSubtitle("\(model.budget.label) used this month")
        .navigationBarTitleDisplayMode(.inline)
        // Keep the bar during the stop modal (hiding it shifts the page); only the back button goes.
        .toolbar(showsFailure ? .hidden : .automatic, for: .navigationBar)
        .navigationBarBackButtonHidden(showStopConfirm || isStopping)
        .background {
            NavigationPopLock(isLocked: showStopConfirm)
        }
        .task {
            VoiceOrbPreloader.warmup()
            await beginSession()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            Task { await onWallClockTick() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { note in
            handleRouteChange(note)
        }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhase(phase)
        }
        .onChange(of: phase) { _, _ in
            routeIfFinished()
        }
        .onDisappear {
            tearDownIfLeaving()
        }
    }

    private var liveCanvas: some View {
        let line = session?.stageLine ?? ""
        return ZStack {
            if !line.isEmpty {
                Text(line)
                    .font(.system(.title3, design: .serif))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .foregroundStyle(isFogged ? .tertiary : .primary)
                    .lineLimit(4)
                    .truncationMode(.head)
                    .frame(maxWidth: 320)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 28)
                    .accessibilityLabel(line)
                    .accessibilityAddTraits(.updatesFrequently)
            }

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

    private var failureView: some View {
        VStack(spacing: SpeechSpacing.related) {
            Text(errorMessage ?? "Connection lost.")
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
        SessionOrbBar(
            phase: orbPhase,
            inputVolume: orbPhase == .listening ? speechEnergy : 0,
            outputVolume: orbPhase == .speaking ? partnerEnergy : 0,
            animating: !isPaused
        ) {
            Button {
                guard pauseThrottle.allow() else { return }
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
            .sensoryFeedback(.selection, trigger: isPaused)
            .accessibilityLabel(isPaused ? "Resume" : "Pause")
        } trailing: {
            Button {
                guard !isStopping else { return }
                session?.requestStop()
                showStopConfirm = true
            } label: {
                Image(systemName: "stop.fill")
                    .speechGlassCircle(tint: .red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop")
        }
        // While the stop card is up, only its two buttons exist for VoiceOver and UI tests.
        .accessibilityHidden(showStopConfirm)
        .allowsHitTesting(!showStopConfirm && !isStopping)
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

            built.session.beginCountdown()

            let mintTask: Task<MintResponse, Error>? = built.mint.map { client in
                Task { try await client.mint() }
            }
            let prepareTask = Task {
                try await built.mouth.prepare()
            }

            for n in [3, 2, 1] {
                try Task.checkCancellation()
                countdownRemaining = n
                try await Task.sleep(for: .seconds(1))
            }
            try Task.checkCancellation()
            // Fog and chrome update together: lift overlay, then mount orb + controls.
            countdownRemaining = nil
            built.session.enterConnecting()

            do {
                try await prepareTask.value
            } catch {
                if !(error is CancellationError) { mintTask?.cancel() }
                throw error
            }

            if let mintTask {
                let minted: MintResponse
                do {
                    minted = try await mintTask.value
                } catch {
                    if !(error is CancellationError) { await built.mouth.close() }
                    throw error
                }
                didMint = true
                do {
                    try await built.session.countdownReachedZero(ephemeralKey: minted.clientSecret)
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
            }
        } catch is CancellationError {
            countdownRemaining = nil
            await mouth?.close()
            await postEndedIfNeeded()
        } catch {
            countdownRemaining = nil
            await mouth?.close()
            await postEndedIfNeeded()
            if let mintError = error as? MintError, mintError == .budget {
                model.budget.used = model.budget.limit
                canRetry = false
            }
            errorMessage = error.localizedDescription
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

    private func clearLiveSession() {
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
        countdownRemaining = nil
    }

    /// The live mouth owns the mic and partner audio; the orb reads both levels from it.
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
        let mint = MintClient.makeIfConfigured(uuid: model.account.accountUUID)
        let mouth: any ConversationMouth
        let fake: FakeConversationMouth?
        if let mint {
            mouth = LiveConversationMouth(apiKey: mint.apiKey)
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
        return SessionStart(session: session, mouth: mouth, fake: fake, mint: mint)
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
        routeIfFinished()
        if !didRouteFinish { isStopping = false }
    }

    private func routeIfFinished() {
        guard !didRouteFinish, let session else { return }
        switch session.phase {
        case .crisis:
            markRoutedAndPostEnded()
            model.presentCrisis(possibleMinorFlag: session.possibleMinorFlag)
        case .report, .dropped:
            guard let report = session.report else { return }
            Self.log.info(
                "conversation end reason=\(String(describing: report.endReason), privacy: .public) turns=\(report.userTurns) present=\(session.shouldPresentReport)"
            )
            if !session.shouldPresentReport {
                if errorMessage == nil {
                    errorMessage = "Connection lost."
                    canRetry = true
                }
                markRoutedAndPostEnded()
                return
            }
            markRoutedAndPostEnded()
            model.finishConversation(
                report: report,
                possibleMinorFlag: session.possibleMinorFlag
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
        countdownRemaining = nil

        switch model.route {
        case .conversationReport, .crisis:
            Task { await postEndedIfNeeded() }
            return
        default:
            break
        }

        didRouteFinish = true
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

    var errorDescription: String? {
        switch self {
        case .missingOpens: "Opening prompts didn’t load."
        }
    }
}
