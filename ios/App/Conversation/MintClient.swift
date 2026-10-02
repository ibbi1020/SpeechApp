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

/// Conversation mint, done on the device (no mint server).
///
/// `mint()` asks OpenAI for a short-lived Realtime client secret with the build's OpenAI key,
/// using the same session config `server/mint.mjs` used. The budget rules the server kept
/// (20 counted starts per calendar month, 1 live session, 3 mints per 10 minutes) are kept
/// locally: the month count in UserDefaults, the rest in memory.
///
/// Wiring (unchanged):
/// - countdown 0 → `mint()` → `countdownReachedZero(ephemeralKey:)`
/// - when `countsAsBudgetStart` becomes true → `started(sessionID:)`
/// - map `MintError.budget` to disable Start
/// - drop before report: `ended()` and do **not** call `started` (session never counted)
final class MintClient: Sendable {
    static let monthlyStarts = 20
    private static let clientSecretsURL = URL(string: "https://api.openai.com/v1/realtime/client_secrets")!
    private static let budget = LocalBudget()

    let uuid: UUID
    private let apiKey: String

    init(apiKey: String, uuid: UUID) {
        self.apiKey = apiKey
        self.uuid = uuid
    }

    /// `nil` when this build has no OpenAI key.
    static func makeIfConfigured(uuid: UUID) -> MintClient? {
        guard let key = ProviderKeys.openAI else { return nil }
        return MintClient(apiKey: key, uuid: uuid)
    }

    func mint() async throws -> MintResponse {
        try Self.budget.reserveMint(now: .now)
        var req = URLRequest(url: Self.clientSecretsURL)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.sessionBody

        let data: Data
        let code: Int
        do {
            let (d, resp) = try await URLSession.shared.data(for: req)
            data = d
            code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            throw MintError.unavailable
        }
        if code == 401 || code == 403 { throw MintError.auth }
        guard (200...299).contains(code),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let secret = Self.secretValue(in: object)
        else {
            throw MintError.unavailable
        }
        Self.budget.mintSucceeded()
        return MintResponse(clientSecret: secret, startsRemaining: Self.budget.remaining(now: .now))
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

    private static func secretValue(in object: [String: Any]) -> String? {
        if let value = object["value"] as? String { return value }
        if let nested = object["client_secret"] as? [String: Any], let value = nested["value"] as? String {
            return value
        }
        return object["client_secret"] as? String
    }

    /// Same body `server/mint.mjs` posted to /v1/realtime/client_secrets.
    private static let sessionBody: Data = {
        let body: [String: Any] = [
            "session": [
                "type": "realtime",
                "model": LiveConversationMouth.pinnedModel,
                "tools": [Any](),
                "tracing": NSNull(),
                "audio": [
                    "input": [
                        "transcription": NSNull(),
                        "turn_detection": [
                            "type": "semantic_vad",
                            "eagerness": "low",
                            "create_response": false,
                            "interrupt_response": false,
                        ],
                        "noise_reduction": ["type": "near_field"],
                    ],
                ],
            ],
            "expires_after": ["anchor": "created_at", "seconds": 120],
        ]
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }()
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
