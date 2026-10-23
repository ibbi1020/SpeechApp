import Foundation
import Testing
@testable import SpeechAppKit

/// Runs every case in `eval/feedback/rules.json` against the marker rules.
@Suite("Feedback rule cases")
struct FeedbackRuleCaseTests {
    static let cases: [FeedbackRuleCase] = {
        var url = URL(fileURLWithPath: #filePath)
        // FeedbackRuleCaseTests.swift → SpeechAppKitTests → Tests → SpeechAppKit → Packages → ios → repo
        for _ in 0..<6 { url.deleteLastPathComponent() }
        url.append(path: "eval/feedback/rules.json")
        do {
            return try JSONDecoder().decode([FeedbackRuleCase].self, from: Data(contentsOf: url))
        } catch {
            Issue.record("Could not load \(url.path): \(error)")
            return []
        }
    }()

    @Test("rules.json loads")
    func loads() {
        #expect(Self.cases.count >= 20)
    }

    @Test("marker rules match the expected feedback", arguments: cases.map(\.name))
    func ruleCase(name: String) throws {
        let ruleCase = try #require(Self.cases.first { $0.name == name })
        let result = try ruleCase.run()
        let problems = FeedbackReport.problems(result)
        if let knownIssue = ruleCase.knownIssue {
            withKnownIssue(Comment(rawValue: knownIssue)) {
                #expect(problems.isEmpty, Comment(rawValue: problems.joined(separator: "\n")))
            }
        } else {
            #expect(problems.isEmpty, Comment(rawValue: problems.joined(separator: "\n")))
        }
    }

    @Test("script layout times words and labels")
    func scriptLayout() throws {
        let layout = try FeedbackScript("[2 pause] I went <fillers> um uh </>").layout()
        #expect(layout.words.map(\.surface) == ["I", "went", "um", "uh"])
        #expect(layout.words.first?.start == 2)
        #expect(layout.labels.count == 2)
        #expect(layout.labels[0] == FeedbackLabel(kind: .pause, start: 0, end: 2))
        #expect(layout.labels[1].kind == .fillerCluster)
    }

    @Test("evaluator separates missed, extra, and wrong kind")
    func evaluator() {
        let labels = [
            FeedbackLabel(kind: .pause, start: 1, end: 3),
            FeedbackLabel(kind: .fillerCluster, start: 10, end: 12),
            FeedbackLabel(kind: .restart, start: 20, end: 21),
        ]
        let markers = [
            ReviewMarker(kind: .pause, start: 1.2, end: 3, score: 1.8, note: ""),
            ReviewMarker(kind: .pause, start: 10.1, end: 11, score: 0.9, note: ""),
            ReviewMarker(kind: .restart, start: 40, end: 41, score: 1, note: ""),
        ]
        let score = FeedbackEvaluator.scoreMarkers(labels: labels, markers: markers)
        #expect(score.matched.count == 1)
        #expect(score.wrongKind.count == 1)
        #expect(score.extra.count == 1)
        #expect(score.missed.map(\.kind) == [.restart])
    }

    @Test("Audacity labels parse with maybe and not")
    func audacity() {
        let text = "1.0\t3.5\tpause\n4\t6\tfillers maybe\n7\t8\tnot restart\nbad line"
        let labels = FeedbackLabel.parseAudacity(text)
        #expect(labels.map(\.kind) == [.pause, .fillerCluster, .restart])
        #expect(labels.map(\.expect) == [.marker, .candidate, .none])
    }
}
