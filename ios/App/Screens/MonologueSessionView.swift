import AVFoundation
import OSLog
import SwiftUI
import UIKit
import SpeechAppKit

struct MonologueSessionView: View {
    private static let log = Logger(subsystem: "com.speechapp", category: "MonologueRecording")

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase

    @State private var session: MonologueSession?
    @State private var errorMessage: String?
    @State private var listenError: String?
    @State private var showLeaveConfirm = false
    @State private var didRouteFinish = false
    @State private var isPreparing = false
    /// When the connecting orb appeared. The slow line uses this clock.
    @State private var connectingStarted: Date?
    @State private var startTask: Task<Void, Never>?

    // Live capture — held so the pump Tasks and engine/source can be cancelled/stopped.
    @State private var liveEngine: (any TranscriptionEngine)?
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

    // Full take text from Grok. The stitcher already keeps earlier words, so each
    // update's rawText replaces this rather than being appended.
    @State private var hypothesis: String = ""
    @State private var committedRanges: [ConversationSpeechInterval] = []
    @State private var committedSpokenTokens: [SpokenToken] = []
    @State private var lastStreamTime: TimeInterval = 0
    @State private var takeRecorder = TakeRecorder()
    @State private var regimenID = UUID()
    @State private var finishedTakes: [MonologueRecordingPipeline.FinishedTake] = []
    @State private var finalizeTask: Task<Void, Never>?
    @State private var isFinalizingAudio = false
    @State private var didStartReportSave = false
    @State private var saveErrorMessage: String?

