/// How loud the ceremony plays the tone to copy.
///
/// 1 is the full sample range. The phone speaker is the output, so a quieter
/// peak disappears in a room. An upper partial is added on top of the voice,
/// then clamped, so the level goes up instead of being shared with the fundamental.
public enum VocalPlayback {
    public static let peak: Float = 1

    /// `shaped` is the voice already scaled to about -1...1. `partial` is the
    /// extra upper tone, added on top. `flutter` is the trill, 1 when there is none.
    public static func sample(shaped: Double, partial: Double, flutter: Double) -> Float {
        let mixed = (shaped + partial) * Double(peak) * flutter
        return Float(min(1, max(-1, mixed)))
    }
}
