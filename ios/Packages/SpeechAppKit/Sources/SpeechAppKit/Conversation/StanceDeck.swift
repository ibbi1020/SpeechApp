import Foundation

public struct StanceCard: Sendable {
    public let views: [String]
}

public struct StanceDeck: Sendable {
    public let views: [String]
    public enum BankError: Error { case missing }

    public static func loadBundled() throws -> StanceDeck {
        guard let url = Bundle.module.url(
            forResource: "stances", withExtension: "json", subdirectory: "Conversation"
        ) ?? Bundle.module.url(forResource: "stances", withExtension: "json")
        else { throw BankError.missing }
        let views = try JSONDecoder().decode([String].self, from: Data(contentsOf: url))
        return StanceDeck(views: views)
    }

    /// One view by default; ~10% of the time two. More views fuel preference monologues.
    public func sample(rng: inout SplitMix64) -> StanceCard {
        var pool = views
        var picked: [String] = []
        let wantTwo = rng.next() % 10 == 0
        let count = min(wantTwo ? 2 : 1, pool.count)
        for _ in 0..<count {
            let i = Int(rng.next() % UInt64(pool.count))
            picked.append(pool.remove(at: i))
        }
        return StanceCard(views: picked)
    }
}

public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
