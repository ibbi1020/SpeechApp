import Foundation

/// Maps mic RMS onto the listen orb's energy.
///
/// A `.measurement` tap is quieter than a browser analyser. The old 0.55
/// ceiling was for the aurora pill, which turned into the AI-speaking look
/// above that band. The cloud orb uses phase for speak vs listen, so the
/// full 0...1 range is available — and a slight concave curve lifts quiet
/// speech without letting room noise through the floor.
public enum ListenDrive {
    /// Top of the listening band. The orb reads this as activity, not as a
    /// speak/listen switch.
    public static let ceiling: Float = 1

    public static func normalized(rms: Float) -> Float {
        let lifted = max(0, rms - 0.003)
        let linear = min(1, lifted * 42)
        return min(ceiling, pow(linear, 0.75))
    }
}
