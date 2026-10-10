import Foundation

/// Plain-text descriptions of evaluation results, shared by tests and the CLI.
public enum FeedbackReport {
    public static func describe(_ label: FeedbackLabel) -> String {
        "\(name(label.kind)) \(time(label.start))–\(time(label.end))"
    }

    public static func describe(_ marker: ReviewMarker) -> String {
        "\(name(marker.kind)) \(time(marker.start))–\(time(marker.end)) (score \(String(format: "%.1f", marker.score)) s)"
    }

    public static func name(_ kind: ReviewMarker.Kind) -> String {
        switch kind {
        case .pause: "pause"
        case .fillerCluster: "fillers"
        case .restart: "restart"
        case .skippedWord: "skip"
        case .swappedWord: "swap"
        case .slowStart: "slow start"
        }
    }

    public static func time(_ seconds: TimeInterval) -> String {
        String(format: "%.2fs", seconds)
    }

    /// One line per thing that went wrong. Empty when the result matches the labels.
    public static func problems(
        candidates: FeedbackScore,
        shown: FeedbackScore,
        noteProblem: String? = nil
    ) -> [String] {
        var lines: [String] = []
        for label in candidates.missed {
            lines.append("not detected: \(describe(label))")
        }
        for marker in candidates.extra {
            lines.append("detected but not expected: \(describe(marker))")
        }
        for match in candidates.wrongKind {
            lines.append("wrong kind: expected \(describe(match.label)), got \(describe(match.marker))")
        }
        let notDetected = Set(candidates.missed.map(describe))
        for label in shown.missed where !notDetected.contains(describe(label)) {
            lines.append("detected but hidden by cap/spacing: \(describe(label))")
        }
        let alreadyExtra = Set(candidates.extra.map(describe))
        for marker in shown.extra where !alreadyExtra.contains(describe(marker)) {
            lines.append("shown but should not be: \(describe(marker))")
        }
        if let noteProblem {
            lines.append(noteProblem)
        }
        return lines
    }

    public static func problems(_ result: FeedbackRuleCase.Result) -> [String] {
        problems(candidates: result.candidates, shown: result.shown, noteProblem: result.noteProblem)
    }

    /// For a missed moment, say whether the transcript or the rules are to blame.
    public static func blame(_ label: FeedbackLabel, words: [RecordedWord]) -> String {
        let pad = FeedbackEvaluator.defaultTolerance
        let nearby = words.filter { $0.end >= label.start - pad && $0.start <= label.end + pad }
        let heard = nearby.map(\.surface).joined(separator: " ")
        let heardText = heard.isEmpty ? "nothing" : "“\(heard)”"
        switch label.kind {
        case .pause:
            let ordered = nearby.sorted { $0.start < $1.start }
            var widest: TimeInterval = ordered.first.map { max(0, $0.start - max(0, label.start - pad)) } ?? 0
            if ordered.count > 1 {
                for index in 1..<ordered.count {
                    widest = max(widest, ordered[index].start - ordered[index - 1].end)
                }
            }
            if widest < ReviewMarkers.minimumWordGap {
                return "transcript: word times show only a \(String(format: "%.2f", widest)) s gap here. Heard \(heardText)."
            }
            return "rules: transcript shows a \(String(format: "%.2f", widest)) s gap. Heard \(heardText)."
        case .fillerCluster:
            let fillers = nearby.filter(\.isFiller).count
            if fillers < ReviewMarkers.minimumFillerCount {
                return "transcript: heard \(fillers) filler word(s) here. Heard \(heardText)."
            }
            return "rules: transcript has \(fillers) fillers here. Heard \(heardText)."
        case .restart:
            if RestartDetector.find(in: nearby).isEmpty {
                return "transcript: no repeated words in what was heard. Heard \(heardText)."
            }
            return "rules: transcript has a repeat here. Heard \(heardText)."
        case .skippedWord, .swappedWord:
            return "Heard \(heardText). If the wrong word is missing here, Grok corrected it to the passage word (passage words are sent as hints)."
        case .slowStart:
            return "Heard \(heardText) after the partner stopped."
        }
    }
}
