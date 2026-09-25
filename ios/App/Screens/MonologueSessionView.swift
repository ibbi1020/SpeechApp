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
    @State private var liveEngine: LiveTranscriptionEngine?
    @State private var liveSource: MicAudioSource?
    @State private var transcriptTask: Task<Void, Never>?
    @State private var audioTask: Task<Void, Never>?
    @State private var speechEnergy: Float = 0
    @State private var isStartingListen = false
    @State private var notes: [SpokenNote] = []
    @State private var noteDraft = ""
    @State private var isAddingNote = false
    @FocusState private var noteFieldFocused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var stageDurationSize: CGFloat = 48
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 76

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
        .task {
            VoiceOrbPreloader.warmup()
            await setUpSessionIfNeeded()
        }
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
        let live = session.phase == .taking || session.phase == .paused
        Group {
            switch session.phase {
            case .planning, .between:
                planningCanvas(session)
            case .taking, .paused:
                liveCanvas(session)
            case .report, .crisis:
                Color.clear
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if live {
                liveChrome(session)
            } else if session.phase == .planning || session.phase == .between {
                planningChrome(session)
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
                        Button("Change topic") {
                            session.skipTopic()
                        }
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 44, alignment: .leading)
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
        .scrollEdgeEffectStyle(.soft, for: .bottom)
    }

    private func stageDuration(_ minutes: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(minutes)")
                .font(.system(size: stageDurationSize, weight: .semibold))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .opacity : .numericText(countsDown: true))
            Text(minutes == 1 ? "minute" : "minutes")
                .font(.title3.weight(.medium))
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
                    dismissKeyboardImmediately()
                    startTask?.cancel()
                    startTask = Task { await beginListen(session) }
                }
                .buttonStyle(SpeechPrimaryButtonStyle(showsTint: true))
                .disabled(isStartingListen)
            }
        }
        .padding(.horizontal, SpeechSpacing.page)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    // MARK: - Taking / paused

    private func liveCanvas(_ session: MonologueSession) -> some View {
        let line = subtitleLine(hypothesis)
        return ZStack {
            Text(session.prompt)
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 8)

            VStack(spacing: 12) {
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

            if !line.isEmpty {
                Text(line)
                    .font(.system(.subheadline, design: .serif))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .foregroundStyle(.primary.opacity(0.7))
                    .lineLimit(2)
                    .truncationMode(.head)
                    .frame(maxWidth: 280)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 10)
                    .accessibilityLabel(line)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .padding(.horizontal, SpeechSpacing.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                phase: .monologue(isPreparing: false, phase: session.phase),
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

    /// The newest words, capped so a long take stays a two-line caption.
    private func subtitleLine(_ transcript: String) -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = 110
        guard trimmed.count > limit else { return trimmed }
        let start = trimmed.index(trimmed.endIndex, offsetBy: -limit)
        let tail = trimmed[start...]
        guard let space = tail.firstIndex(of: " ") else { return String(tail) }
        return String(tail[tail.index(after: space)...])
    }

    // MARK: - Live capture

    /// Permission-first on-device listen. A 3-2-1 plays after I’m ready, then
    /// `session.ready()` starts the take clock. No PCM storage, no WebRTC.
    private func beginListen(_ session: MonologueSession) async {
        dismissKeyboardImmediately()
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
            listenError = "Speech recognition permission is required (Settings → Orator)."
            return
        }

        isPreparing = true
        countdownRemaining = 3
        VoiceOrbPreloader.warmup()
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

    private func spokenRemaining(_ t: TimeInterval) -> String {
        let total = max(0, Int(t.rounded()))
        let minutes = total / 60
        let seconds = total % 60
        return "\(minutes) minutes \(seconds) seconds remaining"
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
