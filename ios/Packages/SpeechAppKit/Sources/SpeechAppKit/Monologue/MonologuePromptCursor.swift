import Foundation

public struct MonologuePromptCursor: Equatable, Sendable {
    public let prompts: [String]
    public private(set) var index: Int

    public init(prompts: [String], lastPrompt: String?) {
        precondition(!prompts.isEmpty, "prompt bank is empty")
        self.prompts = prompts
        if let lastPrompt, let found = prompts.firstIndex(of: lastPrompt) {
            self.index = found
        } else {
            self.index = 0
        }
    }

    public var current: String { prompts[index] }

    public mutating func skip() {
        index = (index + 1) % prompts.count
    }
}
