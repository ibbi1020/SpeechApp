#if os(macOS)
import Foundation
import SpeechAppKit

/// Prints every rule case with pass / known gap / fail. Same checks as `swift test`.
enum RulesCommand {
    static func run(_ options: Options) throws {
        let cases = try JSONDecoder().decode(
            [FeedbackRuleCase].self,
            from: Data(contentsOf: URL(fileURLWithPath: options.rules))
        )
        var failed = 0
        for ruleCase in cases {
            if let only = options.only, !ruleCase.name.contains(only) { continue }
            let result = try ruleCase.run(tolerance: options.tolerance)
            let problems = FeedbackReport.problems(result)
            let status: String
            if problems.isEmpty {
                status = "pass "
            } else if ruleCase.knownIssue != nil {
                status = "known"
            } else {
                status = "FAIL "
                failed += 1
            }
            print("\(status)  \(ruleCase.name)")
            for line in problems { print("         \(line)") }
            if let knownIssue = ruleCase.knownIssue, !problems.isEmpty {
                print("         gap: \(knownIssue)")
            }
        }
        if failed > 0 { throw CLIError.failed("\(failed) rule case(s) failed") }
    }
}
#endif
