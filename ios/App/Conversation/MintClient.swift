import Foundation

struct MintResponse: Decodable {
    let clientSecret: String
    let startsRemaining: Int
    enum CodingKeys: String, CodingKey {
        case clientSecret = "client_secret"
        case startsRemaining = "starts_remaining"
    }

    init(clientSecret: String, startsRemaining: Int) {
        self.clientSecret = clientSecret
        self.startsRemaining = startsRemaining
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startsRemaining = try c.decode(Int.self, forKey: .startsRemaining)
        if let secret = try? c.decode(String.self, forKey: .clientSecret) {
            clientSecret = secret
        } else {
            clientSecret = try c.decode(SecretObject.self, forKey: .clientSecret).value
        }
    }

    private struct SecretObject: Decodable { let value: String }
}

enum MintError: Error, Equatable { case budget, concurrent, rate, auth, unavailable }

extension MintError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .budget: "This month’s conversations are used."
        case .concurrent: "A conversation is already in progress."
        case .rate: "Too many tries. Wait a few minutes."
        case .auth: "Couldn’t sign in to Conversation."
        case .unavailable: "Conversation isn’t available right now."
        }
    }
}

/// Conversation start gate, done on the device (no mint server, no network).
///
/// Conversation talks to xAI's realtime voice API directly with the build's xAI key, so there is
/// no short-lived secret to mint: an xAI ephemeral token would add a round trip (~200 ms) before
/// every session for no gain, since the key already ships in the app. `mint()` only applies the
/// budget rules the server kept (20 counted starts per calendar month, 1 live session, 3 starts
/// per 10 minutes): the month count in UserDefaults, the rest in memory.
///
/// Wiring (unchanged):
/// - countdown 0 → `mint()` → `countdownReachedZero(ephemeralKey:)`
/// - when `countsAsBudgetStart` becomes true → `started(sessionID:)`
/// - map `MintError.budget` to disable Start
/// - drop before report: `ended()` and do **not** call `started` (session never counted)
final class MintClient: Sendable {
    static let monthlyStarts = 20
    private static let budget = LocalBudget()

    let uuid: UUID
    let apiKey: String

    init(apiKey: String, uuid: UUID) {
        self.apiKey = apiKey
        self.uuid = uuid
    }

    /// `nil` when this build has no xAI key.
    static func makeIfConfigured(uuid: UUID) -> MintClient? {
        guard let key = ProviderKeys.xai else { return nil }
        return MintClient(apiKey: key, uuid: uuid)
    }

    func mint() async throws -> MintResponse {
        try Self.budget.reserveMint(now: .now)
        Self.budget.mintSucceeded()
        return MintResponse(clientSecret: apiKey, startsRemaining: Self.budget.remaining(now: .now))
    }

    func started(sessionID: UUID) async throws -> Int {
        try Self.budget.countStart(sessionID: sessionID, now: .now)
    }

    func ended() async throws {
        Self.budget.ended()
    }

    /// The mint server only counted these. Nothing to report without it.
    func crisis() async {}
    func possibleMinor() async {}
}

/// Local stand-in for the mint server's per-account budget.
private final class LocalBudget: @unchecked Sendable {
    private let lock = NSLock()
    private let defaults = UserDefaults.standard
    private let monthKey = "conversation.localBudget.month"
    private let countKey = "conversation.localBudget.count"
    private let rateWindow: TimeInterval = 10 * 60
    private var concurrent = 0
    private var mintTimes: [Date] = []
    private var startedSessions: Set<UUID> = []

    private func month(_ now: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month], from: now)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    private func count(_ now: Date) -> Int {
        defaults.string(forKey: monthKey) == month(now) ? defaults.integer(forKey: countKey) : 0
    }

    func remaining(now: Date) -> Int {
        lock.withLock { max(0, MintClient.monthlyStarts - count(now)) }
    }

    func reserveMint(now: Date) throws {
        try lock.withLock {
            if concurrent >= 1 { throw MintError.concurrent }
            mintTimes = mintTimes.filter { now.timeIntervalSince($0) < rateWindow }
            if mintTimes.count >= 3 { throw MintError.rate }
            if count(now) >= MintClient.monthlyStarts { throw MintError.budget }
            mintTimes.append(now)
        }
    }

    func mintSucceeded() {
        lock.withLock { concurrent += 1 }
    }

    func ended() {
        lock.withLock { concurrent = max(0, concurrent - 1) }
    }

    func countStart(sessionID: UUID, now: Date) throws -> Int {
        try lock.withLock {
            let current = count(now)
            if !startedSessions.contains(sessionID) {
                if current >= MintClient.monthlyStarts { throw MintError.budget }
                startedSessions.insert(sessionID)
                defaults.set(month(now), forKey: monthKey)
                defaults.set(current + 1, forKey: countKey)
                return MintClient.monthlyStarts - (current + 1)
            }
            return MintClient.monthlyStarts - current
        }
    }
}
