import AVFoundation
import Combine
import OSLog
import SwiftUI
import SpeechAppKit

struct ReadingSessionView: View {
    private static let log = Logger(subsystem: "com.speechapp", category: "ReadingSessionView")

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let passage: Passage

    @State private var session: ReadingSession?
    @State private var errorMessage: String?
    @State private var isPreparing = false
    /// When the connecting orb appeared. The slow line uses this clock.
    @State private var connectingStarted: Date?
    @State private var startTask: Task<Void, Never>?
    @State private var startPulse = false
    @State private var displayIndex = 0
    @State private var caretGeneration = 0
    @State private var layoutReady = false
    @State private var wordTops: [String: CGFloat] = [:]
    @State private var lastScrolledLine: CGFloat?
    @State private var takeRecorder: TakeRecorder?
    @State private var feedbackTranscriber: FeedbackTranscriber?

    private var isLive: Bool {
        session?.phase == .running || session?.phase == .stalled
    }

    private var isPaused: Bool {
        session?.phase == .paused
    }

    private var isFinishing: Bool {
        session?.phase == .finishing
    }

    /// Fog until the microphone is listening. No count.
    private var isFogged: Bool {
        isPreparing
    }

    private var fogBlurRadius: CGFloat {
        isFogged && !reduceTransparency ? SpeechCountdown.fogBlurRadius : 0
    }

