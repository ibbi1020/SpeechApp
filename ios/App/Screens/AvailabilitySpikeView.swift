import SwiftUI
import SpeechAppKit

/// Hardware readiness — calm copy, no engine jargon in the headline.
struct AvailabilitySpikeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var statusText = "Checking speech on this phone…"
    @State private var detail = ""
    @State private var isReady = false
    @State private var isWorking = true
    @State private var showPulse = true

    var body: some View {
        ZStack {
            SpeechScreenBackground()

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 24)

                VStack(alignment: .leading, spacing: 18) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(isWorking && showPulse ? 0.14 : 0.08))
                            .frame(width: 72, height: 72)
                            .scaleEffect(isWorking && showPulse && !reduceMotion ? 1.08 : 1)
                            .animation(
                                reduceMotion || !isWorking
                                    ? .default
                                    : .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                                value: showPulse
                            )

                        Image(systemName: isReady ? "checkmark.circle.fill" : "ear.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(isReady ? Color.accentColor : .secondary)
                            .symbolEffect(.bounce, value: isReady)
                    }
                    .frame(maxWidth: .infinity)

                    Text(isReady ? "You’re set" : "Getting ready")
                        .font(.largeTitle.weight(.bold))
                        .tracking(-0.5)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text(statusText)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)

                    if !detail.isEmpty {
                        Text(detail)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 8)
                    }

                    if isWorking {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 28)

                Spacer()

                VStack(spacing: 12) {
            if isReady {
                Button("Choose a passage") {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
                        model.beginReading()
                    }
                }
                .buttonStyle(SpeechPrimaryButtonStyle())
                .sensoryFeedback(.impact(flexibility: .soft), trigger: isReady)
            } else if !isWorking {
                        Button("Try again") {
                            Task { await runCheck() }
                        }
                        .buttonStyle(SpeechSecondaryButtonStyle())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
        .navigationBarHidden(true)
        .task {
            await runCheck()
        }
    }

    private func runCheck() async {
        isWorking = true
        isReady = false
        showPulse = true
        statusText = "Checking speech on this phone…"
        detail = ""

        let availability = await LiveTranscriptionEngine.checkAvailability()
        switch availability {
        case .speechTranscriberReady:
            model.speechEngineKind = .speechTranscriber
            statusText = "On-device listening is ready."
            detail = "Your reading stays on this phone."
            isReady = true
            try? await LiveTranscriptionEngine().prepareIfNeeded()
        case .dictationTranscriberReady:
            model.speechEngineKind = .dictationTranscriber
            statusText = "On-device listening is ready."
            detail = "Your reading stays on this phone."
            isReady = true
            try? await LiveTranscriptionEngine().prepareIfNeeded()
        case .dictationTranscriberNeedsDownload:
            statusText = "Downloading speech support…"
            do {
                try await LiveTranscriptionEngine.ensureDictationAssets()
                model.speechEngineKind = .dictationTranscriber
                statusText = "On-device listening is ready."
                detail = "Speech support installed for English (US)."
                isReady = true
                try? await LiveTranscriptionEngine().prepareIfNeeded()
            } catch {
                model.speechEngineKind = .sfSpeechRecognizerOnDevice
                statusText = "Ready with a backup listener."
                detail = "Download didn’t finish — still on-device, slightly older engine."
                isReady = true
            }
        case .fallbackSFSpeechRecognizer:
            model.speechEngineKind = .sfSpeechRecognizerOnDevice
            statusText = "Ready with the on-device backup listener."
            detail = "Same experience; older speech engine on this hardware."
            isReady = true
        case .unavailable(let message):
            model.speechEngineKind = .unavailable
            statusText = "Speech isn’t available on this phone."
            detail = message
            isReady = false
        }

        model.availabilityMessage = statusText
        isWorking = false
        showPulse = false
    }
}
