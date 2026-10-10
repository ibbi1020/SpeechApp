import Foundation

/// Listen-back markers for Conversation: long pauses, filler clusters, and restarts
/// inside an answer, and slow starts after the partner stops.
///
/// Slow start: people usually answer within about 0.5 s; beginner L2 speakers average
/// about 1 s with a spread of about 1.25 s (Wehrle et al., L2 Map Task). Gaps from
/// 0.7 s on start to carry meaning for listeners (Kendrick & Torreira 2015). 2 s is
/// past a beginner's normal range, so it marks a real freeze, not normal L2 timing.
public enum ConversationMarkers {
    public static let slowStartThreshold: TimeInterval = 2.0

    /// Words from the user's microphone only. Anything said while the partner was
    /// playing is treated as echo the voice processing missed.
    public static func userWords(_ words: [RecordedWord], partnerTurns: [PartnerTurn]) -> [RecordedWord] {
        words.filter { word in
            let middle = (word.start + word.end) / 2
            return !partnerTurns.contains { middle >= $0.start && middle <= $0.end }
        }
    }

    public static func candidates(
        words: [RecordedWord],
        partnerTurns: [PartnerTurn],
        durationSeconds: TimeInterval
    ) -> [ReviewMarker] {
        let turns = partnerTurns.sorted { $0.start < $1.start }
        let mine = userWords(words, partnerTurns: turns).sorted { $0.start < $1.start }

        // Split the user's words into answers: everything between two partner turns.
        var answers: [[RecordedWord]] = Array(repeating: [], count: turns.count + 1)
        for word in mine {
            let index = turns.filter { $0.end <= word.start }.count
            answers[index].append(word)
        }

        var markers: [ReviewMarker] = []
        for answer in answers where !answer.isEmpty {
            markers.append(contentsOf: ReviewMarkers.pauseMarkers(words: answer, includeLeading: false))
            markers.append(contentsOf: ReviewMarkers.fillerClusterMarkers(words: answer))
            markers.append(contentsOf: ReviewMarkers.restartMarkers(words: answer))
        }

        for (index, turn) in turns.enumerated() {
            guard let first = answers[index + 1].first else { continue }
            // Grok word starts sit a little inside the sound.
            let wait = first.start - turn.end - ReviewMarkers.wordEdgePadding / 2
            guard wait >= slowStartThreshold - ReviewMarkers.timeSlack else { continue }
            markers.append(ReviewMarker(
                kind: .slowStart,
                start: turn.end,
                end: first.start,
                score: wait,
                note: slowStartNote(seconds: wait, question: turn.text)
            ))
        }
        _ = durationSeconds
        return markers.sorted { $0.start < $1.start }
    }

    public static func build(
        words: [RecordedWord],
        partnerTurns: [PartnerTurn],
        durationSeconds: TimeInterval
    ) -> [ReviewMarker] {
        ReviewMarkers.select(
            candidates(words: words, partnerTurns: partnerTurns, durationSeconds: durationSeconds),
            durationSeconds: durationSeconds
        )
    }

    static func slowStartNote(seconds: TimeInterval, question: String) -> String {
        let secs = max(1, Int(seconds.rounded()))
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let lead: String
        if trimmed.isEmpty {
            lead = "You took \(secs) seconds to start answering."
        } else {
            let short = trimmed.count > 60 ? String(trimmed.prefix(57)) + "…" : trimmed
            lead = "After “\(short)”, you took \(secs) seconds to start."
        }
        return lead + " Listen: were you deciding what to say, or finding the first words?"
    }
}
