import Foundation

public struct MonologuePromptCursor: Equatable, Sendable {
    public let prompts: [String]
    public private(set) var index: Int
    /// True when this cursor opened on the saved prompt from the previous session.
    public let openedLastPrompt: Bool

    public init(prompts: [String], lastPrompt: String?, rng: inout SplitMix64) {
        precondition(!prompts.isEmpty, "prompt bank is empty")
        self.prompts = prompts
        if let lastPrompt, let found = prompts.firstIndex(of: lastPrompt) {
            index = found
            openedLastPrompt = true
        } else {
            index = Int(rng.next() % UInt64(prompts.count))
            openedLastPrompt = false
        }
    }

    public var current: String { prompts[index] }

    /// Picks a different prompt. A one-item bank stays put.
    public mutating func skip(using rng: inout SplitMix64) {
        guard prompts.count > 1 else { return }
        var next = index
        while next == index {
            next = Int(rng.next() % UInt64(prompts.count))
        }
        index = next
    }
}
