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
        ScrollViewReader { proxy in
            ScrollView {
                passageBody
            }
            .onChange(of: session?.currentWordID) { _, wordID in
                guard isLive, let wordID else { return }
                guard let index = passage.words.firstIndex(where: { $0.id == wordID }), index >= 12 else {
                    return
                }
                if reduceMotion {
                    proxy.scrollTo(wordID, anchor: .center)
                } else {
                    withAnimation(SpeechMotion.scroll) {
                        proxy.scrollTo(wordID, anchor: .center)
                    }
                }
            }
        }
    }

    private var passageBody: some View {
        VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(passage.title)
                        .font(.system(.title2, design: .serif).weight(.semibold))
                        .foregroundStyle(isFogged ? .tertiary : .primary)

                    Text(passage.durationLabel)
                        .font(.footnote)
                        .foregroundStyle(isFogged ? .tertiary : .secondary)
                }

                ReadingFollowAlong(
                    words: passage.words,
                    currentWordID: isLive ? session?.currentWordID : nil,
                    reduceMotion: reduceMotion,
                    dimmed: isFogged
                )
                .padding(.top, 28)
        }
        .padding(.horizontal, SpeechSpacing.reading)
        .padding(.top, 20)
        .padding(.bottom, 12)
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
        guard let relay = MintClient.makeIfConfigured(uuid: model.account.accountUUID) else {
            errorMessage = "Reading transcription needs the local server."
            return
        }

        isPreparing = true
        countdownRemaining = 3
        VoiceOrbPreloader.warmup()
        defer {
            isPreparing = false
            countdownRemaining = nil
        }

        let engine = GrokTranscriptionEngine(
            relayBase: relay.base,
            bearerToken: relay.uuid.uuidString
        )
        model.speechEngineKind = .grokVoiceTranscribe
        engine.setContextualPhrases(ReadingSession.contextualPhrases(for: passage, fromIndex: 0))
        let prepareTask = Task {
            try await engine.prepareIfNeeded(locale: Locale(identifier: "en-US"))
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
                preference: .autoPreferSpeechTranscriber
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

/// Passage words with a single underline on the word being spoken.
private struct ReadingFollowAlong: View {
    let words: [ScriptWord]
    let currentWordID: String?
    let reduceMotion: Bool
    let dimmed: Bool

    var body: some View {
        WordWrapLayout(spacing: 8, lineSpacing: 14) {
            ForEach(words) { word in
                let isCurrent = word.id == currentWordID
                Text(word.surface)
                    .font(.system(size: 22, weight: isCurrent ? .semibold : .regular, design: .serif))
                    .foregroundStyle(dimmed ? .tertiary : .primary)
                    .underline(isCurrent, color: dimmed ? Color.secondary : Color.primary)
                    .id(word.id)
                    .accessibilityAddTraits(isCurrent ? .isSelected : [])
            }
        }
        .animation(reduceMotion ? nil : SpeechMotion.follow, value: currentWordID)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(words.map(\.surface).joined(separator: " "))
    }
}

/// Left-to-right wrapping rows. Used so each passage word can take its own underline.
private struct WordWrapLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let rows = rows(in: width, subviews: subviews)
        let height = rows.reduce(CGFloat(0)) { $0 + $1.height }
            + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(in: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indexes {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indexes: [Int]
        var height: CGFloat
    }

    private func rows(in width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var indexes: [Int] = []
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let nextWidth = indexes.isEmpty ? size.width : rowWidth + spacing + size.width
            if !indexes.isEmpty, width > 0, nextWidth > width {
                rows.append(Row(indexes: indexes, height: rowHeight))
                indexes = [index]
                rowWidth = size.width
                rowHeight = size.height
            } else {
                indexes.append(index)
                rowWidth = nextWidth
                rowHeight = max(rowHeight, size.height)
            }
        }
        if !indexes.isEmpty {
            rows.append(Row(indexes: indexes, height: rowHeight))
        }
        return rows
    }
}
