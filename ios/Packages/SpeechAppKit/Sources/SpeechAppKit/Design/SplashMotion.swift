import CoreGraphics
import Foundation

/// Cold-launch splash. The mark sits still on white, then Home appears.
public enum SplashMotion {
    /// How long the mark stays on screen before Home.
    public static let hold: TimeInterval = 0.35

    /// Point size of the mark. Matches the launch image (96pt).
    public static let markSize: CGFloat = 96
}
