import Combine
import SwiftUI
import SpeechAppKit

struct ConversationSessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var session: ConversationSession?
    @State private var mouth: FakeConversationMouth?
    @State private var errorMessage: String?
    @State private var countdownRemaining: Int?
    @State private var showStopConfirm = false
    @State private var didRouteFinish = false
    @State private var eventPump: Task<Void, Never>?
    @State private var debugLoop: Task<Void, Never>?

    private var phase: ConversationPhase {
        session?.phase ?? .idle
    }

    private var isLive: Bool {
        phase == .talking || phase == .wrapping || phase == .connecting
    }

    private var isPaused: Bool {
        phase == .paused
    }

    private var isFogged: Bool {
        countdownRemaining != nil
    }

    private var showsControls: Bool {
        switch phase {
        case .connecting, .talking, .paused, .wrapping: true
        default: false
        }
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

            liveCanvas
                .blur(radius: fogBlurRadius)
                .overlay {
                    Color.black.opacity(fogWashOpacity)
                        .allowsHitTesting(false)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !isFogged {
                        bottomChrome
                    }
                }
                .accessibilityHidden(isFogged)
                .allowsHitTesting(!isFogged)

            if isFogged {
                ReadingCountdownOverlay(
                    remaining: countdownRemaining,
                    instruction: "Take a deep breath. Talk when you're ready."
                )
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle, value: isFogged)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle, value: phase)
        .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.65), trigger: countdownRemaining)
        .navigationTitle("Conversation")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Stop this conversation?",
            isPresented: $showStopConfirm,
            titleVisibility: .visible
        ) {
            Button("Stop", role: .destructive) {
                Task { await confirmStop() }
            }
            Button("Keep talking", role: .cancel) {}
        }
        .task { await beginSession() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            Task { await onWallClockTick() }
        }
        .onChange(of: phase) { _, _ in
            routeIfFinished()
        }
        .onDisappear {
            tearDownIfLeaving()
        }
    }

    private var liveCanvas: some View {
        VStack(alignment: .leading, spacing: SpeechSpacing.related) {
            Text("AI partner")
                .font(.footnote)
                .foregroundStyle(isFogged ? .tertiary : .secondary)

            AuroraPresenceView(
                energy: 0,
                isLive: phase == .talking,
                isHearingSpeech: false
            )

            Spacer(minLength: 0)

            if isPaused {
                Text("Paused — still here.")
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, SpeechSpacing.page)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
    }

    @ViewBuilder
    private var actionRow: some View {
        if showsControls {
            HStack(spacing: 12) {
                Button {
                    if isPaused {
                        session?.resume()
                    } else {
                        session?.pause()
                    }
                } label: {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 52, height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.tertiarySystemFill))
                        )
                }
                .buttonStyle(.plain)
                .disabled(phase != .talking && !isPaused)
                .accessibilityLabel(isPaused ? "Resume" : "Pause")

                Button("Stop") {
                    session?.requestStop()
                    showStopConfirm = true
                }
                .buttonStyle(SpeechPrimaryButtonStyle(isDestructive: true))
            }
        }
    }

    private func beginSession() async {
        guard session == nil else { return }
        errorMessage = nil
        didRouteFinish = false

        do {
            let built = try makeSession()
            session = built.session
            mouth = built.mouth
            startEventPump(session: built.session, mouth: built.mouth)

            built.session.beginCountdown()
            for n in [3, 2, 1] {
                try Task.checkCancellation()
                countdownRemaining = n
                try await Task.sleep(for: .seconds(1))
            }
            countdownRemaining = nil

            try Task.checkCancellation()
            // Send-muted: do not mint OpenAI. Fake mouth only.
            try await built.session.countdownReachedZero(ephemeralKey: "debug")

            try await Task.sleep(for: .milliseconds(300))
            try Task.checkCancellation()
            // connect() does not auto-yield — drive sessionUpdated then first audioDelta.
            built.mouth.emit(.sessionUpdated)
            built.mouth.emit(.audioDelta)

            #if DEBUG
            startDebugUserLoop(session: built.session, mouth: built.mouth)
            #endif
        } catch is CancellationError {
            countdownRemaining = nil
        } catch {
            countdownRemaining = nil
            errorMessage = error.localizedDescription
        }
    }

    private func makeSession() throws -> (session: ConversationSession, mouth: FakeConversationMouth) {
        let deck = try StanceDeck.loadBundled()
        let bank = try OpenPromptBank.loadBundled()
        guard !bank.prompts.isEmpty else {
            throw ConversationSessionError.missingOpens
        }

        var rng = SplitMix64(seed: UInt64.random(in: 1...UInt64.max))
        let stance = deck.sample(rng: &rng).views.joined(separator: "\n")
        let openQuestion = bank.prompts[Int(rng.next() % UInt64(bank.prompts.count))]
        let mouth = FakeConversationMouth()

        #if DEBUG
        let cap: TimeInterval = 300
        #else
        let cap: TimeInterval = 15 * 60
        #endif

        let session = ConversationSession(
            time: SystemTimeSource(),
            mouth: mouth,
            cap: cap,
            prefix: FrozenPersona.prefix,
            stance: stance,
            openQuestion: openQuestion
        )
        return (session, mouth)
    }

    private func startEventPump(session: ConversationSession, mouth: FakeConversationMouth) {
        eventPump?.cancel()
        eventPump = Task { @MainActor in
            for await event in mouth.events {
                await session.handle(event)
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
                session.ingestUserText("hello")
                session.noteUserSpeech(seconds: 1)
                mouth.emit(.speechStopped)
            }
        }
    }
    #endif

    private func onWallClockTick() async {
        await session?.tick()
        routeIfFinished()
    }

    private func confirmStop() async {
        debugLoop?.cancel()
        await session?.confirmStop()
        routeIfFinished()
    }

    private func routeIfFinished() {
        guard !didRouteFinish, let session else { return }
        switch session.phase {
        case .crisis:
            didRouteFinish = true
            model.presentCrisis(possibleMinorFlag: session.possibleMinorFlag)
        case .report, .dropped:
            guard let report = session.report else { return }
            didRouteFinish = true
            model.finishConversation(
                report: report,
                possibleMinorFlag: session.possibleMinorFlag
            )
        default:
            break
        }
    }

    private func tearDownIfLeaving() {
        eventPump?.cancel()
        eventPump = nil
        debugLoop?.cancel()
        debugLoop = nil
        countdownRemaining = nil

        switch model.route {
        case .conversationReport, .crisis:
            return
        default:
            break
        }

        didRouteFinish = true
        guard let session else { return }
        switch session.phase {
        case .idle, .report, .crisis, .dropped:
            break
        default:
            Task { await session.confirmStop() }
        }
    }
}

private enum ConversationSessionError: LocalizedError {
    case missingOpens

    var errorDescription: String? {
        switch self {
        case .missingOpens: "Opening prompts didn’t load."
        }
    }
}
