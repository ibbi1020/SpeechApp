import Foundation

struct MintResponse: Decodable {
    let clientSecret: String
    let startsRemaining: Int
    enum CodingKeys: String, CodingKey {
        case clientSecret = "client_secret"
        case startsRemaining = "starts_remaining"
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

/// Authenticated Conversation mint client. Server is source of truth for budget.
///
/// Wiring (Tasks 11–13 — do not consume a start locally here):
/// - countdown 0 → `mint()` → `countdownReachedZero(ephemeralKey:)`
/// - when `countsAsBudgetStart` becomes true → `started(sessionID:)`
/// - map `MintError.budget` to disable Start
/// - never consume a start locally on countdown
/// - drop before report: `ended()` and do **not** call `started` (session never counted)
/// - if `started` already ran, do not refund
final class MintClient: Sendable {
    static let apiBaseKey = "CONVERSATION_API_BASE"

    let base: URL
    let uuid: UUID
    init(base: URL, uuid: UUID) {
        self.base = base
        self.uuid = uuid
    }

    /// `nil` when `CONVERSATION_API_BASE` is missing, empty, or not a host URL.
    /// Empty plist value means skip POSTs — never fall back to a baked-in host.
    static func makeIfConfigured(
        uuid: UUID,
        info: [String: Any]? = Bundle.main.infoDictionary
    ) -> MintClient? {
        guard let raw = info?[apiBaseKey] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.host != nil else {
            return nil
        }
        return MintClient(base: url, uuid: uuid)
    }

    func mint() async throws -> MintResponse {
        try await post("v1/conversation/mint", body: [:], decode: MintResponse.self)
    }

    func started(sessionID: UUID) async throws -> Int {
        struct StartedResponse: Decodable {
            let startsRemaining: Int
            enum CodingKeys: String, CodingKey { case startsRemaining = "starts_remaining" }
        }
        let r: StartedResponse = try await post(
            "v1/conversation/started",
            body: ["session_id": sessionID.uuidString],
            decode: StartedResponse.self
        )
        return r.startsRemaining
    }

    func ended() async throws {
        _ = try await post("v1/conversation/ended", body: [:], decode: OptionalEmpty.self)
    }

    func crisis() async {
        _ = try? await post("v1/conversation/crisis", body: [:], decode: OptionalEmpty.self)
    }

    func possibleMinor() async {
        _ = try? await post("v1/conversation/possible-minor", body: [:], decode: OptionalEmpty.self)
    }

    private struct OptionalEmpty: Decodable {}

    private func post<T: Decodable>(_ path: String, body: [String: String], decode: T.Type) async throws -> T {
        var req = URLRequest(url: base.appending(path: path))
        req.httpMethod = "POST"
        req.setValue("Bearer \(uuid.uuidString)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 429, let err = try? JSONDecoder().decode(ErrorBody.self, from: data) {
            switch err.error {
            case "budget": throw MintError.budget
            case "concurrent": throw MintError.concurrent
            default: throw MintError.rate
            }
        }
        if code == 401 { throw MintError.auth }
        guard (200...204).contains(code) else { throw MintError.unavailable }
        if T.self == OptionalEmpty.self { return OptionalEmpty() as! T }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private struct ErrorBody: Decodable { let error: String }
}
