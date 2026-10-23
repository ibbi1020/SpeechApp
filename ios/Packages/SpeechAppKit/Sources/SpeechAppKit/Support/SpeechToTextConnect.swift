import Foundation

/// Where a Reading or Monologue take gets its words.
public enum SpeechToTextRoute: Equatable, Sendable {
    /// Grok connected. Stay here for the take.
    case grok
    /// The server or model could not be reached before the take was live.
    case onDevice
}

/// Grok is the speech-to-text path. The phone is only the backup.
public enum SpeechToTextConnect {
    /// Calls `connect` only when a server is configured.
    /// A cancellation is not a reason to start the phone.
    public static func route(
        relayConfigured: Bool,
        connect: () async throws -> Void
    ) async throws -> SpeechToTextRoute {
        guard relayConfigured else { return .onDevice }
        do {
            try await connect()
            return .grok
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .onDevice
        }
    }
}
