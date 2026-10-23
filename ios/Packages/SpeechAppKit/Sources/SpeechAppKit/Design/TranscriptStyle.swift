import CoreGraphics
import SwiftUI

/// Listen-back transcript. Same size and spacing as the reading passage.
///
/// The person is New York. The partner is SF Pro. 22pt at the Large text
/// setting, 8pt between words, 14pt between lines.
public enum TranscriptStyle {
    public enum Face: Equatable, Sendable {
        /// New York, the reading serif.
        case newYork
        /// SF Pro, the system sans.
        case system
    }

    /// What the person said. New York, same as the reading passage.
    public static let speaker: Face = .newYork

    /// What the partner said. SF Pro.
    public static let partner: Face = .system

    /// Point size at the Large text setting. Same as `SpeechReading.size`.
    public static let size: CGFloat = 22

    /// Space between words at `size`. Same as `SpeechReading.wordGap`.
    public static let wordGap: CGFloat = 8

    /// Space between lines at `size`. Same as `SpeechReading.lineGap`.
    public static let lineGap: CGFloat = 14

    /// Dynamic Type bucket. Same as `SpeechReading.textStyle`.
    public static let textStyle: Font.TextStyle = .title2
}
