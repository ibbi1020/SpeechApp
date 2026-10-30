import Foundation

/// The app no longer reads this. The mint Worker holds `XAI_API_KEY`.
/// `server/sync-xai-secret.sh` can still write the gitignored plist for a local experiment.
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
