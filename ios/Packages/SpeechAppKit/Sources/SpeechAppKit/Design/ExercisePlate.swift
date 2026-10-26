import Foundation

/// The colour of one exercise disc. Reading is a warm off-white, monologue is
/// amber, conversation is blue.
public struct ExercisePlate: Equatable, Sendable {
    /// 0...1, matching the prototype's `rgb()` channels.
    public var red: Double
    public var green: Double
    public var blue: Double

    public static func plate(for kind: PracticeFormat.Kind) -> ExercisePlate {
        switch kind {
        case .reading:
            plate(236, 232, 224)
        case .monologue:
            plate(255, 206, 150)
        case .conversation:
            plate(186, 208, 232)
        }
    }

    private static func plate(
        _ red: Double,
        _ green: Double,
        _ blue: Double
    ) -> ExercisePlate {
        ExercisePlate(red: red / 255, green: green / 255, blue: blue / 255)
    }
}
