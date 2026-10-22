import Foundation
import SpeechAppKit

/// Records the microphone for listen-back, and the partner audio that finished
/// playing, so the saved file can fill the holes where the partner spoke.
///
/// Only audio from while the talk is live is written. The file, the feedback
/// transcriber, and partner turns share one timeline: seconds of audio written.
@MainActor
final class ConversationListenBack {
    private let recorder = TakeRecorder()
    private let transcriber: FeedbackTranscriber
    private let mouth: LiveConversationMouth
    private var micTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?
    private var partnerTurns: [PartnerTurn] = []
    private var partnerSpans: [PartnerAudioSpan] = []
    /// Where the next finished partner buffer lands on the mic clock.
    private var partnerCursor: TimeInterval?
    private var openPartnerStart: TimeInterval?
    private var heardWords: [RecordedWord] = []
    /// Answer-window indices already reported to the session (one slip per answer).
    private var notifiedLanguageAnswers = Set<Int>()
    /// Fired when a qualifying non-English span appears in an answer.
    var onLanguageSlip: ((TimeInterval) -> Void)?

    init(mouth: LiveConversationMouth, apiKey: String) {
        self.mouth = mouth
        transcriber = FeedbackTranscriber(apiKey: apiKey)
    }

    /// `isLive` says whether the talk is running (not paused, not over).
    func start(isLive: @escaping @MainActor () -> Bool) async {
        try? recorder.start()
        // Countdown is not part of the take. The session turns capture on at talking.
        recorder.setWriting(false)
        let recorder = recorder
        mouth.setMicListener { chunk in
            recorder.append(chunk)
        }
        setCapturing(isLive())
        transcriber.onFinalWords = { [weak self] batch in
            self?.considerLanguage(batch)
        }
        await transcriber.start()
        setCapturing(isLive())
        let transcriber = transcriber
        micTask = Task { @MainActor [mouth] in
            for await chunk in mouth.micChunks {
                guard isLive() else { continue }
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
            partnerCursor = now
        case .played(let samples, let sampleRate):
            guard sampleRate > 0, !samples.isEmpty else { return }
            let start = partnerCursor ?? openPartnerStart ?? now
            let seconds = Double(samples.count) / sampleRate
            partnerSpans.append(PartnerAudioSpan(start: start, sampleRate: sampleRate, samples: samples))
            partnerCursor = start + seconds
        case .interrupted:
            partnerSpans = ListenBackMix.trimming(partnerSpans, heardThrough: now)
            if let cursor = partnerCursor, cursor > now {
                partnerCursor = now
            }
        case .finished(let transcript):
            let start = openPartnerStart ?? now
            openPartnerStart = nil
            partnerCursor = nil
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

    /// True while the talk itself is being recorded. Countdown and pause stay out.
    func setCapturing(_ on: Bool) {
        recorder.setWriting(on)
    }

    /// Stops recording and starts saving in the background. Returns the recording id.
    func finish(report: ConversationReport, inLibrary: Bool = true) -> UUID? {
        stopPumps()
        // Chunks are placed when they are queued, which can run ahead of the
        // speaker. Keep only what the mic clock has reached.
        let heardThrough = recorder.writtenSeconds
        partnerSpans = ListenBackMix.trimming(partnerSpans, heardThrough: heardThrough)
        if let start = openPartnerStart {
            partnerTurns.append(PartnerTurn(text: "", start: start, end: heardThrough))
            openPartnerStart = nil
            partnerCursor = nil
        }
        guard let rawURL = recorder.stop() else {
            discardTranscriber()
            return nil
        }
        let duration = recorder.writtenSeconds
        guard duration > 0 else {
            try? FileManager.default.removeItem(at: rawURL)
            discardTranscriber()
            return nil
        }
        let id = UUID()
        let spans = partnerSpans
        partnerSpans = []
        // Partner words stay on the turn. Markers only see the user's words.
        let turns = partnerTurns.map { turn in
            PartnerTurn(
                text: turn.text,
                start: turn.start,
                end: turn.end,
                words: PartnerWordTiming.words(text: turn.text, start: turn.start, end: turn.end)
            )
        }
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
                    partnerTurns: turns,
                    inLibrary: inLibrary
                ),
                partnerSpans: spans
            )
        }
        return id
    }

    /// Crisis, dropped call, or leaving early: keep nothing.
    func discard() {
        stopPumps()
        partnerSpans = []
        partnerCursor = nil
        if let rawURL = recorder.stop() {
            try? FileManager.default.removeItem(at: rawURL)
        }
        discardTranscriber()
    }

    private func stopPumps() {
        mouth.setMicListener(nil)
        // Waits for mic chunks already handed over, then stops accepting more.
        recorder.setWriting(false)
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
