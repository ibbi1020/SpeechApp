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

    /// Same size as the reading passage. The person is New York. The partner is SF Pro.
    @ScaledMetric(relativeTo: TranscriptStyle.textStyle) private var size: CGFloat = TranscriptStyle.size
    private let turnGap: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: turnGap) {
            ForEach(blocks) { block in
                VStack(alignment: .leading, spacing: turnGap) {
                    if let partner = block.partner {
                        partnerLine(partner)
                    }
                    if !block.words.isEmpty {
                        words(block.words, tint: nil, quietFillers: true, face: .newYork)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func partnerLine(_ partner: PartnerTurn) -> some View {
        if let timed = partner.words, !timed.isEmpty {
            words(
                timed,
                tint: Color.secondary,
                quietFillers: false,
                accessibilityPrefix: "Partner, ",
                face: .system
            )
        } else if !partner.text.isEmpty {
            Text(partner.text)
                .font(.system(size: size))
                .foregroundStyle(Color.secondary)
                .lineSpacing(SpeechReading.scaledGap(TranscriptStyle.lineGap, size: size))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// New York for the person, SF Pro for the partner. Same faces as `TranscriptStyle`.
    private func wordFace(_ style: TranscriptStyle.Face) -> SpeechReadingWord.Face {
        switch style {
        case .newYork:
            .newYork
        case .system:
            .system
        }
    }

    private func words(
        _ words: [RecordedWord],
        tint: Color?,
        quietFillers: Bool,
        accessibilityPrefix: String = "",
        face: TranscriptStyle.Face
    ) -> some View {
        WordWrapLayout(
            spacing: SpeechReading.scaledGap(TranscriptStyle.wordGap, size: size),
            lineSpacing: SpeechReading.scaledGap(TranscriptStyle.lineGap, size: size)
        ) {
            ForEach(words) { word in
                Button {
                    onWordTap(word)
                } label: {
                    SpeechReadingWord(
                        text: word.surface,
                        isCurrent: currentWordID == word.id,
                        quiet: quietFillers && word.isFiller,
                        tint: tint,
                        face: wordFace(face),
                        size: size
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityPrefix + word.surface)
            }
        }
    }
}
