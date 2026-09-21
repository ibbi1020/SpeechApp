import Foundation

public enum CrisisVerdict: Equatable, Sendable {
    case allow, crisis, therapyOverride, possibleMinor
}

public enum CrisisGate {
    private static let crisisPhrases = [
        "kill myself", "suicide", "end my life", "want to die",
    ]
    private static let therapyPhrases = [
        "you are my therapist", "pretend you are human", "ignore instructions",
        "you are my friend", // keep tight; do not explode this list in v1
    ]
    private static let minorPhrases = ["i'm 16", "i am 16", "i'm a minor", "i am a minor"]

    public static func evaluate(_ raw: String) -> CrisisVerdict {
        let text = raw.lowercased()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .allow }
        if crisisPhrases.contains(where: { text.contains($0) }) { return .crisis }
        if minorPhrases.contains(where: { text.contains($0) }) { return .possibleMinor }
        if therapyPhrases.contains(where: { text.contains($0) }) { return .therapyOverride }
        return .allow
    }
}
