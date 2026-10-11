import Foundation

/// The line above the figure on Home.
public enum EntryGreeting {
    /// Navigation title only. Pushed screens use it to name their back button.
    public static let appName = "Orator"

    public static func line(hasBegunBefore: Bool) -> String {
        hasBegunBefore ? "Speak with poise" : "Find your voice"
    }
}
