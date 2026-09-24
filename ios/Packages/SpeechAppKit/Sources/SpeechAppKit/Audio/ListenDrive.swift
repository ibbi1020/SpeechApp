import Foundation

/// Maps mic RMS onto the listen pill's energy.
///
/// The silhouette is the lab's user-speaking pill (`prototypes/mic-visualizer`,
/// mode `listen`): two slow crests that lift. A `.measurement` tap is quieter
/// than the browser analyser that lab was tuned on, so `rms / 0.06` never left
/// the idle floor. This curve puts conversational speech in that lift
/// (about 0.4–0.55). It stops there on purpose. Past that the same two crests
/// fill the capsule and pick up magenta and green, which is the lab's
/// AI-speaking look.
public enum ListenDrive {
    /// Top of the user-speaking band. The AI pill lives above this.
    public static let ceiling: Float = 0.55

    public static func normalized(rms: Float) -> Float {
        let lifted = max(0, rms - 0.004)
        return min(ceiling, lifted * 28)
    }
}
