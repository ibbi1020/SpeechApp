import SwiftUI
import SpeechAppKit

/// Conversation transcript: each partner line, then the user's answer.
/// The spoken word matches passage reading. Tapping a word jumps there.
struct ConversationTranscriptView: View {
    let words: [RecordedWord]
    let partnerTurns: [PartnerTurn]
    let currentTime: TimeInterval
    let onWordTap: (RecordedWord) -> Void

    private struct Block: Identifiable {
        let id: Int
        let partner: PartnerTurn?
        let words: [RecordedWord]
    }

    private var blocks: [Block] {
        let turns = partnerTurns.sorted { $0.start < $1.start }
        var answers: [[RecordedWord]] = Array(repeating: [], count: turns.count + 1)
        for word in words.sorted(by: { $0.start < $1.start }) {
            answers[turns.filter { $0.end <= word.start }.count].append(word)
        }
        var out: [Block] = []
        if !answers[0].isEmpty {
            out.append(Block(id: 0, partner: nil, words: answers[0]))
        }
        for (index, turn) in turns.enumerated() {
            out.append(Block(id: index + 1, partner: turn, words: answers[index + 1]))
        }
        return out
    }

    private var currentWordID: UUID? {
        words.last { $0.start <= currentTime && currentTime <= $0.end + 0.15 }?.id
    }

    @ScaledMetric(relativeTo: SpeechReading.textStyle) private var size = SpeechReading.size

    var body: some View {
        VStack(alignment: .leading, spacing: SpeechSpacing.related) {
            ForEach(blocks) { block in
                VStack(alignment: .leading, spacing: SpeechSpacing.cluster) {
                    if let partner = block.partner, !partner.text.isEmpty {
                        Text(partner.text)
                            .font(SpeechType.reading(15, relativeTo: .subheadline))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !block.words.isEmpty {
                        WordWrapLayout(
                            spacing: SpeechReading.scaledGap(SpeechReading.wordGap, size: size),
                            lineSpacing: SpeechReading.scaledGap(SpeechReading.lineGap, size: size)
                        ) {
                            ForEach(block.words) { word in
                                Button {
                                    onWordTap(word)
                                } label: {
                                    SpeechReadingWord(
                                        text: word.surface,
                                        isCurrent: currentWordID == word.id,
                                        quiet: word.isFiller,
                                        size: size
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
