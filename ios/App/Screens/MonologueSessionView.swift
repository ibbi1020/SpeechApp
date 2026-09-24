import AVFoundation
import SwiftUI
import SpeechAppKit

struct MonologueSessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var session: MonologueSession?
    @State private var errorMessage: String?
    @State private var listenError: String?
    @State private var showLeaveConfirm = false
    @State private var didRouteFinish = false

    // Live capture — held so the pump Tasks and engine/source can be cancelled/stopped.
    @State private var liveEngine: LiveTranscriptionEngine?
    @State private var liveSource: MicAudioSource?
    @State private var transcriptTask: Task<Void, Never>?
    @State private var audioTask: Task<Void, Never>?
    @State private var speechEnergy: Float = 0

    var body: some View {
        ZStack {
            SpeechScreenBackground()
            content
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle, value: session?.phase)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
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
        .confirmationDialog(
            "Leave this talk?",
            isPresented: $showLeaveConfirm,
            titleVisibility: .visible
        ) {
            Button("Leave", role: .destructive) {
                Task {
                    await stopListen()
                    session?.confirmLeave()
                    routeIfFinished()
                }
            }
            Button("Keep going", role: .cancel) {}
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
                    planningChrome(session)
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
                Task { await beginListen(session) }
            }
            .buttonStyle(SpeechPrimaryButtonStyle(showsTint: true))
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
        HStack(spacing: 16) {
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

            AuroraPill(
                energy: speechEnergy,
                mode: .listen,
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

    /// Permission-first on-device listen. Only calls `session.ready()` (starting the
    /// 4:00 clock) once mic + speech authorization and the engine/source are up.
    /// No 3-2-1, no PCM storage, no WebRTC — text/ranges are pumped straight into the session.
    private func beginListen(_ session: MonologueSession) async {
        listenError = nil
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

        let engine = LiveTranscriptionEngine()
        engine.setContextualPhrases([session.prompt])

        var startedSource: MicAudioSource?
        do {
            try await engine.prepareIfNeeded()
            let source = MicAudioSource()
            try await source.start()
            startedSource = source
            try await engine.start()
        } catch {
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
                session.ingestText(update.rawText)
                let ranges: [ConversationSpeechInterval] = update.tokens.compactMap { token in
                    guard let start = token.startTime, let end = token.endTime else { return nil }
                    return ConversationSpeechInterval(start: start, end: end)
                }
                session.ingestRanges(ranges)
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
                speechEnergy = min(1, StallDetector.rms(chunk.samples) / 0.06)
            }
        }

        session.ready()
        #else
        listenError = "Live mic requires iOS."
        #endif
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

    private func handleBack() {
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