    private var displayWordID: String? {
        guard isLive, passage.words.indices.contains(displayIndex) else { return nil }
        return passage.words[displayIndex].id
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
                .blur(radius: fogBlurRadius)
                .overlay {
                    Color.black.opacity(fogWashOpacity)
                        .allowsHitTesting(false)
                }
                .accessibilityHidden(isFogged)
                .allowsHitTesting(!isFogged)
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    bottomChrome
                }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle, value: isFogged)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .speechBarChrome()
        .speechBottomBlur(bar: false)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                SpeechBarButton(systemName: "chevron.left", label: "Back") {
                    dismiss()
                }
            }
        }
        .background(SpeechEdgeSwipe())
        .background {
            CaretClock(
                wordCount: passage.words.count,
                generation: caretGeneration,
                isLive: isLive,
                session: session,
                reduceMotion: reduceMotion,
                displayIndex: $displayIndex,
                layoutReady: $layoutReady
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { note in
            if SessionInterruption.shouldPause(note) {
                session?.pause()
            }
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
            isPreparing = false
            connectingStarted = nil
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
            .coordinateSpace(.named("reading-passage"))
            .onPreferenceChange(WordLineTops.self) { tops in
                guard layoutReady, tops != wordTops else { return }
                wordTops = tops
                scrollIfLineChanged(proxy: proxy)
            }
            .onChange(of: displayIndex) { _, _ in
                scrollIfLineChanged(proxy: proxy)
            }
        }
    }

    /// Scroll when the underlined word moves to another line, not on every word.
    private func scrollIfLineChanged(proxy: ScrollViewProxy) {
        guard isLive, passage.words.indices.contains(displayIndex), displayIndex >= 12 else { return }
        let id = passage.words[displayIndex].id
        guard let top = wordTops[id] else { return }
        let line = (top / 8).rounded()
        guard line != lastScrolledLine else { return }
        lastScrolledLine = line
        if reduceMotion {
            proxy.scrollTo(id, anchor: .center)
        } else {
            withAnimation(SpeechMotion.scroll) {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    private var passageBody: some View {
        ReadingFollowAlong(
            words: passage.words,
            currentWordID: displayWordID,
            dimmed: isFogged
        )
        .equatable()
        .padding(.horizontal, SpeechSpacing.reading)
        .padding(.top, SpeechSpacing.section)
        .padding(.bottom, SpeechSpacing.related)
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
        if isLive || isPaused || isFinishing || isPreparing {
            liveControlRow
        } else {
            Button("Start") {
                startPulse.toggle()
                startTask?.cancel()
                startTask = Task { await beginStart() }
            }
            .buttonStyle(SpeechStartButtonStyle())
            .sensoryFeedback(.impact(flexibility: .soft), trigger: startPulse)
        }
    }

    private var liveControlRow: some View {
        SessionOrbBar(
            phase: isPreparing ? .connecting : .listening,
            connectingStarted: isPreparing ? connectingStarted : nil,
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
            }
            .buttonStyle(SpeechIconCircleStyle(diameter: SpeechIconCircleStyle.session))
            .disabled(isPreparing || isFinishing)
            .opacity(isPreparing ? 0 : 1)
            .allowsHitTesting(!isPreparing)
            .accessibilityHidden(isPreparing)
            .accessibilityLabel(isPaused ? "Resume" : "Pause")
        } trailing: {
            Button {
                Task { await stopSession() }
            } label: {
                Image(systemName: "checkmark")
            }
            .buttonStyle(SpeechIconCircleStyle(diameter: SpeechIconCircleStyle.session, fill: .red))
            .disabled(isPreparing || isFinishing)
            .opacity(isPreparing ? 0 : 1)
            .allowsHitTesting(!isPreparing)
            .accessibilityHidden(isPreparing)
            .accessibilityLabel("Done")
        }
        .opacity(isFinishing ? 0.7 : 1)
    }

    private func beginStart() async {
        errorMessage = nil

        #if os(iOS)
        let granted = await requestMic()
        guard granted else {
            Self.log.error("microphone permission denied")
            errorMessage = UserFacingFailure.microphoneOff
            return
        }
        isPreparing = true
        connectingStarted = Date()
        VoiceOrbPreloader.warmup()
        defer {
            isPreparing = false
            connectingStarted = nil
        }

        let apiKey = XAIDirectKey.load()
        let phrases = ReadingSession.contextualPhrases(for: passage, fromIndex: 0)
        let engine: any TranscriptionEngine
        do {
            engine = try await LiveSpeech.engine(apiKey: apiKey, phrases: phrases)
        } catch is CancellationError {
            return
        } catch {
            UserFacingFailure.log(error, context: "reading start")
            errorMessage = UserFacingFailure.message(for: error)
            return
        }

        do {
            try Task.checkCancellation()
            caretGeneration += 1
            displayIndex = 0
            lastScrolledLine = nil
            let source = MicAudioSource()
            let recorder = TakeRecorder()
            try? recorder.start()
            takeRecorder = recorder
            if engine.engineKind == .grokVoiceTranscribe, let apiKey {
                let transcriber = FeedbackTranscriber(apiKey: apiKey)
                await transcriber.start()
                feedbackTranscriber = transcriber
                session?.onRecordedChunk = { chunk in
                    recorder.append(chunk)
                    transcriber.append(chunk)
                }
            } else {
                session?.onRecordedChunk = { chunk in
                    recorder.append(chunk)
                }
            }
            try await session?.start(
                audioSource: source,
                engine: engine,
                preference: .autoPreferSpeechTranscriber
            )
            model.speechEngineKind = session?.engineKind ?? engine.engineKind
        } catch is CancellationError {
            await engine.stop()
        } catch {
            await engine.stop()
            UserFacingFailure.log(error, context: "reading start")
            errorMessage = UserFacingFailure.message(for: error)
        }
        #else
        Self.log.error("live mic is unavailable off iOS")
        errorMessage = UserFacingFailure.needsIPhone
        #endif
    }

    private func stopSession() async {
        startTask?.cancel()
        guard let session else { return }
        let report = await session.stop()
        session.onRecordedChunk = nil
        let recordingID = saveRecording(session: session, report: report)
        model.finish(report: report, recordingID: recordingID)
    }

    /// Starts saving the take for listen-back and returns its id when there is audio.
    /// The score is already on `report`. Unhinted words finish in the background, under the ring.
    private func saveRecording(session: ReadingSession, report: SessionReport) -> UUID? {
        guard let recorder = takeRecorder else { return nil }
        takeRecorder = nil
        guard let rawURL = recorder.stop() else { return nil }
        let duration = recorder.writtenSeconds
        guard duration > 0 else {
            try? FileManager.default.removeItem(at: rawURL)
            return nil
        }
        let id = UUID()
        let fallback = session.spokenWords
        let transcriber = feedbackTranscriber
        feedbackTranscriber = nil
        let readingPassage = passage
        let inLibrary = RecordingsService.keepRecordings
        SaveProgressBoard.begin(
            id: id,
            durationSeconds: duration,
            willClean: SaveProgress.needsCleaning(
                durationSeconds: duration,
                runsOnSimulator: SaveProgressBoard.runsOnSimulator
            ),
            includesTranscription: transcriber != nil
        )
        Task { @MainActor in
            await SingleTakeRecording.finalizeAndSave(id: id, rawURL: rawURL) {
                // Unhinted words show what was really said; the hinted live words are the fallback.
                // The file is already being finalized. Markers wait until these words exist.
                var words = fallback
                if let transcriber {
                    SaveProgressBoard.update(id: id, .catchingWords, 0)
                    let heard = await transcriber.finish()
                    if !heard.isEmpty { words = heard }
                    SaveProgressBoard.update(id: id, .catchingWords, 1)
                }
                return .init(
                    id: id,
                    format: .reading,
                    topic: readingPassage.title,
                    lines: [
                        .init(label: "Words read", value: "\(report.matchCount) of \(report.scriptWordCount)"),
                        .init(label: "Time", value: Self.timeLabel(report.durationSeconds)),
                    ],
                    words: words,
                    durationSeconds: duration,
                    markers: ReadingMarkers.build(passage: readingPassage, words: words, durationSeconds: duration),
                    inLibrary: inLibrary
                )
            }
        }
        return id
    }

    private static func timeLabel(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
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

/// Passage words. Same face, size, and current-word mark as listen-back.
private struct ReadingFollowAlong: View, Equatable {
    let words: [ScriptWord]
    let currentWordID: String?
    let dimmed: Bool

    @ScaledMetric(relativeTo: SpeechReading.textStyle) private var size: CGFloat = SpeechReading.size

    /// Lets `.equatable()` skip re-diffing every word when only the mic level
    /// or another piece of chrome changed.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.currentWordID == rhs.currentWordID
            && lhs.dimmed == rhs.dimmed
            && lhs.words.map(\.id) == rhs.words.map(\.id)
    }

    var body: some View {
        WordWrapLayout(
            spacing: SpeechReading.scaledGap(SpeechReading.wordGap, size: size),
            lineSpacing: SpeechReading.scaledGap(SpeechReading.lineGap, size: size)
        ) {
            ForEach(words) { word in
                SpeechReadingWord(
                    text: word.surface,
                    isCurrent: word.id == currentWordID,
                    dimmed: dimmed,
                    size: size
                )
                .id(word.id)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: WordLineTops.self,
                            value: [word.id: proxy.frame(in: .named("reading-passage")).minY]
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(words.map(\.surface).joined(separator: " "))
    }
}

/// Y position of each passage word, so scroll runs when the underline changes line.
private struct WordLineTops: PreferenceKey {
    static var defaultValue: [String: CGFloat] { [:] }

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// Moves the underline after the navigation push has finished.
///
/// A per-frame SwiftUI animation during that push throws
/// "Failed to preempt running transition" and leaves a black screen.
private struct CaretClock: UIViewControllerRepresentable {
    var wordCount: Int
    var generation: Int
    var isLive: Bool
    /// Read on each display-link tick instead of through `body`, so speech and
    /// anchor changes do not re-render the whole passage.
    var session: ReadingSession?
    var reduceMotion: Bool
    @Binding var displayIndex: Int
    @Binding var layoutReady: Bool

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.wordCount = wordCount
        controller.generation = generation
        controller.isLive = isLive
        controller.session = session
        controller.reduceMotion = reduceMotion
        controller.onIndex = { index in
            if displayIndex != index {
                displayIndex = index
            }
        }
        controller.onReady = {
            if !layoutReady {
                layoutReady = true
            }
        }
        controller.sync()
    }

    final class Controller: UIViewController {
        var follow = CaretFollow()
        var wordCount = 0
        var generation = 0
        var isLive = false
        weak var session: ReadingSession?
        var reduceMotion = false
        var onIndex: (Int) -> Void = { _ in }
        var onReady: () -> Void = {}
        private var link: CADisplayLink?
        private var didAppear = false
        private var appliedGeneration = -1

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            didAppear = true
            onReady()
            sync()
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            didAppear = false
            link?.invalidate()
            link = nil
        }

        func sync() {
            guard didAppear else { return }
            if generation != appliedGeneration || follow.wordCount != wordCount {
                appliedGeneration = generation
                follow = CaretFollow(wordCount: max(wordCount, 1))
            }
            if isLive {
                if link == nil {
                    let link = CADisplayLink(target: self, selector: #selector(tick))
                    link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
                    link.add(to: .main, forMode: .common)
                    self.link = link
                }
                link?.isPaused = false
            } else {
                link?.isPaused = true
            }
        }

        @objc private func tick() {
            guard isLive else { return }
            let anchor = session?.caretAnchor ?? CaretAnchor(index: 0, speechEnd: nil, hostTime: 0)
            let speaking = session?.isHearingSpeech == true
            if anchor.hostTime > 0 {
                follow.noteAnchor(
                    index: anchor.index,
                    speechEnd: anchor.speechEnd,
                    hostNow: anchor.hostTime
                )
            }
            follow.tick(
                hostNow: ProcessInfo.processInfo.systemUptime,
                speaking: speaking,
                reduceMotion: reduceMotion
            )
            onIndex(follow.displayWordIndex)
        }
    }
}

