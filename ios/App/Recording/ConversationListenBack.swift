import Foundation
import SpeechAppKit

/// Records the user's side of a conversation for listen-back.
///
/// Only audio from while the talk is live is written, so the file, the feedback
/// transcriber, and partner turns all share one timeline: seconds of audio written.
@MainActor
final class ConversationListenBack {
    private let recorder = TakeRecorder()
    private let transcriber: FeedbackTranscriber
    private let mouth: LiveConversationMouth
    private var micTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?
    private var partnerTurns: [PartnerTurn] = []
    private var openPartnerStart: TimeInterval?
    private var heardWords: [RecordedWord] = []
    /// Answer-window indices already reported to the session (one slip per answer).
    private var notifiedLanguageAnswers = Set<Int>()
    /// Fired when a qualifying non-English span appears in an answer.
    var onLanguageSlip: ((TimeInterval) -> Void)?

    init(mouth: LiveConversationMouth, relayBase: URL, bearerToken: String) {
        self.mouth = mouth
        transcriber = FeedbackTranscriber(relayBase: relayBase, bearerToken: bearerToken)
    }

    /// `isLive` says whether the talk is running (not paused, not over).
    func start(isLive: @escaping @MainActor () -> Bool) async {
        try? recorder.start()
        transcriber.onFinalWords = { [weak self] batch in
            self?.considerLanguage(batch)
        }
        await transcriber.start()
        let recorder = recorder
        let transcriber = transcriber
        micTask = Task { @MainActor [mouth] in
            for await chunk in mouth.micChunks {
                guard isLive() else { continue }
                recorder.append(chunk)
                transcriber.append(chunk)
            }
        }
        playbackTask = Task { @MainActor [weak self, mouth] in
            for await event in mouth.partnerPlayback {
                self?.note(event)
            }
        }
    }

    private func note(_ event: LiveConversationMouth.PartnerPlayback) {
        let now = recorder.writtenSeconds
        switch event {
        case .started:
            openPartnerStart = now
        case .finished(let transcript):
            let start = openPartnerStart ?? now
            openPartnerStart = nil
            partnerTurns.append(PartnerTurn(text: transcript, start: start, end: max(start, now)))
        }
    }

    private func considerLanguage(_ batch: [RecordedWord]) {
        heardWords.append(contentsOf: batch)
        // Scan every answer window. Streaming STT often finishes after the partner
        // has already replied; limiting to "words after last partner end" dropped
        // those slips, so the live nudge never reached its turn threshold.
        for slip in ConversationMarkers.liveOtherLanguageSlips(
            words: heardWords,
            partnerTurns: partnerTurns,
            alreadyNotified: notifiedLanguageAnswers
        ) {
            notifiedLanguageAnswers.insert(slip.index)
            onLanguageSlip?(slip.end)
        }
    }

    /// Stops recording and starts saving in the background. Returns the recording id.
    func finish(report: ConversationReport) -> UUID? {
        stopPumps()
        if let start = openPartnerStart {
            partnerTurns.append(PartnerTurn(text: "", start: start, end: recorder.writtenSeconds))
            openPartnerStart = nil
        }
        let duration = recorder.writtenSeconds
        guard let rawURL = recorder.stop(), duration > 0 else {
            discardTranscriber()
            return nil
        }
        let id = UUID()
        let turns = partnerTurns
        let transcriber = transcriber
        Task { @MainActor in
            let heard = await transcriber.finish()
            let words = ConversationMarkers.userWords(heard, partnerTurns: turns)
            SingleTakeRecording.finalizeAndSave(
                rawURL: rawURL,
                content: .init(
                    id: id,
                    format: .conversation,
                    topic: turns.first?.text.isEmpty == false ? turns[0].text : "Conversation",
                    lines: report.lines.map { MonologueReport.Line(label: $0.label, value: $0.value) },
                    words: words,
                    durationSeconds: duration,
                    markers: ConversationMarkers.build(words: words, partnerTurns: turns, durationSeconds: duration),
                    partnerTurns: turns
                )
            )
        }
        return id
    }

    /// Crisis, dropped call, or leaving early: keep nothing.
    func discard() {
        stopPumps()
        if let rawURL = recorder.stop() {
            try? FileManager.default.removeItem(at: rawURL)
        }
        discardTranscriber()
    }

    private func stopPumps() {
        micTask?.cancel()
        micTask = nil
        playbackTask?.cancel()
        playbackTask = nil
        transcriber.onFinalWords = nil
    }

    private func discardTranscriber() {
        let transcriber = transcriber
        Task { @MainActor in _ = await transcriber.finish() }
    }
}
