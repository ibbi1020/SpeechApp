import CoreGraphics
import SwiftUI
import Testing
@testable import SpeechAppKit

/// Passage metrics from `SpeechReading`: New York, 22pt, 8pt word gap, 14pt line gap, `.title2`.
@Suite("Transcript style")
struct TranscriptStyleTests {
    @Test("the transcript matches the reading passage face, size, gaps, and text style")
    func matchesReadingPassage() {
        #expect(TranscriptStyle.speaker == .newYork)
        #expect(TranscriptStyle.partner == .system)
        #expect(TranscriptStyle.speaker != TranscriptStyle.partner)
        #expect(TranscriptStyle.size == 22)
        #expect(TranscriptStyle.wordGap == 8)
        #expect(TranscriptStyle.lineGap == 14)
        #expect(TranscriptStyle.textStyle == Font.TextStyle.title2)
    }
}
