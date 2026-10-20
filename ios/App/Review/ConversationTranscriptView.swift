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
        let partnerWords = partnerTurns.flatMap { $0.words ?? [] }
        return (words + partnerWords)
            .sorted { $0.start < $1.start }
            .last { $0.start <= currentTime && currentTime <= $0.end + 0.15 }?.id
    }

    /// Smaller than a passage. Same size for both speakers.
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 17
    private let turnGap: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: turnGap) {
            ForEach(blocks) { block in
                VStack(alignment: .leading, spacing: turnGap) {
                    if let partner = block.partner {
                        partnerLine(partner)
                    }
                    if !block.words.isEmpty {
                        words(block.words, face: .instrumentSerif, tint: nil)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func partnerLine(_ partner: PartnerTurn) -> some View {
        if let timed = partner.words, !timed.isEmpty {
            words(timed, face: .system, tint: Color.secondary, accessibilityPrefix: "Partner, ")
        } else if !partner.text.isEmpty {
            Text(partner.text)
                .font(.system(size: size))
                .foregroundStyle(Color.secondary)
                .lineSpacing(SpeechReading.scaledGap(SpeechReading.lineGap, size: size))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func words(
        _ words: [RecordedWord],
        face: SpeechReadingWord.Face,
        tint: Color?,
        accessibilityPrefix: String = ""
    ) -> some View {
        WordWrapLayout(
            spacing: SpeechReading.scaledGap(SpeechReading.wordGap, size: size),
            lineSpacing: SpeechReading.scaledGap(SpeechReading.lineGap, size: size)
        ) {
            ForEach(words) { word in
                Button {
                    onWordTap(word)
                } label: {
                    SpeechReadingWord(
                        text: word.surface,
                        isCurrent: currentWordID == word.id,
                        quiet: face == .instrumentSerif && word.isFiller,
                        tint: tint,
                        face: face,
                        size: size
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityPrefix + word.surface)
            }
        }
    }
}
