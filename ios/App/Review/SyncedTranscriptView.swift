import SwiftUI
import SpeechAppKit

struct SyncedTranscriptView: View {
    let words: [RecordedWord]
    let currentTime: TimeInterval
    let onWordTap: (RecordedWord) -> Void

    @ScaledMetric(relativeTo: SpeechReading.textStyle) private var size = SpeechReading.size

    private var currentIndex: Int? {
        guard !words.isEmpty else { return nil }
        var lo = 0
        var hi = words.count - 1
        var answer: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if words[mid].start <= currentTime {
                answer = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        if let answer, words[answer].end + 0.15 < currentTime {
            return nil
        }
        return answer
    }

    var body: some View {
        WordWrapLayout(
            spacing: SpeechReading.scaledGap(SpeechReading.wordGap, size: size),
            lineSpacing: SpeechReading.scaledGap(SpeechReading.lineGap, size: size)
        ) {
            ForEach(Array(words.enumerated()), id: \.element.id) { index, word in
                Button {
                    onWordTap(word)
                } label: {
                    SpeechReadingWord(
                        text: word.surface,
                        isCurrent: currentIndex == index,
                        quiet: word.isFiller,
                        size: size
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
