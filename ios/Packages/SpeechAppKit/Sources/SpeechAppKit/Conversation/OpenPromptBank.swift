import Foundation

public struct OpenPromptBank: Sendable {
    public let prompts: [String]
    public enum BankError: Error { case missing }

    public static func loadBundled() throws -> OpenPromptBank {
        guard let url = Bundle.module.url(
            forResource: "opens", withExtension: "json", subdirectory: "Conversation"
        ) ?? Bundle.module.url(forResource: "opens", withExtension: "json")
        else { throw BankError.missing }
        let prompts = try JSONDecoder().decode([String].self, from: Data(contentsOf: url))
        return OpenPromptBank(prompts: prompts)
    }
}
