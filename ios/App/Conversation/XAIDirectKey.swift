import Foundation

/// Local testing only: load `XAI_API_KEY` from the gitignored `XAISecrets.plist`
/// written by `server/sync-xai-secret.sh`. Format 2 skips mint and uses this key
/// as the WebSocket Bearer token.
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
