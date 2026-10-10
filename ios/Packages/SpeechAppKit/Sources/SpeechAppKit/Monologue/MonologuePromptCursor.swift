import Foundation

public struct MonologuePromptCursor: Equatable, Sendable {
    public let prompts: [String]
    public private(set) var index: Int

    /// A random prompt. The saved topic from last time is left out when another one exists.
    public init(prompts: [String], lastPrompt: String?, rng: inout SplitMix64) {
        precondition(!prompts.isEmpty, "prompt bank is empty")
        self.prompts = prompts
        let pool = Self.choices(in: prompts, excluding: lastPrompt)
        index = pool[Int(rng.next() % UInt64(pool.count))]
    }

    private static func choices(in prompts: [String], excluding lastPrompt: String?) -> [Int] {
        guard prompts.count > 1, let lastPrompt, let found = prompts.firstIndex(of: lastPrompt) else {
            return Array(prompts.indices)
        }
        return prompts.indices.filter { $0 != found }
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
