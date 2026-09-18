import Foundation

public enum PassageLength: String, Codable, Sendable, CaseIterable {
    case short
    case medium
    case long

    public var label: String {
        switch self {
        case .short: return "Short"
        case .medium: return "Medium"
        case .long: return "Longer"
        }
    }
}

extension ScriptWord {
    /// Expected phones for specialized scoring (not Apple ASR).
    public var resolvedPhones: [String] {
        if !canonicalPhones.isEmpty { return canonicalPhones }
        if !phoneTags.isEmpty, phoneTags.count > 1 || phoneTags.first != "stress" {
            // Passage-level tags alone are contrast hints, not a full word spelling —
            // fall through to lexicon when tags look like contrast inventory.
        }
        return PhoneLexicon.phones(for: surface)
    }
}
