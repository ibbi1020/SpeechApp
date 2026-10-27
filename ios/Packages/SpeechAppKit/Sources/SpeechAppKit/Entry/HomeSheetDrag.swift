import Foundation

/// How far a home sheet must travel before it counts as open.
///
/// Progress uses this twice. The drag commits at this openness, and the home
/// stack waits until the same point to put Progress in front of Gallery.
public enum HomeSheetDrag {
    public static let openThreshold: Double = 0.62

    /// A flick up opens. A flick down closes. Otherwise the projected end
    /// has to pass `openThreshold`.
    public static func commitsOpen(flickUp: Bool, flickDown: Bool, projected: Double) -> Bool {
        flickUp || (!flickDown && projected > openThreshold)
    }
}
