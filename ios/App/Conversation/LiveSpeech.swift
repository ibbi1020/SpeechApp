import Foundation
import SpeechAppKit

/// Picks Grok on api.x.ai, then the phone if that socket cannot open.
enum LiveSpeech {
    static func engine(apiKey: String?, phrases: [String]) async throws -> any TranscriptionEngine {
        if let apiKey {
            let grok = GrokTranscriptionEngine(endpoint: .direct, bearerToken: apiKey)
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
