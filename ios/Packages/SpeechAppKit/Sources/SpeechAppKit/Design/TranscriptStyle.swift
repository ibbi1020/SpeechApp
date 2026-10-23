import CoreGraphics
import SwiftUI

/// Listen-back transcript. Same face, size, and spacing as the reading passage.
///
/// New York, 22pt at the Large text setting, 8pt between words, 14pt between lines.
/// Matches `SpeechReading`: `.newYork`, `size`, `wordGap`, `lineGap`, and `textStyle`.
public enum TranscriptStyle {
    public enum Face: Equatable, Sendable {
        case newYork
    }

    /// New York, the system serif. Same face as `SpeechReadingWord.Face.newYork`.
    public static let face: Face = .newYork

    /// Point size at the Large text setting. Same as `SpeechReading.size`.
    public static let size: CGFloat = 22

    /// Space between words at `size`. Same as `SpeechReading.wordGap`.
    public static let wordGap: CGFloat = 8

    /// Space between lines at `size`. Same as `SpeechReading.lineGap`.
    public static let lineGap: CGFloat = 14

    /// Dynamic Type bucket. Same as `SpeechReading.textStyle`.
    public static let textStyle: Font.TextStyle = .title2
}