    /// Fog the notes page while the microphone starts. The take clock stays stopped until it ends.
    private var isFogged: Bool {
        isPreparing
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
                // The stop card does not sit on a flat scrim: the talk behind it
                // blurs and dims as one layer, so the card is the only thing in focus.
                .blurBackdrop(showLeaveConfirm)

            // Fog and the leave modal animate on their own. A spring on the
            // whole screen also springs the orb bar, and a WebGL view laid out
            // at zero height stays blank for the rest of the take.
            ZStack {
                if showLeaveConfirm {
                    SessionStopModal(
                        title: "Leave this talk?",
                        confirmTitle: "Leave",
                        dismissTitle: "Keep going",
                        onConfirm: {
                            showLeaveConfirm = false
                            Task {
                                if let session {
                                    await finishCurrentTake(session, leaving: true)
                                } else {
                                    await stopListen()
                                    routeIfFinished()
                                }
                            }
                        },
                        onDismiss: { showLeaveConfirm = false }
                    )
                    .transition(SpeechBlur.dissolve)
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle, value: isFogged)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle, value: showLeaveConfirm)
            .allowsHitTesting(isFogged || showLeaveConfirm)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .speechBarChrome()
        .speechBottomBlur(bar: false)
        .navigationBarBackButtonHidden(true)
        .toolbar(showLeaveConfirm ? .hidden : .automatic, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                SpeechBarButton(systemName: "chevron.left", label: "Back") {
                    handleBack()
                }
            }
            if session?.phase == .planning || session?.phase == .between {
                ToolbarItem(placement: .topBarTrailing) {
                    SpeechBarButton(systemName: "waveform", label: "Gallery") {
                        model.showGallery()
                    }
                }
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
                if wasTaking, let session, session.phase != .taking {
                    // Ceiling hit — same as Done for this take.
                    if session.phase == .between {
                        await captureTakeAudio(session)
                        await stopListen()
                    } else if session.phase == .report {
                        await stopListen()
                        beginReportSave(session)
                        routeIfFinished()
                    } else if session.phase == .crisis {
                        await handleCrisis(session)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { note in
            handleRouteChange(note)
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { note in
            if SessionInterruption.shouldPause(note) {
                session?.pause(atStreamTime: lastStreamTime)
                takeRecorder.setWriting(false)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                session?.pause(atStreamTime: lastStreamTime)
                takeRecorder.setWriting(false)
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
            .accessibilityHidden(isFogged || showLeaveConfirm)
            .allowsHitTesting(!isFogged && !showLeaveConfirm)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle, value: session.phase)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle, value: isFogged)
            .safeAreaBar(edge: .bottom, spacing: 0) {
                sessionChrome(session, live: live)
                    .accessibilityHidden(showLeaveConfirm)
                    .allowsHitTesting(!showLeaveConfirm)
            }
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
        // The connecting orb is the same bar the take uses, so it is already
        // up while the model connects. Mounting it only as the phase changes
        // blanks the WebGL view.
        if live || isPreparing {
            liveChrome(session, live: live)
        } else if session.phase == .planning || session.phase == .between {
            planningChrome(session)
                .opacity(isFogged ? 0 : 1)
                .accessibilityHidden(isFogged)
                .allowsHitTesting(!isFogged)
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
                        .speechReading()
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
            .padding(.top, SpeechSpacing.section)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func stageDuration(_ minutes: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(minutes)")
                .font(.system(size: stageDurationSize, weight: .semibold))
                .monospacedDigit()
                .digitRoll(minutes, countsDown: true, reduceMotion: reduceMotion)
            Text(minutes == 1 ? "minute" : "minutes")
                .speechType(.h3)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(minutes) \(minutes == 1 ? "minute" : "minutes")")
        .accessibilityAddTraits(.isHeader)
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
                .speechReading()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

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
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    /// Keep this bar at its real size. A phase spring that shrinks it leaves the WebGL orb blank.
    private func orbBar(session: MonologueSession, live: Bool) -> some View {
        SessionOrbBar(
            phase: .monologue(isPreparing: !live, phase: session.phase),
            connectingStarted: isPreparing ? connectingStarted : nil,
            inputVolume: session.phase == .taking ? speechEnergy : 0,
            animating: session.phase != .paused
        ) {
            Button {
                if session.phase == .paused {
                    session.resume(atStreamTime: lastStreamTime)
                    takeRecorder.setWriting(true)
                } else {
                    session.pause(atStreamTime: lastStreamTime)
                    takeRecorder.setWriting(false)
                }
            } label: {
                Image(systemName: session.phase == .paused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(SpeechIconCircleStyle(diameter: SpeechIconCircleStyle.session))
            .disabled(!live)
            .opacity(live ? 1 : 0)
            .allowsHitTesting(live)
            .accessibilityHidden(!live)
            .accessibilityLabel(session.phase == .paused ? "Resume" : "Pause")
        } trailing: {
            Button {
                Task {
                    await finishCurrentTake(session)
                }
            } label: {
                Image(systemName: "checkmark")
            }
            .buttonStyle(SpeechIconCircleStyle(diameter: SpeechIconCircleStyle.session, fill: .red))
            .disabled(!live)
            .opacity(live ? 1 : 0)
            .allowsHitTesting(live)
            .accessibilityHidden(!live)
            .accessibilityLabel("Done")
        }
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

    /// The microphone starts after Grok is ready, or after the phone backup is ready. `session.ready()` starts the take clock.
    private func beginListen(_ session: MonologueSession) async {
        dismissKeyboardImmediately()
        guard !isStartingListen else { return }
        isStartingListen = true
        defer { isStartingListen = false }

        listenError = nil
        // New take — reset accumulation so take-1 speech never leaks into take 2/3.
        hypothesis = ""
        committedRanges = []
        // Take 2/3 "I'm ready" must not retain take-1 audio.
        await stopListen()

        #if os(iOS)
        let granted = await requestMic()
        guard granted else {
            Self.log.error("microphone permission denied")
            listenError = UserFacingFailure.microphoneOff
            return
        }
        isPreparing = true
        connectingStarted = Date()
        VoiceOrbPreloader.warmup()
        defer {
            isPreparing = false
            connectingStarted = nil
        }

        let engine: any TranscriptionEngine
        do {
            engine = try await LiveSpeech.engine(
                apiKey: XAIDirectKey.load(),
                phrases: Self.keyterms(prompt: session.prompt, reuseLine: session.reuseLine)
            )
        } catch is CancellationError {
            return
        } catch {
            UserFacingFailure.log(error, context: "monologue start")
            listenError = UserFacingFailure.message(for: error)
            return
        }
        // One read. A later read of `updates` would replace the stream and drop words.
        let updates = engine.updates

        var startedSource: MicAudioSource?
        do {
            try Task.checkCancellation()
            try await engine.start(locale: Locale(identifier: "en-US"), preference: .autoPreferSpeechTranscriber)
            let source = MicAudioSource()
            try await source.start()
            startedSource = source
        } catch is CancellationError {
            await startedSource?.stop()
            await engine.stop()
            return
        } catch {
            await startedSource?.stop()
            await engine.stop()
            UserFacingFailure.log(error, context: "monologue start")
            listenError = UserFacingFailure.message(for: error)
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
                    lastStreamTime = max(lastStreamTime, end)
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

                let finalSpoken = update.tokens.filter { $0.isFinal && $0.startTime != nil && $0.endTime != nil }
                if !finalSpoken.isEmpty {
                    committedSpokenTokens.append(contentsOf: finalSpoken)
                    session.ingestWords(committedSpokenTokens)
                }

                if session.phase == .crisis {
                    await handleCrisis(session)
                    break
                }
            }
        }

        audioTask = Task {
            for await chunk in source.chunks {
                // Only feed Grok and the file while the take clock is running so
                // stream time and the saved file stay aligned across pauses.
                guard session.phase == .taking else {
                    speechEnergy = 0
                    continue
                }
                engine.append(chunk)
                takeRecorder.append(chunk)
                let duration = Double(chunk.samples.count) / max(chunk.sampleRate, 1)
                session.appendRecordingAudio(duration: duration)
                speechEnergy = ListenDrive.normalized(rms: StallDetector.rms(chunk.samples))
            }
        }

        hypothesis = ""
        committedRanges = []
        committedSpokenTokens = []
        lastStreamTime = 0
        try? takeRecorder.start()
        takeRecorder.setWriting(true)
        session.ready()
        #else
        Self.log.error("live mic is unavailable off iOS")
        listenError = UserFacingFailure.needsIPhone
        #endif
    }

    /// Topic words to bias Grok toward. Each term is capped at 50 characters.
    private static func keyterms(prompt: String, reuseLine: String) -> [String] {
        [prompt, reuseLine]
            .flatMap { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
            .filter { !$0.isEmpty }
    }

    /// Cancels the pump Tasks and stops engine/source. Never stopped on user Pause —
    /// resume continues the same engine. Does not finalize the take recorder —
    /// call `captureTakeAudio` for that.
    private func stopListen() async {
        takeRecorder.setWriting(false)
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
            let bank = try MonologuePromptBank.loadBundled()
            session = MonologueSession(
                prompts: bank.prompts,
                store: UserDefaultsMonologuePromptStore(),
                time: SystemTimeSource()
            )
        } catch {
            UserFacingFailure.log(error, context: "monologue topics")
            errorMessage = UserFacingFailure.topicsDidNotLoad
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
            session?.pause(atStreamTime: lastStreamTime)
            takeRecorder.setWriting(false)
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
            // The id is passed only once a save is actually running. Keep-on with
            // no audio must not sit on the ring waiting for a file that will not appear.
            let id: UUID? = if report.kind == .crisis || !didStartReportSave {
                nil
            } else {
                regimenID
            }
            model.finishMonologue(
                report: report,
                possibleMinorFlag: session.possibleMinorFlag,
                regimenID: id,
                topic: session.prompt
            )
        }
    }

    /// Done / leave: stop mic, snapshot the take, then route.
    /// The take that opens the report saves in the background so the ring is on screen.
    /// Earlier takes still finish here, between takes.
    private func finishCurrentTake(_ session: MonologueSession, leaving: Bool = false) async {
        await stopListen()
        if leaving {
            session.confirmLeave()
        } else {
            session.done()
        }
        if session.phase == .crisis {
            await handleCrisis(session)
            return
        }
        if session.phase == .report {
            beginReportSave(session)
            routeIfFinished()
            return
        }
        await captureTakeAudio(session)
    }

    private func handleCrisis(_ session: MonologueSession) async {
        _ = takeRecorder.stop()
        try? RecordingsService.store.delete(id: regimenID)
        finishedTakes = []
        await stopListen()
        routeIfFinished()
    }

    /// Finalize the just-finished take's audio into `finishedTakes`.
    private func captureTakeAudio(_ session: MonologueSession) async {
        guard let take = session.takes.last, !take.words.isEmpty else {
            _ = takeRecorder.stop()
            return
        }
        if finishedTakes.contains(where: { $0.index == take.index }) {
            _ = takeRecorder.stop()
            return
        }
        guard let rawURL = takeRecorder.stop() else { return }
        isFinalizingAudio = true
        defer { isFinalizingAudio = false }
        do {
            let (finalURL, report) = try await TakeFinalizer.finalizeWithReport(rawCAF: rawURL)
            let line = "take \(take.index) saved: \(report.stages.line(usedDenoise: report.usedDenoise)) inputPeak=\(report.inputPeak) outputPeak=\(report.outputPeak)"
            Self.log.info("\(line, privacy: .public)")
            finishedTakes.append(
                MonologueRecordingPipeline.FinishedTake(
                    index: take.index,
                    durationSeconds: take.wallSeconds,
                    words: take.words,
                    audioURL: finalURL
                )
            )
        } catch TakeFinalizerError.empty {
            try? FileManager.default.removeItem(at: rawURL)
        } catch {
            UserFacingFailure.log(error, context: "monologue save")
            saveErrorMessage = (error as? RecordingStoreError) == .diskFull
                ? UserFacingFailure.diskFull
                : UserFacingFailure.nothingToPlay
            try? FileManager.default.removeItem(at: rawURL)
        }
    }

    /// Starts the last take's save, then returns. The report ring follows that work.
    private func beginReportSave(_ session: MonologueSession) {
        guard !didStartReportSave else { return }
        guard let report = session.report, report.kind != .crisis else { return }
        let rawURL = takeRecorder.stop()
        let earlier = finishedTakes
        let last = session.takes.last
        let lastNeedsFinalize = rawURL != nil
            && last.map { take in
                !take.words.isEmpty && !earlier.contains { $0.index == take.index }
            } == true
        let kept = RecordingsService.keepRecordings
        let hasSomething = lastNeedsFinalize || !earlier.isEmpty || (kept && saveErrorMessage != nil)
        guard hasSomething else {
            if let rawURL { try? FileManager.default.removeItem(at: rawURL) }
            return
        }
        didStartReportSave = true
        let id = regimenID
        let topic = session.prompt
        let failure = saveErrorMessage
        let duration = last?.wallSeconds ?? earlier.map(\.durationSeconds).max() ?? 0
        SaveProgressBoard.begin(
            id: id,
            durationSeconds: duration,
            willClean: SaveProgress.needsCleaning(
                durationSeconds: duration,
                runsOnSimulator: SaveProgressBoard.runsOnSimulator
            ),
            includesTranscription: false
        )
        Task { @MainActor in
            await Self.finishReportSave(
                id: id,
                rawURL: rawURL,
                last: last,
                lastNeedsFinalize: lastNeedsFinalize,
                earlier: earlier,
                report: report,
                topic: topic,
                inLibrary: kept,
                saveError: failure
            )
        }
    }

    /// Finalize the take that opened the report, then write the manifest. Outlives the session screen.
    private static func finishReportSave(
        id: UUID,
        rawURL: URL?,
        last: MonologueTake?,
        lastNeedsFinalize: Bool,
        earlier: [MonologueRecordingPipeline.FinishedTake],
        report: MonologueReport,
        topic: String,
        inLibrary: Bool,
        saveError: String?
    ) async {
        defer { SaveProgressBoard.markFinished(id: id) }
        var takes = earlier
        var failure = saveError
        var timing = "clean=not-this-take"
        if lastNeedsFinalize, let rawURL, let last {
            do {
                let (url, report) = try await TakeFinalizer.finalizeWithReport(rawCAF: rawURL) { step, fraction in
                    SaveProgressBoard.update(id: id, step, fraction)
                }
                timing = report.stages.line(usedDenoise: report.usedDenoise)
                takes.append(
                    MonologueRecordingPipeline.FinishedTake(
                        index: last.index,
                        durationSeconds: last.wallSeconds,
                        words: last.words,
                        audioURL: url
                    )
                )
            } catch TakeFinalizerError.empty {
                try? FileManager.default.removeItem(at: rawURL)
            } catch {
                failure = (error as? RecordingStoreError) == .diskFull
                    ? UserFacingFailure.diskFull
                    : UserFacingFailure.nothingToPlay
                try? FileManager.default.removeItem(at: rawURL)
            }
        }
        SaveProgressBoard.update(id: id, .writing, 0)
        MonologueRecordingPipeline.persist(
            regimenID: id,
            topic: topic,
            report: report,
            finishedTakes: takes,
            inLibrary: inLibrary,
            saveError: failure,
            onWriting: { SaveProgressBoard.update(id: id, .writing, $0) }
        )
        let wall = Int(SaveProgressBoard.wallMilliseconds(id: id).rounded())
        let line = "monologue save: \(timing) wall=\(wall)ms"
        Self.log.info("\(line, privacy: .public)")
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
                .digitRoll(label, countsDown: true, reduceMotion: reduceMotion)
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
