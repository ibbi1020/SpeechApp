import Foundation
import SpeechAppKit

/// Picks Grok through the mint relay, then the phone if that socket cannot open.
enum LiveSpeech {
    /// `accountID` is the Keychain account. The relay checks it and adds the xAI key.
    static func engine(relayBase: URL?, accountID: String, phrases: [String]) async throws -> any TranscriptionEngine {
        if let relayBase {
            let grok = GrokTranscriptionEngine(endpoint: .relay(relayBase), bearerToken: accountID)
            grok.setContextualPhrases(phrases)
            do {
                let route = try await SpeechToTextConnect.route(relayConfigured: true) {
                    try await grok.prepareIfNeeded(locale: Locale(identifier: "en-US"))
                }
                if route == .grok {
                    return grok
                }
            } catch {
                await grok.stop()
                throw error
            }
            await grok.stop()
        }
        let phone = LiveTranscriptionEngine()
        phone.setContextualPhrases(phrases)
        try await phone.prepareIfNeeded(locale: Locale(identifier: "en-US"))
        return phone
    }
}
