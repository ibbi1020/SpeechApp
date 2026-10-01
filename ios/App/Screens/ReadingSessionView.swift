import AVFoundation
import SwiftUI
import SpeechAppKit

struct ReadingSessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let passage: Passage

    @State private var session: ReadingSession?
    @State private var errorMessage: String?
    @State private var countdownRemaining: Int?
    @State private var isPreparing = false
    @State private var startTask: Task<Void, Never>?
    @State private var startPulse = false
    @State private var showStopConfirm = false

    private var isLive: Bool {
        session?.phase == .running || session?.phase == .stalled
    }

    private var isPaused: Bool {
        session?.phase == .paused
    }

    private var isFinishing: Bool {
        session?.phase == .finishing
    }

    /// Fog until listening starts (countdown or engine prep).
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

            passageScroll
                .scrollEdgeEffectStyle(.soft, for: .bottom)
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

            if isFogged {
                ReadingCountdownOverlay(remaining: countdownRemaining)
            }

            if showStopConfirm {
                SessionStopModal(
                    title: "Stop this reading?",
                    confirmTitle: "Stop",
                    dismissTitle: "Keep reading",
                    onConfirm: {
                        showStopConfirm = false
                        Task { await stopSession() }
                    },
                    onDismiss: { showStopConfirm = false }
                )
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle, value: isFogged)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle, value: showStopConfirm)
        .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.65), trigger: countdownRemaining)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(showStopConfirm ? .hidden : .automatic, for: .navigationBar)
        .background {
            NavigationPopLock(isLocked: showStopConfirm)
        }
        .onAppear {
            VoiceOrbPreloader.warmup()
            if session == nil {
                session = ReadingSession(
                    passage: passage,
                    ledgerAverageRate: model.ledger.averageSpeechRate
                )
            }
        }
        .onDisappear {
            switch model.route {
            case .reading, .report:
                return
            default:
                break
            }
            startTask?.cancel()
            startTask = nil
            countdownRemaining = nil
            isPreparing = false
            if let session, session.phase != .idle, session.phase != .finished {
                Task { _ = await session.stop() }
            }
        }
    }

    private var passageScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(passage.title)
                        .font(.system(.title2, design: .serif).weight(.semibold))
                        .foregroundStyle(isFogged ? .tertiary : .primary)

                    Text(passage.durationLabel)
                        .font(.footnote)
                        .foregroundStyle(isFogged ? .tertiary : .secondary)
                }

                Text(passage.text)
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(isFogged ? .tertiary : .primary)
                    .lineSpacing(10)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityLabel(passage.text)
                    .padding(.top, 28)
            }
            .padding(.horizontal, SpeechSpacing.reading)
            .padding(.top, 20)
            .padding(.bottom, 12)
        }
    }

    private var bottomChrome: some View {
        VStack(alignment: .leading, spacing: SpeechSpacing.related) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actionRow
        }
        .padding(.horizontal, SpeechSpacing.page)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle, value: session?.phase)
    }

    @ViewBuilder
    private var actionRow: some View {
        if isLive || isPaused || isFinishing || isFogged {
            liveControlRow
                .opacity(isLive || isPaused || isFinishing ? 1 : 0)
                .allowsHitTesting(isLive || isPaused || isFinishing)
                .accessibilityHidden(!(isLive || isPaused || isFinishing))
        } else {
            Button("Start") {
                startPulse.toggle()
                startTask?.cancel()
                startTask = Task { await beginStart() }
            }
            .buttonStyle(SpeechPrimaryButtonStyle(showsTint: true))
            .sensoryFeedback(.impact(flexibility: .soft), trigger: startPulse)
        }
    }

    private var liveControlRow: some View {
        SessionOrbBar(
            phase: .listening,
            inputVolume: isLive ? (session?.speechEnergy ?? 0) : 0,
            animating: isLive
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
            .disabled(isFinishing)
            .accessibilityLabel(isPaused ? "Resume" : "Pause")
        } trailing: {
            Button {
                showStopConfirm = true
            } label: {
                Image(systemName: "stop.fill")
                    .speechGlassCircle(tint: .red)
            }
            .buttonStyle(.plain)
            .disabled(isFinishing)
            .accessibilityLabel("Stop")
        }
        .opacity(isFinishing ? 0.7 : 1)
    }

    private func beginStart() async {
        errorMessage = nil

        #if os(iOS)
        let granted = await requestMic()
        guard granted else {
            errorMessage = "Microphone permission is required."
            return
        }
        do {
            try await LiveTranscriptionEngine.requestSpeechAuthorization()
        } catch {
            errorMessage = "Speech recognition permission is required (Settings → Orator)."
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
        let prepareTask = Task {
            try await prepareAvailability()
            try await engine.prepareIfNeeded()
        }

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
            try await session?.start(
                audioSource: source,
                engine: engine,
                preference: enginePreference(for: model.speechEngineKind)
            )
        } catch is CancellationError {
            prepareTask.cancel()
        } catch {
            prepareTask.cancel()
            errorMessage = error.localizedDescription
        }
        #else
        errorMessage = "Live mic requires iOS."
        #endif
    }

    private func prepareAvailability() async throws {
        let availability = await LiveTranscriptionEngine.checkAvailability()
        switch availability {
        case .speechTranscriberReady:
            model.speechEngineKind = .speechTranscriber
        case .dictationTranscriberReady:
            model.speechEngineKind = .dictationTranscriber
        case .dictationTranscriberNeedsDownload:
            try await LiveTranscriptionEngine.ensureDictationAssets()
            model.speechEngineKind = .dictationTranscriber
        case .fallbackSFSpeechRecognizer:
            model.speechEngineKind = .sfSpeechRecognizerOnDevice
        case .unavailable(let message):
            throw WarmupError.message(message)
        }
    }

    private func enginePreference(
        for kind: LiveTranscriptionEngine.EngineKind
    ) -> LiveTranscriptionEngine.EnginePreference {
        switch kind {
        case .speechTranscriber:
            return .speechTranscriber
        case .dictationTranscriber:
            return .dictationTranscriber
        default:
            return .autoPreferSpeechTranscriber
        }
    }

    private func stopSession() async {
        startTask?.cancel()
        guard let session else { return }
        let report = await session.stop()
        model.finish(report: report)
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
}

private enum WarmupError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): message
        }
    }
}
