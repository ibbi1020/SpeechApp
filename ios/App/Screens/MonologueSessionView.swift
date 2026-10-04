import AVFoundation
import SwiftUI
import UIKit
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
    @State private var liveEngine: (any TranscriptionEngine)?
    @State private var liveSource: MicAudioSource?
    @State private var transcriptTask: Task<Void, Never>?
    @State private var audioTask: Task<Void, Never>?
    @State private var speechEnergy: Float = 0
    @State private var isStartingListen = false
    /// Background engine / mic shutdown after Done or Leave. The next take waits on it.
    @State private var pendingStop: Task<Void, Never>?
    @State private var isEnding = false
    @State private var pauseThrottle = TapThrottle()
    @State private var topicThrottle = TapThrottle()
    @State private var notes: [SpokenNote] = []
    @State private var noteDraft = ""
    @State private var isAddingNote = false
    @FocusState private var noteFieldFocused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var stageDurationSize: CGFloat = 48
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 76

    // Full take text from Grok. The stitcher already keeps earlier words, so each
    // update's rawText replaces this rather than being appended.
    @State private var hypothesis: String = ""
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

            // Fog and the leave modal animate on their own. A spring on the
            // whole screen also springs the orb bar, and a WebGL view laid out
            // at zero height stays blank for the rest of the take.
            ZStack {
                if isFogged {
                    ReadingCountdownOverlay(remaining: countdownRemaining, instruction: "")
                }

                if showLeaveConfirm {
                    SessionStopModal(
                        title: "Leave this talk?",
                        confirmTitle: "Leave",
                        dismissTitle: "Keep going",
                        onConfirm: {
                            guard !isEnding else { return }
                            isEnding = true
                            showLeaveConfirm = false
                            // Route first; the engine and mic wind down behind the next screen.
                            detachListen()
                            session?.confirmLeave()
                            routeIfFinished()
                            isEnding = false
                        },
                        onDismiss: { showLeaveConfirm = false }
                    )
                    .transition(.opacity)
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle, value: isFogged)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle, value: showLeaveConfirm)
            .allowsHitTesting(isFogged || showLeaveConfirm)
        }
        .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.65), trigger: countdownRemaining)
        .navigationBarTitleDisplayMode(.inline)
        .speechBottomBlur(bar: false)
        .navigationBarBackButtonHidden(true)
        // Back stays in the bar, unchanged, while the leave card is up (like Reading): removing
        // the only bar item collapses the bar and shifts the page up. The card guards it instead.
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    guard !showLeaveConfirm, !isEnding else { return }
                    handleBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Back")
            }
        }
        .background {
            NavigationPopLock(isLocked: showLeaveConfirm)
        }
        .task {
            VoiceOrbPreloader.warmup()
            await setUpSessionIfNeeded()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            Task {
                let wasTaking = session?.phase == .taking
                await session?.tick()
                if wasTaking, session?.phase != .taking {
                    detachListen()
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
            detachListen()
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

    /// Fog only the page. The orb is a WebGL view and stays blank inside `.blur`,
    /// so live chrome is attached after the filter — same as Reading and Conversation.
    @ViewBuilder
    private func sessionContent(_ session: MonologueSession) -> some View {
        let live = session.phase == .taking || session.phase == .paused
        sessionCanvas(session)
            .blur(radius: fogBlurRadius)
            .overlay {
                Color.black.opacity(fogWashOpacity)
                    .allowsHitTesting(false)
            }
            .animation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle, value: session.phase)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle, value: isFogged)
            .safeAreaBar(edge: .bottom, spacing: 0) {
                sessionChrome(session, live: live)
            }
            .accessibilityHidden(isFogged || showLeaveConfirm)
            .allowsHitTesting(!isFogged && !showLeaveConfirm)
    }

    @ViewBuilder
    private func sessionCanvas(_ session: MonologueSession) -> some View {
        switch session.phase {
        case .planning, .between:
            planningCanvas(session)
        case .taking, .paused:
            liveCanvas(session)
        case .report, .crisis:
            Color.clear
        }
    }

    @ViewBuilder
    private func sessionChrome(_ session: MonologueSession, live: Bool) -> some View {
        // Mount the orb only once the take is up. The 3-2-1 still shows the
        // planning page; swapping that page out from under a live WebGL view
        // is what blanks the orb. Format 2 inserts the orb once, after the countdown.
        if live {
            liveChrome(session, live: true)
        } else if session.phase == .planning || session.phase == .between {
            planningChrome(session)
                .blur(radius: fogBlurRadius)
                .overlay {
                    Color.black.opacity(fogWashOpacity)
                        .allowsHitTesting(false)
                }
        }
    }

    // MARK: - Planning / between

    private func planningCanvas(_ session: MonologueSession) -> some View {
        let minutes = Int(session.ceiling / 60)
        return ScrollView {
            VStack(alignment: .leading, spacing: SpeechSpacing.section) {
                VStack(alignment: .leading, spacing: 14) {
                    stageDuration(minutes)

                    Text(session.prompt)
                        .font(.system(size: 22, weight: .regular, design: .serif))
                        .lineSpacing(8)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)

                    if session.phase == .planning {
                        Button {
                            guard topicThrottle.allow() else { return }
                            session.skipTopic()
                        } label: {
                            Text("Change topic")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: SpeechSpacing.related) {
                    notesEditor(session)

                    if !session.takes.isEmpty {
                        reuseField(session)
                    }
                }
            }
            .padding(.horizontal, SpeechSpacing.page)
            .padding(.top, 28)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func stageDuration(_ minutes: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(minutes)")
                .font(.custom(SpeechType.instrumentSerif, size: stageDurationSize))
                .tracking(stageDurationSize * SpeechType.metrics(.h1).trackingEm)
                .monospacedDigit()
                .contentTransition(reduceMotion ? .opacity : .numericText(countsDown: true))
            Text(minutes == 1 ? "minute" : "minutes")
                .speechType(.h3)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(minutes) \(minutes == 1 ? "minute" : "minutes")")
        .accessibilityAddTraits(.isHeader)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle, value: minutes)
    }

    private func notesEditor(_ session: MonologueSession) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(notes) { note in
                HStack(alignment: .center, spacing: 4) {
                    Text(note.text)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        removeNote(note, from: session)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove note")
                }
            }

            if isAddingNote {
                TextField("Short note", text: $noteDraft)
                    .font(.body)
                    .focused($noteFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { commitNote(session) }
                    .frame(minHeight: 44)
            } else {
                Button {
                    isAddingNote = true
                } label: {
                    Label("Add note", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .task(id: isAddingNote) {
            noteFieldFocused = isAddingNote
        }
    }

    private func reuseField(_ session: MonologueSession) -> some View {
        @Bindable var session = session
        return VStack(alignment: .leading, spacing: SpeechSpacing.cluster) {
            Text("One thing to reuse")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            TextField("A word or phrase", text: $session.reuseLine)
                .font(.body)
                .textFieldStyle(.plain)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.18))
                        .frame(height: 0.5)
                }
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

            if isAddingNote {
                Button("Add") {
                    commitNote(session)
                }
                .buttonStyle(SpeechPrimaryButtonStyle(showsTint: true))
            } else {
                Button("I’m ready") {
                    readyTapped(session)
                }
                .buttonStyle(SpeechStartButtonStyle())
                .disabled(isStartingListen)
            }
        }
        .padding(.horizontal, SpeechSpacing.page)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    // MARK: - Taking / paused

    private func liveCanvas(_ session: MonologueSession) -> some View {
        ZStack {
            Text(session.prompt)
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 8)

            VStack(spacing: 20) {
                MonologueCountdown(
                    session: session,
                    reduceMotion: reduceMotion,
                    size: clockSize
                )
                .equatable()

                if session.phase == .paused {
                    Text("Paused.")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, SpeechSpacing.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func liveChrome(_ session: MonologueSession, live: Bool) -> some View {
        VStack(spacing: 4) {
            SpeechSubtitle(text: subtitleLine(hypothesis))
            orbBar(session: session, live: live)
        }
        .padding(.horizontal, SpeechSpacing.page)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    /// Keep this bar at its real size. A phase spring that shrinks it leaves the WebGL orb blank.
    private func orbBar(session: MonologueSession, live: Bool) -> some View {
        SessionOrbBar(
            phase: .monologue(isPreparing: !live, phase: session.phase),
            inputVolume: session.phase == .taking ? speechEnergy : 0,
            animating: session.phase != .paused
        ) {
            Button {
                guard pauseThrottle.allow() else { return }
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
            .sensoryFeedback(.selection, trigger: session.phase == .paused)
            .accessibilityLabel(session.phase == .paused ? "Resume" : "Pause")
        } trailing: {
            Button {
                guard !isEnding else { return }
                isEnding = true
                // Stop feeding the take, move on, and let the engine and mic close in the background.
                detachListen()
                session.done()
                routeIfFinished()
                isEnding = false
            } label: {
                Image(systemName: "checkmark")
                    .speechGlassCircle(tint: .accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Done")
        }
        .accessibilityHidden(showLeaveConfirm)
        .allowsHitTesting(!showLeaveConfirm)
        .fixedSize(horizontal: false, vertical: true)
        .transaction { $0.disablesAnimations = true }
    }

    // MARK: - Error state

    private func errorView(_ message: String) -> some View {
        VStack(spacing: SpeechSpacing.related) {
            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

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

    // MARK: - Bindings

    private func commitNote(_ session: MonologueSession) {
        let text = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        dismissKeyboardImmediately()
        noteDraft = ""
        isAddingNote = false
        guard !text.isEmpty else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
            notes.append(SpokenNote(text: text))
        }
        syncNotes(session)
    }

    private func removeNote(_ note: SpokenNote, from session: MonologueSession) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
            notes.removeAll { $0.id == note.id }
        }
        syncNotes(session)
    }

    private func syncNotes(_ session: MonologueSession) {
        session.notes = notes.map(\.text).joined(separator: "\n")
    }

    /// The newest words, capped so the caption stays two short lines above the orb.
    private func subtitleLine(_ transcript: String) -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = 96
        guard trimmed.count > limit else { return trimmed }
        let start = trimmed.index(trimmed.endIndex, offsetBy: -limit)
        let tail = trimmed[start...]
        guard let space = tail.firstIndex(of: " ") else { return String(tail) }
        return String(tail[tail.index(after: space)...])
    }

    // MARK: - Live capture

    /// Fog and the first digit go up on the tap; the previous take's shutdown, permission and
    /// engine set-up run behind it. A second tap while a start is in flight is ignored.
    private func readyTapped(_ session: MonologueSession) {
        dismissKeyboardImmediately()
        guard startTask == nil, !isStartingListen else { return }
        listenError = nil
        #if os(iOS)
        guard ProviderKeys.xai != nil else {
            listenError = "Topic-talk transcription isn’t set up in this build."
            return
        }
        #endif
        isStartingListen = true
        isPreparing = true
        countdownRemaining = 3
        startTask = Task {
            await beginListen(session)
            startTask = nil
        }
    }

    /// A 3-2-1 plays after the Grok relay is ready, then `session.ready()` starts the take clock.
    private func beginListen(_ session: MonologueSession) async {
        defer {
            isStartingListen = false
            isPreparing = false
            countdownRemaining = nil
        }
        // Let the fog frame commit before audio-session and engine set-up touch the main thread.
        await SpeechFrame.yieldForRender()

        listenError = nil
        // New take — reset accumulation so take-1 speech never leaks into take 2/3.
        hypothesis = ""
        committedRanges = []
        // Take 2/3 "I'm ready" must not retain take-1 audio.
        await stopListen()

        #if os(iOS)
        let granted = await micGranted()
        guard granted else {
            listenError = "Microphone permission is required."
            return
        }
        guard let xaiKey = ProviderKeys.xai else {
            listenError = "Topic-talk transcription isn’t set up in this build."
            return
        }

        VoiceOrbPreloader.warmup()

        let engine = GrokTranscriptionEngine(xaiAPIKey: xaiKey)
        engine.setContextualPhrases(Self.keyterms(prompt: session.prompt, reuseLine: session.reuseLine))
        // Subscribe before prepare. A later read of `updates` would replace the stream and drop words.
        let updates = engine.updates
        let prepareTask = Task {
            try await engine.prepareIfNeeded(locale: Locale(identifier: "en-US"))
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
            try await engine.start(locale: Locale(identifier: "en-US"), preference: .autoPreferSpeechTranscriber)
            let source = MicAudioSource()
            try await source.start()
            startedSource = source
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

        liveEngine = engine
        liveSource = source

        transcriptTask = Task {
            for await update in updates {
                let text = update.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    hypothesis = text
                }
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
                    detachListen()
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

    /// Topic words to bias Grok toward. Each term is capped at 50 characters by the relay.
    private static func keyterms(prompt: String, reuseLine: String) -> [String] {
        [prompt, reuseLine]
            .flatMap { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
            .filter { !$0.isEmpty }
    }

    /// Cancels the pump Tasks and stops engine/source. Never stopped on user Pause —
    /// resume continues the same engine.
    private func stopListen() async {
        detachListen()
        await pendingStop?.value
    }

    /// Cuts the take off right away (no more words or levels reach the session), then closes
    /// the engine and mic in the background so Done / Leave can move on this frame.
    private func detachListen() {
        audioTask?.cancel()
        audioTask = nil
        transcriptTask?.cancel()
        transcriptTask = nil
        let engine = liveEngine
        let source = liveSource
        liveEngine = nil
        liveSource = nil
        speechEnergy = 0
        guard engine != nil || source != nil else { return }
        let previous = pendingStop
        pendingStop = Task {
            await previous?.value
            await engine?.stop()
            await source?.stop()
        }
    }

    #if os(iOS)
    /// Skips the permission round trip when access is already granted.
    private func micGranted() async -> Bool {
        if AVAudioApplication.shared.recordPermission == .granted { return true }
        return await requestMic()
    }

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
            let bank = try MonologuePromptBank.loadBundled()
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

    /// Drops the keyboard on this frame. A normal resign waits out the countdown
    /// animation, so I’m ready would leave the keyboard up on the next screen.
    private func dismissKeyboardImmediately() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            noteFieldFocused = false
        }
        UIView.performWithoutAnimation {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }
    }
}

private struct SpokenNote: Identifiable {
    let id = UUID()
    var text: String
}

/// The take clock, isolated from mic and transcript updates.
/// Those redraw the screen many times a second and cancel the digit transition.
private struct MonologueCountdown: View, Equatable {
    var session: MonologueSession
    var reduceMotion: Bool
    var size: CGFloat

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.session === rhs.session
            && lhs.reduceMotion == rhs.reduceMotion
            && lhs.size == rhs.size
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let label = clockLabel(session.remaining)
            Text(label)
                .font(.system(size: size, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .contentTransition(reduceMotion ? .opacity : .numericText(countsDown: true))
                .animation(
                    reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle,
                    value: label
                )
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityLabel(spokenRemaining(session.remaining))
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private func clockLabel(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func spokenRemaining(_ t: TimeInterval) -> String {
        let total = max(0, Int(t.rounded()))
        return "\(total / 60) minutes \(total % 60) seconds remaining"
    }
}
