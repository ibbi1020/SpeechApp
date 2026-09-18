import AVFoundation
import SwiftUI
import SpeechAppKit

struct ReadingSessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let passage: Passage

    @State private var session: ReadingSession?
    @State private var errorMessage: String?
    @State private var isStarting = false
    @State private var stopPulse = false
    @State private var wordFrames: [String: CGRect] = [:]
    @State private var viewportFrame: CGRect = .zero
    @State private var lastScrollUptime: TimeInterval = 0

    private var isLive: Bool {
        session?.phase == .running || session?.phase == .stalled
    }

    var body: some View {
        ZStack {
            SpeechScreenBackground()

            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(passage.title)
                                .font(.title2.weight(.bold))
                                .tracking(-0.3)
                            Text("\(passage.length.label) · \(passage.wordCount) words · ~\(passage.estimatedSeconds)s")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            PassageTextView(
                                passage: passage,
                                currentWordID: session?.presenceWordID ?? session?.currentWordID,
                                hintNextWordID: session?.hintNextWordID,
                                heardWordIDs: Set(session?.heardWordIDs ?? []),
                                provisionalMatchedIDs: Set(session?.provisionalMatchedIDs ?? []),
                                presenceTrailIDs: Set(session?.presenceTrailIDs ?? []),
                                liveSkipMarks: session?.liveSkipMarks ?? [],
                                isHearingSpeech: session?.isHearingSpeech ?? false,
                                speechEnergy: session?.speechEnergy ?? 0,
                                optimisticWordProgress: session?.presenceProgress ?? 0,
                                isLive: isLive
                            )
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .padding(.bottom, 140)
                    }
                    .coordinateSpace(name: "passageScroll")
                    .onPreferenceChange(WordFramePreferenceKey.self) { wordFrames = $0 }
                    .background {
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: PassageViewportPreferenceKey.self,
                                value: geo.frame(in: .global)
                            )
                        }
                    }
                    .onPreferenceChange(PassageViewportPreferenceKey.self) { viewportFrame = $0 }
                    .onChange(of: session?.presenceWordID) { _, newID in
                        guard let newID else { return }
                        requestComfortScroll(to: newID, proxy: proxy)
                    }
                    .onChange(of: session?.currentWordID) { _, newID in
                        // ASR catch-up may jump past presence — keep viewport honest.
                        guard let newID else { return }
                        if session?.presenceWordID == nil || session?.presenceWordID == newID {
                            requestComfortScroll(to: newID, proxy: proxy)
                        }
                    }
                }

                bottomChrome
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Passages") {
                    model.chooseAnotherPassage()
                }
                .disabled(isLive)
            }
        }
        .onAppear {
            if session == nil {
                session = ReadingSession(
                    passage: passage,
                    ledgerAverageRate: model.ledger.averageSpeechRate
                )
            }
        }
    }

    /// Reading-app scroll: ease to upper-middle, throttle, only when caret leaves comfort band.
    private func requestComfortScroll(to wordID: String, proxy: ScrollViewProxy) {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastScrollUptime < 0.35 { return }

        let shouldScroll: Bool
        if viewportFrame.width > 1, let frame = wordFrames[wordID] {
            // Comfort band ≈ middle third of the visible scroll viewport.
            let bandMin = viewportFrame.minY + viewportFrame.height * 0.28
            let bandMax = viewportFrame.minY + viewportFrame.height * 0.62
            let midY = frame.midY
            shouldScroll = midY < bandMin || midY > bandMax
        } else {
            // First layout / unknown geometry — scroll gently once.
            shouldScroll = true
        }
        guard shouldScroll else { return }

        lastScrollUptime = now
        session?.noteScroll(to: wordID, reason: "comfort")
        let anchor = UnitPoint(x: 0.5, y: 0.35)
        if reduceMotion {
            proxy.scrollTo(wordID, anchor: anchor)
        } else {
            withAnimation(SpeechMotion.scroll) {
                proxy.scrollTo(wordID, anchor: anchor)
            }
        }
    }

    private var bottomChrome: some View {
        VStack(spacing: 12) {
            if isLive {
                Text(
                    session?.showKeepGoingHint == true
                        ? "Still with you — try the next word if this one won’t lock."
                        : "We’re with you on each word — not grading pronunciation yet."
                )
                    .font(.caption)
                    .foregroundStyle(session?.showKeepGoingHint == true ? Color.accentColor : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                    .animation(SpeechMotion.follow, value: session?.showKeepGoingHint)
            }

            if session?.showStallNudge == true {
                stallBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if isLive {
                Button("Stop") {
                    stopPulse.toggle()
                    Task { await stopSession() }
                }
                .buttonStyle(SpeechPrimaryButtonStyle(isDestructive: true))
                .sensoryFeedback(.impact(weight: .medium), trigger: stopPulse)
            } else {
                Button(isStarting ? "Starting…" : "Start") {
                    Task { await startSession() }
                }
                .buttonStyle(SpeechPrimaryButtonStyle())
                .disabled(isStarting)
                .opacity(isStarting ? 0.7 : 1)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.06), radius: 16, y: -4)
                .ignoresSafeArea(edges: .bottom)
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle, value: session?.showStallNudge)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : SpeechMotion.follow, value: isLive)
    }

    private var stallBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Take your time")
                    .font(.subheadline.weight(.semibold))
                Text("Tap when you’re ready to continue")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("I’m ready") {
                session?.dismissStallNudge()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
    }

    private func startSession() async {
        errorMessage = nil
        isStarting = true
        defer { isStarting = false }

        #if os(iOS)
        let granted = await requestMic()
        guard granted else {
            errorMessage = "Microphone permission is required."
            return
        }
        do {
            try await LiveTranscriptionEngine.requestSpeechAuthorization()
        } catch {
            errorMessage = "Speech recognition permission is required (Settings → SpeechApp)."
            return
        }
        #endif

        let engine = LiveTranscriptionEngine()
        #if os(iOS)
        let source: any AudioSource = MicAudioSource()
        #else
        errorMessage = "Live mic requires iOS."
        return
        #endif

        let preference: LiveTranscriptionEngine.EnginePreference
        switch model.speechEngineKind {
        case .speechTranscriber:
            preference = .speechTranscriber
        case .dictationTranscriber:
            preference = .dictationTranscriber
        default:
            preference = .autoPreferSpeechTranscriber
        }

        do {
            try await session?.start(audioSource: source, engine: engine, preference: preference)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopSession() async {
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

struct PassageTextView: View {
    let passage: Passage
    /// Live caret — presence cursor while reading (may lead ASR).
    let currentWordID: String?
    /// Soft suggestion only — never the caret.
    var hintNextWordID: String? = nil
    /// Sticky optimistic-success trail (never rewinds mid-session).
    var heardWordIDs: Set<String> = []
    var provisionalMatchedIDs: Set<String> = []
    /// Presence walked these; lighter than heard (not locked by ASR).
    var presenceTrailIDs: Set<String> = []
    /// Live skip pills only (not extra / substitute).
    var liveSkipMarks: [LiveMark] = []
    var isHearingSpeech: Bool = false
    var speechEnergy: Float = 0
    var optimisticWordProgress: Double = 0
    var isLive: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var skipBlinkOn = true

    private var skippedIDs: Set<String> {
        Set(liveSkipMarks.compactMap(\.scriptWordID))
    }

    var body: some View {
        PassageFlowLayout(spacing: 6, lineSpacing: 12) {
            ForEach(passage.words) { word in
                KaraokeWordChip(
                    word: word,
                    state: state(for: word),
                    progress: progress(for: word),
                    speechEnergy: word.id == currentWordID ? speechEnergy : 0,
                    skipBlinkOn: skipBlinkOn,
                    reduceMotion: reduceMotion
                )
                .id(word.id)
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: WordFramePreferenceKey.self,
                            value: [word.id: geo.frame(in: .global)]
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .onAppear { startSkipBlinkIfNeeded() }
        .onChange(of: liveSkipMarks.count) { _, _ in startSkipBlinkIfNeeded() }
    }

    private func progress(for word: ScriptWord) -> Double {
        if word.id == currentWordID { return optimisticWordProgress }
        if heardWordIDs.contains(word.id) || provisionalMatchedIDs.contains(word.id) { return 1 }
        if presenceTrailIDs.contains(word.id) { return 1 }
        return 0
    }

    private func state(for word: ScriptWord) -> KaraokeWordState {
        if skippedIDs.contains(word.id) { return .skipped }
        if heardWordIDs.contains(word.id) || provisionalMatchedIDs.contains(word.id) {
            return .heard
        }
        if presenceTrailIDs.contains(word.id) {
            return .presence
        }
        if word.id == currentWordID {
            if isLive && (isHearingSpeech || optimisticWordProgress > 0.02) {
                return .speaking
            }
            return .currentIdle
        }
        if word.id == hintNextWordID {
            return .hintNext
        }
        return .upcoming
    }

    private func startSkipBlinkIfNeeded() {
        guard !skippedIDs.isEmpty else { return }
        guard !reduceMotion else {
            skipBlinkOn = true
            return
        }
        withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
            skipBlinkOn = true
        }
        DispatchQueue.main.async {
            skipBlinkOn = false
        }
    }

    private var accessibilitySummary: String {
        let current = passage.words.first(where: { $0.id == currentWordID })?.surface
        let hint = passage.words.first(where: { $0.id == hintNextWordID })?.surface
        let heardCount = heardWordIDs.count
        let skippedCount = skippedIDs.count
        if let current {
            if let hint {
                return "\(passage.title). Current word: \(current). You can try \(hint) next. Heard \(heardCount). Skipped \(skippedCount)."
            }
            return "\(passage.title). Current word: \(current). Heard \(heardCount). Skipped \(skippedCount)."
        }
        return passage.title
    }
}

private enum KaraokeWordState {
    case upcoming
    case currentIdle
    case speaking
    case heard
    /// Presence walked here — lighter than heard (not ASR-locked).
    case presence
    case skipped
    /// Suggested next word — secondary, not the caret.
    case hintNext
}

/// Per-word karaoke chip — static glyph geometry; feedback is paint-only (Monkeytype-style).
/// Padding, font weight, and capsule size never change with state so the passage does not reflow.
private struct KaraokeWordChip: View {
    let word: ScriptWord
    let state: KaraokeWordState
    let progress: Double
    let speechEnergy: Float
    let skipBlinkOn: Bool
    let reduceMotion: Bool

    /// Fixed for every state — changing weight reflows `PassageFlowLayout`.
    private static let chipFont: Font = .title3.weight(.regular)
    private static let horizontalPad: CGFloat = 6
    private static let verticalPad: CGFloat = 3

    var body: some View {
        Text(word.surface)
            .font(Self.chipFont)
            .foregroundStyle(foreground)
            .padding(.horizontal, Self.horizontalPad)
            .padding(.vertical, Self.verticalPad)
            .background { chipBackground }
            .overlay(alignment: .bottom) { caretUnderline }
            .accessibilityAddTraits(state == .speaking || state == .currentIdle ? .isSelected : [])
            .animation(nil, value: state)
            .animation(reduceMotion ? nil : .linear(duration: 0.05), value: progress)
    }

    private var foreground: Color {
        switch state {
        case .heard: return Color.accentColor
        case .presence: return Color.accentColor.opacity(0.75)
        case .speaking, .currentIdle, .skipped: return .primary
        case .hintNext: return .primary.opacity(0.85)
        case .upcoming: return .primary.opacity(0.55)
        }
    }

    /// Always the same capsule frame; upcoming is clear so layout never jumps when paint appears.
    private var chipBackground: some View {
        Capsule(style: .continuous)
            .fill(fillColor)
            .overlay(alignment: .leading) { progressiveFill }
            .overlay { strokeOverlay }
            .clipShape(Capsule(style: .continuous))
    }

    private var fillColor: Color {
        switch state {
        case .skipped:
            return Color.orange.opacity(skipBlinkOn ? 0.38 : 0.12)
        case .heard:
            return Color.accentColor.opacity(0.28)
        case .presence:
            return Color.accentColor.opacity(0.14)
        case .speaking:
            // Opacity pulse from mic energy — does not change measured size.
            let pulse = reduceMotion ? 0 : Double(speechEnergy) * 0.08
            return Color.accentColor.opacity(0.12 + pulse)
        case .currentIdle:
            return Color.accentColor.opacity(0.08)
        case .hintNext, .upcoming:
            return Color.clear
        }
    }

    @ViewBuilder
    private var progressiveFill: some View {
        switch state {
        case .speaking:
            Capsule(style: .continuous)
                .fill(Color.accentColor.opacity(0.42))
                .scaleEffect(x: max(0.04, progress), y: 1, anchor: .leading)
        case .presence:
            Capsule(style: .continuous)
                .fill(Color.accentColor.opacity(0.22))
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var strokeOverlay: some View {
        switch state {
        case .currentIdle:
            Capsule(style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1.5)
        case .hintNext:
            Capsule(style: .continuous)
                .strokeBorder(
                    Color.accentColor.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1.25, dash: [4, 3])
                )
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var caretUnderline: some View {
        if state == .currentIdle || state == .speaking {
            Capsule()
                .fill(Color.accentColor)
                .frame(height: 2)
                .padding(.horizontal, 2)
                .offset(y: 1)
        }
    }
}

/// Simple left-to-right wrapping layout for passage words (karaoke pills).
struct PassageFlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var height: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + lineSpacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            height = y + rowHeight
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + lineSpacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Scroll comfort-band preferences

private struct WordFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct PassageViewportPreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
