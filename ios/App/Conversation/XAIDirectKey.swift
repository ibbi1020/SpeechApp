import Foundation

/// Local testing only: load `XAI_API_KEY` from the gitignored `XAISecrets.plist`
/// written by `server/sync-xai-secret.sh`.
///
/// Reading, Monologue, listen-back, and Conversation use this key on api.x.ai.
/// The mint server replaces it before launch so the key is not in the app.
enum XAIDirectKey {
    private static let plistName = "XAISecrets"
    private static let keyName = "XAI_API_KEY"

    static func load() -> String? {
        guard let url = Bundle.main.url(forResource: plistName, withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any],
              let raw = dict[keyName] as? String
        else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
