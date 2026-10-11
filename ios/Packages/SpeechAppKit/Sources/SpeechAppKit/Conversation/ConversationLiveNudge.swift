import Foundation

/// Tunables for spoken mid-session nudges that are not lifecycle cues (open / wrap).
///
/// The turn threshold is a tuned constant, not a research finding. Classroom L1-use
/// percentages (Macaro, Levine) do not map to a 1:1 rehearsal; delayed selective
/// feedback and the lexical-gap nature of most code-switches argue for skipping the
/// first qualifying turn and keeping heard asides rare.
public enum ConversationLiveNudge {
    /// Nudge on this qualifying non-English turn (1-based). Default 2.
    public static let otherLanguageTurnThreshold = 2
    /// At most this many heard code-switch asides per session. Wrap does not count.
    public static let otherLanguageAsideCap = 2

    /// Spoken `code_switch` cue. Off until accented-English precision ≥ 0.90.
    /// DEBUG builds turn it on so device testing can hear the aside. Tests override.
    /// `nonisolated(unsafe)`: flipped only at process start or in unit tests, never mid-turn.
    #if DEBUG
    nonisolated(unsafe) public static var spokenCodeSwitchEnabled = true
    #else
    nonisolated(unsafe) public static var spokenCodeSwitchEnabled = false
    #endif
}
