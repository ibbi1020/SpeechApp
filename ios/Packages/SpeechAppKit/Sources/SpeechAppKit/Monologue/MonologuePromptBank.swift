import Foundation

public struct MonologuePromptBank: Sendable {
    public let prompts: [String]
    public enum BankError: Error { case missing }

    public static func loadBundled() throws -> MonologuePromptBank {
        guard let url = Bundle.module.url(
            forResource: "monologue-prompts", withExtension: "json", subdirectory: "Monologue"
        ) ?? Bundle.module.url(forResource: "monologue-prompts", withExtension: "json")
        else { throw BankError.missing }
        let prompts = try JSONDecoder().decode([String].self, from: Data(contentsOf: url))
        return MonologuePromptBank(prompts: prompts)
    }
}
