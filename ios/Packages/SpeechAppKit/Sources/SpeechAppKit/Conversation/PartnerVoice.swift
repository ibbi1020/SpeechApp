import Foundation

/// A Grok speech-to-speech voice. `id` is the `session.update` value.
/// Tones are the short labels from the xAI voice table.
public struct PartnerVoice: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let tone: String

    public init(id: String, name: String, tone: String) {
        self.id = id
        self.name = name
        self.tone = tone
    }

    /// Lively default. Eve is the API default and reads flat in this session.
    /// Sirius is the voice table's quick-witted, playful option.
    public static let defaultID = "sirius"

    /// Built-in roster from the xAI voice table. The app may replace this with `GET /v1/tts/voices`.
    public static let catalog: [PartnerVoice] = [
        PartnerVoice(id: "carina", name: "Carina", tone: "Soft and soothing"),
        PartnerVoice(id: "zagan", name: "Zagan", tone: "Dramatic"),
        PartnerVoice(id: "helix", name: "Helix", tone: "Bold and dynamic"),
        PartnerVoice(id: "orion", name: "Orion", tone: "Cinematic"),
        PartnerVoice(id: "luna", name: "Luna", tone: "Gentle and patient"),
        PartnerVoice(id: "iris", name: "Iris", tone: "Friendly and upbeat"),
        PartnerVoice(id: "altair", name: "Altair", tone: "Elegant"),
        PartnerVoice(id: "zenith", name: "Zenith", tone: "Sharp and focused"),
        PartnerVoice(id: "perseus", name: "Perseus", tone: "Strong and confident"),
        PartnerVoice(id: "helios", name: "Helios", tone: "Upbeat and energetic"),
        PartnerVoice(id: "lux", name: "Lux", tone: "Calm and grounded"),
        PartnerVoice(id: "kepler", name: "Kepler", tone: "Inventive"),
        PartnerVoice(id: "rigel", name: "Rigel", tone: "Precise, Australian"),
        PartnerVoice(id: "cosmo", name: "Cosmo", tone: "Bright and curious"),
        PartnerVoice(id: "celeste", name: "Celeste", tone: "Warm and reassuring"),
        PartnerVoice(id: "ursa", name: "Ursa", tone: "Warm and steady"),
        PartnerVoice(id: "sirius", name: "Sirius", tone: "Quick-witted and playful"),
        PartnerVoice(id: "lumen", name: "Lumen", tone: "Warm and articulate"),
        PartnerVoice(id: "castor", name: "Castor", tone: "Down to earth"),
        PartnerVoice(id: "naksh", name: "Naksh", tone: "Thoughtful, Indian accent"),
        PartnerVoice(id: "atlas", name: "Atlas", tone: "Confident"),
        PartnerVoice(id: "aurora", name: "Aurora", tone: "Serene and steady"),
        PartnerVoice(id: "liora", name: "Liora", tone: "Calm and grounded"),
        PartnerVoice(id: "ara", name: "Ara", tone: "Warm and friendly"),
        PartnerVoice(id: "eve", name: "Eve", tone: "Energetic, British"),
        PartnerVoice(id: "leo", name: "Leo", tone: "Authoritative, British"),
        PartnerVoice(id: "rex", name: "Rex", tone: "Confident and clear"),
        PartnerVoice(id: "sal", name: "Sal", tone: "Smooth and balanced"),
    ]

    public static func named(_ id: String) -> PartnerVoice? {
        let key = canonical(id)
        return catalog.first { $0.id == key }
    }

    /// Lowercase id safe to send as `voice`, or the default when the string is unusable.
    public static func canonical(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isSelectable(trimmed) else { return defaultID }
        return trimmed
    }

    public static func isSelectable(_ id: String) -> Bool {
        guard (1...64).contains(id.count) else { return false }
        return id.unicodeScalars.allSatisfy { scalar in
            CharacterSet.lowercaseLetters.contains(scalar)
                || CharacterSet.decimalDigits.contains(scalar)
                || scalar == "_"
                || scalar == "-"
        }
    }

    /// Catalog order, with any extra API voices appended. Known ids keep their tone.
    public static func merging(remote: [PartnerVoice]) -> [PartnerVoice] {
        guard !remote.isEmpty else { return catalog }
        var seen = Set<String>()
        var merged: [PartnerVoice] = []
        for voice in remote {
            let id = canonical(voice.id)
            guard seen.insert(id).inserted else { continue }
            let tone = voice.tone.isEmpty ? (named(id)?.tone ?? "") : voice.tone
            let name = voice.name.isEmpty ? (named(id)?.name ?? id) : voice.name
            merged.append(PartnerVoice(id: id, name: name, tone: tone))
        }
        return merged.isEmpty ? catalog : merged
    }
}

/// The partner voice chosen on this phone. Missing or junk values read as Sirius.
public final class VoicePreference: @unchecked Sendable {
    public static let storageKey = "conversation.partnerVoice"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var voiceID: String {
        get { PartnerVoice.canonical(defaults.string(forKey: Self.storageKey) ?? "") }
        set { defaults.set(PartnerVoice.canonical(newValue), forKey: Self.storageKey) }
    }
}
