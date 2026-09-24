import AVFoundation
import SwiftUI
import SpeechAppKit

struct MonologueSessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase

    @State private var session: MonologueSession?
    @State private var errorMessage: String?
    @State private var listenError: String?
    @State private var showLeaveConfirm = false
    @State private var didRouteFinish = false
    @State private var countdownRemaining: Int?
    @State private var isPreparing = false
    @State private var startTask: Task<Void, Never>?

    // Live capture — held so the pump Tasks and engine/source can be cancelled/stopped.
    @State private var liveEngine: LiveTranscriptionEngine?
    @State private var liveSource: MicAudioSource?
    @State private var transcriptTask: Task<Void, Never>?
    @State private var audioTask: Task<Void, Never>?
    @State private var speechEnergy: Float = 0
    @State private var isStartingListen = false

    // Current-take recognition accumulation. `LiveTranscriptionEngine` sometimes grows
    // the same hypothesis and sometimes starts a fresh segment — these track that so we
    // can assign the full take text/ranges to the session instead of dropping earlier speech.
    @State private var hypothesis: String = ""
    @State private var lastRaw: String = ""
    @State private var committedRanges: [ConversationSpeechInterval] = []

    /// Fog the notes page for the 3-2-1 after I’m ready. The take clock stays stopped until it ends.
    private var isFogged: Bool {
        countdownRemaining != nil || isPreparing
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
            content
                .blur(radius: fogBlurRadius)
                .overlay {
                    Color.black.opacity(fogWashOpacity)
                        .allowsHitTesting(false)
                }
                .accessibilityHidden(isFogged || showLeaveConfirm)
                .allowsHitTesting(!isFogged && !showLeaveConfirm)

            if isFogged {
                ReadingCountdownOverlay(remaining: countdownRemaining, instruction: "")
            }

            if showLeaveConfirm {
                SessionStopModal(
                    title: "Leave this talk?",
                    confirmTitle: "Leave",
                    dismissTitle: "Keep going",
                    onConfirm: {
                        showLeaveConfirm = false
                        Task {
                            await stopListen()
                            session?.confirmLeave()
                            routeIfFinished()
                        }
                    },
                    onDismiss: { showLeaveConfirm = false }
                )
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle, value: session?.phase)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle, value: isFogged)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle, value: showLeaveConfirm)
        .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.65), trigger: countdownRemaining)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(showLeaveConfirm ? .hidden : .automatic, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    handleBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Back")
            }
        }
        .background {
            NavigationPopLock(isLocked: showLeaveConfirm)
        }
        .task { await setUpSessionIfNeeded() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            Task {
                let wasTaking = session?.phase == .taking
                await session?.tick()
                if wasTaking, session?.phase != .taking {
                    await stopListen()
                }
                routeIfFinished()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { note in
            handleRouteChange(note)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                session?.pause()
            }
        }
        .onDisappear {
            startTask?.cancel()
            startTask = nil
            // Swipe-back still pops the screen even with the back button hidden.
            Task { await stopListen() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage {
            errorView(errorMessage)
        } else if let session {
            sessionContent(session)
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private func sessionContent(_ session: MonologueSession) -> some View {
        switch session.phase {
        case .planning, .between:
            planningCanvas(session)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !isFogged {
                        planningChrome(session)
                    }
                }
        case .taking, .paused:
            liveCanvas(session)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    liveChrome(session)
                }
        case .report, .crisis:
            // routeIfFinished already navigated away by the time this would render.
            Color.clear
        }
    }

    // MARK: - Planning / between

    private func planningCanvas(_ session: MonologueSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpeechSpacing.section) {
                Text(session.prompt)
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .lineSpacing(10)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                VStack(alignment: .leading, spacing: SpeechSpacing.cluster) {
                    Text("Notes")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    TextEditor(text: notesBinding(session))
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 150)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(.secondarySystemBackground).opacity(0.6))
                        )
                }

                if session.takes.last?.index != nil {
                    TextField("One thing to reuse", text: reuseLineBinding(session))
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemBackground).opacity(0.6))
                        )
                }

                if !session.betweenCopy.isEmpty {
                    Text(session.betweenCopy)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button("Another topic") {
                    session.skipTopic()
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, SpeechSpacing.page)
            .padding(.top, 20)
            .padding(.bottom, 12)
        }
    }

    private func planningChrome(_ session: MonologueSession) -> some View {
        VStack(alignment: .leading, spacing: SpeechSpacing.related) {
            if let listenError {
                Text(listenError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("I’m ready") {
                startTask?.cancel()
                startTask = Task { await beginListen(session) }
            }
            .buttonStyle(SpeechPrimaryButtonStyle(showsTint: true))
            .disabled(isStartingListen)
        }
        .padding(.horizontal, SpeechSpacing.page)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    // MARK: - Taking / paused

    private func liveCanvas(_ session: MonologueSession) -> some View {
        VStack(alignment: .leading, spacing: SpeechSpacing.related) {
            Text(session.prompt)
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Text(clockLabel(session.remaining))
                .font(.title)
                .monospacedDigit()
                .foregroundStyle(.primary)

            if session.phase == .paused {
                Text("Paused.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, SpeechSpacing.page)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func liveChrome(_ session: MonologueSession) -> some View {
        HStack(spacing: VoiceOrb.controlSpacing) {
            Button {
                if session.phase == .paused {
                    session.resume()
                } else {
                    session.pause()
                }
            } label: {
                Image(systemName: session.phase == .paused ? "play.fill" : "pause.fill")
                    .speechGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.phase == .paused ? "Resume" : "Pause")

            VoiceOrb(
                phase: session.phase == .taking ? .listening : .idle,
                inputVolume: session.phase == .taking ? speechEnergy : 0,
                animating: session.phase == .taking
            )

            Button {
                Task {
                    await stopListen()
                    session.done()
                    routeIfFinished()
                }
            } label: {
                Image(systemName: "checkmark")
                    .speechGlassCircle(tint: .accentColor)
            }
            .accessibilityLabel("Done")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, SpeechSpacing.page)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    // MARK: - Error state

    private func errorView(_ message: String) -> some View {
        VStack(spacing: SpeechSpacing.related) {
            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Back to home") {
                model.goHome()
            }
            .buttonStyle(SpeechSecondaryButtonStyle())
        }
        .padding(SpeechSpacing.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Bindings

    private func notesBinding(_ session: MonologueSession) -> Binding<String> {
        Binding(
            get: { session.notes },
            set: { session.notes = $0 }
        )
    }

    private func reuseLineBinding(_ session: MonologueSession) -> Binding<String> {
        Binding(
            get: { session.reuseLine },
            set: { session.reuseLine = $0 }
        )
    }

    // MARK: - Live capture

    /// Permission-first on-device listen. A 3-2-1 plays after I’m ready, then
    /// `session.ready()` starts the take clock. No PCM storage, no WebRTC.
    private func beginListen(_ session: MonologueSession) async {
        guard !isStartingListen else { return }
        isStartingListen = true
        defer { isStartingListen = false }

        listenError = nil
        // New take — reset accumulation so take-1 speech never leaks into take 2/3.
        hypothesis = ""
        lastRaw = ""
        committedRanges = []
        // Take 2/3 "I'm ready" must not retain take-1 audio.
        await stopListen()

        #if os(iOS)
        let granted = await requestMic()
        guard granted else {
            listenError = "Microphone permission is required."
            return
        }
        do {
            try await LiveTranscriptionEngine.requestSpeechAuthorization()
        } catch {
            listenError = "Speech recognition permission is required (Settings → SpeechApp)."
            return
        }

        isPreparing = true
        countdownRemaining = 3
        defer {
            isPreparing = false
            countdownRemaining = nil
        }

        let engine = LiveTranscriptionEngine()
        engine.setContextualPhrases([session.prompt])
        let prepareTask = Task {
            try await engine.prepareIfNeeded()
        }

        var startedSource: MicAudioSource?
        do {
            for n in [3, 2, 1] {
                try Task.checkCancellation()
                countdownRemaining = n
                try await Task.sleep(for: .seconds(1))
            }
            countdownRemaining = nil
            try await prepareTask.value
            try Task.checkCancellation()
            let source = MicAudioSource()
            try await source.start()
            startedSource = source
            try await engine.start()
        } catch is CancellationError {
            prepareTask.cancel()
            await startedSource?.stop()
            return
        } catch {
            prepareTask.cancel()
            await startedSource?.stop()
            listenError = error.localizedDescription
            return
        }

        guard let source = startedSource else { return }
        let updates = engine.updates

        liveEngine = engine
        liveSource = source

        transcriptTask = Task {
            for await update in updates {
                absorbHypothesis(update.rawText)
                session.ingestText(hypothesis)

                let timedTokens: [(isFinal: Bool, interval: ConversationSpeechInterval)] = update.tokens.compactMap { token in
                    guard let start = token.startTime, let end = token.endTime else { return nil }
                    return (isFinal: token.isFinal, interval: ConversationSpeechInterval(start: start, end: end))
                }
                let finals = timedTokens.filter(\.isFinal).map(\.interval)
                committedRanges.append(contentsOf: finals)
                // Volatile intervals often repeat the whole current result, so they
                // re-cover already-committed words. Only keep the part past the committed edge.
                let committedEnd = committedRanges.last?.end ?? -1
                let volatileTail = timedTokens
                    .filter { !$0.isFinal && $0.interval.start >= committedEnd }
                    .map(\.interval)
                session.ingestRanges(committedRanges + volatileTail)

                if session.phase == .crisis {
                    // Don't wait for the next timer tick — stop and route now.
                    await stopListen()
                    routeIfFinished()
                    break
                }
            }
        }

        audioTask = Task {
            for await chunk in source.chunks {
                engine.append(chunk)
                speechEnergy = ListenDrive.normalized(rms: StallDetector.rms(chunk.samples))
            }
        }

        session.ready()
        #else
        listenError = "Live mic requires iOS."
        #endif
    }

    /// Absorbs a new recognizer `rawText` into the running take's `hypothesis`.
    /// `LiveTranscriptionEngine` sometimes yields a growing full result (rawText extends
    /// the previous one) and sometimes a fresh segment (`deltaFinals` treats non-prefix
    /// text as new). This never shrinks the accumulated hypothesis.
    private func absorbHypothesis(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let lowerHypothesis = hypothesis.lowercased()
        let lowerText = text.lowercased()

        if hypothesis.isEmpty || lowerHypothesis.hasPrefix(lowerText) || lowerText.hasPrefix(lowerHypothesis) {
            // One is a case-insensitive prefix of the other — keep the longer one.
            // If the new text is a prefix of the current hypothesis, keep the hypothesis.
            if text.count > hypothesis.count {
                hypothesis = text
            }
        } else if !lastRaw.isEmpty,
                  hypothesis.count > lastRaw.count,
                  lowerHypothesis.hasSuffix(lastRaw.lowercased()) {
            // The latest segment grew — replace that trailing segment with the new text.
            let keepCount = hypothesis.count - lastRaw.count
            let keepEnd = hypothesis.index(hypothesis.startIndex, offsetBy: keepCount)
            hypothesis = String(hypothesis[hypothesis.startIndex..<keepEnd]) + text
        } else {
            // Fresh segment.
            hypothesis += " " + text
        }

        lastRaw = text
    }

    /// Cancels the pump Tasks and stops engine/source. Never stopped on user Pause —
    /// resume continues the same engine.
    private func stopListen() async {
        audioTask?.cancel()
        audioTask = nil
        transcriptTask?.cancel()
        transcriptTask = nil
        await liveEngine?.stop()
        await liveSource?.stop()
        liveEngine = nil
        liveSource = nil
        speechEnergy = 0
    }

    #if os(iOS)
    private func requestMic() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    #endif

    // MARK: - Lifecycle

    private func setUpSessionIfNeeded() async {
        guard session == nil, errorMessage == nil else { return }
        do {
            let bank = try OpenPromptBank.loadBundled()
            session = MonologueSession(
                prompts: bank.prompts,
                store: UserDefaultsMonologuePromptStore(),
                time: SystemTimeSource()
            )
        } catch {
            errorMessage = "Topics didn’t load."
        }
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

    private func handleBack() {
        startTask?.cancel()
        startTask = nil
        guard let session else {
            model.goHome()
            return
        }
        if session.phase == .planning, session.takes.isEmpty {
            model.goHome()
        } else {
            showLeaveConfirm = true
        }
    }

    private func routeIfFinished() {
        guard !didRouteFinish, let session else { return }
        if session.phase == .report || session.phase == .crisis, let report = session.report {
            didRouteFinish = true
            model.finishMonologue(
                report: report,
                possibleMinorFlag: session.possibleMinorFlag
            )
        }
    }

    private func clockLabel(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
