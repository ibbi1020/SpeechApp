import SwiftUI
import SpeechAppKit

struct MonologueSessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var session: MonologueSession?
    @State private var errorMessage: String?
    @State private var showLeaveConfirm = false
    @State private var didRouteFinish = false

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
                session?.confirmLeave()
                routeIfFinished()
            }
            Button("Keep going", role: .cancel) {}
        }
        .task { await setUpSessionIfNeeded() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            Task {
                await session?.tick()
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
            Button("I’m ready") {
                session.ready()
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
                energy: 0,
                mode: .listen,
                animating: session.phase == .taking
            )

            Button {
                session.done()
                routeIfFinished()
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
