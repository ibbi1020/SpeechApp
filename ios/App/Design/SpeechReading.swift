import SwiftUI

/// Shared settings for words you read or hear back.
///
/// Passage reading and listen-back both use this, so Instrument Serif stays one size,
/// one gap, and one way of marking the current word.
enum SpeechReading {
    /// Point size at the Large text setting. Scales with `textStyle`.
    static let size: CGFloat = 22
    static let textStyle: Font.TextStyle = .title2
    /// Space between words at `size`.
    static let wordGap: CGFloat = 8
    /// Space between lines at `size`.
    static let lineGap: CGFloat = 14
    /// Instrument Serif has no heavier cut. A second copy, shifted by this much,
    /// is one step heavier on the word being spoken.
    static let currentWordShift: CGFloat = 0.5

    static func scaledGap(_ gap: CGFloat, size: CGFloat) -> CGFloat {
        size * gap / Self.size
    }

    static func font(size: CGFloat) -> Font {
        .custom(SpeechType.instrumentSerif, size: size)
    }
}

/// One word in Instrument Serif. The spoken word is underlined and drawn twice.
struct SpeechReadingWord: View {
    var text: String
    var isCurrent: Bool
    var dimmed: Bool = false
    /// A filler, or any word that should sit back. Not the current-word mark.
    var quiet: Bool = false
    var size: CGFloat

    var body: some View {
        styled(text)
            .underline(isCurrent, color: dimmed ? Color.secondary : Color.primary)
            .background(alignment: .leading) {
                if isCurrent {
                    styled(text)
                        .offset(x: SpeechReading.currentWordShift)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private func styled(_ value: String) -> some View {
        Text(value)
            .font(SpeechReading.font(size: size))
            .foregroundStyle(ink)
    }

    private var ink: AnyShapeStyle {
        if dimmed { return AnyShapeStyle(.tertiary) }
        if quiet { return AnyShapeStyle(.secondary) }
        return AnyShapeStyle(.primary)
    }
}

/// Left-to-right wrapping rows, so each word can take its own underline.
struct WordWrapLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let rows = rows(in: width, subviews: subviews)
        let height = rows.reduce(CGFloat(0)) { $0 + $1.height }
            + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(in: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indexes {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indexes: [Int]
        var height: CGFloat
    }

    private func rows(in width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var indexes: [Int] = []
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let nextWidth = indexes.isEmpty ? size.width : rowWidth + spacing + size.width
            if !indexes.isEmpty, width > 0, nextWidth > width {
                rows.append(Row(indexes: indexes, height: rowHeight))
                indexes = [index]
                rowWidth = size.width
                rowHeight = size.height
            } else {
                indexes.append(index)
                rowWidth = nextWidth
                rowHeight = max(rowHeight, size.height)
            }
        }
        if !indexes.isEmpty {
            rows.append(Row(indexes: indexes, height: rowHeight))
        }
        return rows
    }
}
