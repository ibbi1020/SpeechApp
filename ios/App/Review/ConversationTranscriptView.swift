import Flow
import SwiftUI
import SpeechAppKit

/// Conversation transcript: each partner line, then the user's answer with the
/// current word highlighted. Tapping a word jumps there.
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

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(blocks) { block in
                        VStack(alignment: .leading, spacing: 6) {
                            if let partner = block.partner, !partner.text.isEmpty {
                                Text(partner.text)
                                    .font(.subheadline.italic())
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if !block.words.isEmpty {
                                HFlow(itemSpacing: 6, rowSpacing: 6) {
                                    ForEach(block.words) { word in
                                        Button {
                                            onWordTap(word)
                                        } label: {
                                            Text(word.surface)
                                                .font(.system(.body, design: .serif))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 2)
                                                .background {
                                                    if currentWordID == word.id {
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
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: currentWordID) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .frame(minHeight: 120, maxHeight: 260)
    }
}
