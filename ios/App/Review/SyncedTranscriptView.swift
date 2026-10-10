import Flow
import SwiftUI
import SpeechAppKit

struct SyncedTranscriptView: View {
    let words: [RecordedWord]
    let currentTime: TimeInterval
    let onWordTap: (RecordedWord) -> Void

    private var currentIndex: Int? {
        guard !words.isEmpty else { return nil }
        // Binary search: last word whose start <= currentTime.
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
            // Past the word with a little slack — no highlight.
            return nil
        }
        return answer
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                HFlow(itemSpacing: 6, rowSpacing: 6) {
                    ForEach(Array(words.enumerated()), id: \.element.id) { index, word in
                        Button {
                            onWordTap(word)
                        } label: {
                            Text(word.surface)
                                .font(.system(.body, design: .serif))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background {
                                    if currentIndex == index {
                                        Capsule(style: .continuous)
                                            .fill(Color.accentColor.opacity(0.25))
                                    }
                                }
                                .foregroundStyle(word.isFiller ? Color.secondary : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .id(word.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: currentIndex) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(words[newValue].id, anchor: .center)
                }
            }
        }
        .frame(minHeight: 120, maxHeight: 220)
    }
}
