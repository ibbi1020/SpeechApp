#if os(macOS)
import Foundation
import SpeechAppKit

/// Runs the marker rules on cached Grok words and compares them with each clip's labels.
enum ScoreCommand {
    struct ClipResult {
        let clip: Clip
        let labels: ClipLabels
        let words: [RecordedWord]
        let duration: TimeInterval
        let candidates: FeedbackScore
        let shown: FeedbackScore
        let markers: [ReviewMarker]
    }

    static func run(_ options: Options) throws {
        var results: [ClipResult] = []
        var skipped: [String] = []
        for clip in Clip.all(in: options.dir, only: options.only) {
            guard let labels = try clip.labels() else {
                skipped.append("\(clip.name): no labels (.labels.json or Audacity .txt)")
                continue
            }
            guard let grok = clip.grok() else {
                skipped.append("\(clip.name): not transcribed yet (run `transcribe`)")
                continue
            }
            let words = grok.recordedWords
            let duration = grok.audioSeconds
            let (candidates, markers) = labels.context.markers(words: words, durationSeconds: duration)
            results.append(ClipResult(
                clip: clip,
                labels: labels,
                words: words,
                duration: duration,
                candidates: FeedbackEvaluator.scoreCandidates(
                    labels: labels.labels,
                    candidates: candidates,
                    tolerance: options.tolerance
                ),
                shown: FeedbackEvaluator.scoreMarkers(
                    labels: labels.labels,
                    markers: markers,
                    tolerance: options.tolerance
                ),
                markers: markers
            ))
        }

        let report = render(results, skipped: skipped, tolerance: options.tolerance)
        let reportURL = URL(fileURLWithPath: options.report)
        try FileManager.default.createDirectory(
            at: reportURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try report.write(to: reportURL, atomically: true, encoding: .utf8)
        print(report)
        print("\nReport written to \(options.report)")
    }

    static func render(_ results: [ClipResult], skipped: [String], tolerance: TimeInterval) -> String {
        var out = "# Feedback eval\n\n"
        out += "Onset tolerance \(tolerance) s. “Detected” is before the cap and spacing; “shown” is what the player displays.\n\n"

        out += "## Summary\n\n"
        out += "| Kind | Expected | Detected | Shown when it should be | Extra detections |\n|---|---|---|---|---|\n"
        let kinds: [ReviewMarker.Kind] = [.pause, .fillerCluster, .restart, .skippedWord, .swappedWord, .slowStart]
        for kind in kinds {
            let expected = results.flatMap { $0.labels.labels }.filter { $0.kind == kind && $0.expect != .none }.count
            let detected = results.flatMap { $0.candidates.matched }.filter { $0.label.kind == kind }.count
            let mustShow = results.flatMap { $0.labels.labels }.filter { $0.kind == kind && $0.expect == .marker }.count
            let shown = results.flatMap { $0.shown.matched }.filter { $0.label.kind == kind }.count
            let extra = results.flatMap { $0.candidates.extra }.filter { $0.kind == kind }.count
            if expected == 0, extra == 0 { continue }
            out += "| \(FeedbackReport.name(kind)) | \(expected) | \(detected) | \(shown)/\(mustShow) | \(extra) |\n"
        }
        let clean = results.filter { $0.candidates.isPerfect && $0.shown.isPerfect }.count
        out += "\n\(clean) of \(results.count) clips match their labels exactly.\n"

        for result in results {
            let problems = FeedbackReport.problems(candidates: result.candidates, shown: result.shown)
            out += "\n## \(problems.isEmpty ? "✅" : "❌") \(result.clip.name)\n\n"
            if let why = result.labels.why { out += "\(why)\n\n" }
            if let script = result.labels.script { out += "Script: `\(script)`\n\n" }
            out += "Heard: \(heard(result.words))\n\n"
            out += "Take \(String(format: "%.1f", result.duration)) s, cap \(ReviewMarkers.maxMarkers(durationSeconds: result.duration)) markers.\n\n"
            if result.markers.isEmpty {
                out += "Shown: none\n"
            } else {
                out += "Shown:\n"
                for marker in result.markers {
                    out += "- \(FeedbackReport.describe(marker)): \(marker.note)\n"
                }
            }
            if !problems.isEmpty {
                out += "\nProblems:\n"
                for line in problems { out += "- \(line)\n" }
                let missed = result.candidates.missed + result.shown.missed
                var seen = Set<String>()
                for label in missed where seen.insert(FeedbackReport.describe(label)).inserted {
                    out += "  - why \(FeedbackReport.describe(label)) was missed → \(FeedbackReport.blame(label, words: result.words))\n"
                }
            }
        }

        if !skipped.isEmpty {
            out += "\n## Skipped\n\n"
            for line in skipped { out += "- \(line)\n" }
        }
        return out
    }

    /// Transcript with fillers in italics and gaps of 0.7 s or more written in.
    static func heard(_ words: [RecordedWord]) -> String {
        guard !words.isEmpty else { return "(nothing)" }
        var parts: [String] = []
        var previousEnd: TimeInterval = 0
        for word in words.sorted(by: { $0.start < $1.start }) {
            let gap = word.start - previousEnd
            if gap >= 0.7 { parts.append("[\(String(format: "%.1f", gap)) s]") }
            parts.append(word.isFiller ? "*\(word.surface)*" : word.surface)
            previousEnd = word.end
        }
        return parts.joined(separator: " ")
    }
}
#endif
