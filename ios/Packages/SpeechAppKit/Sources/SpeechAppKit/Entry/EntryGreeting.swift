import Foundation

/// The two words above the figure on Home. Two words, about craft rather than a streak.
public enum EntryGreeting {
    public static let kicker = "Orator"

    public static func line(hasBegunBefore: Bool) -> String {
        hasBegunBefore ? "Once more" : "First words"
    }
}
