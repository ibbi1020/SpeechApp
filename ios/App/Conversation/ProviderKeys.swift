import Foundation

/// Implemented by `ProviderSecretsGenerated`, which CI writes to `App/Generated/`
/// (gitignored) from the XAI_API_KEY / OPENAI_API_KEY repo secrets. The keys are stored
/// XOR-masked with a random per-build mask and decoded here at runtime.
@objc protocol ProviderSecretsSource {
    static var xaiAPIKey: String { get }
    static var openAIAPIKey: String { get }
}

/// Provider API keys baked in at build time. `nil` when the build has no generated secrets
/// (for example a local Xcode run without `App/Generated/ProviderSecrets.generated.swift`).
enum ProviderKeys {
    private static var source: ProviderSecretsSource.Type? {
        NSClassFromString("ProviderSecretsGenerated") as? ProviderSecretsSource.Type
    }

    static var xai: String? { nonEmpty(source?.xaiAPIKey) }
    static var openAI: String? { nonEmpty(source?.openAIAPIKey) }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
