import SwiftUI
import UIKit

/// Shared settings for words you read or hear back.
///
/// A prompt, a subtitle, a passage, and a transcript all use this.
/// New York, 22pt at the Large text setting, 8pt between words, 14pt between lines.
/// The spoken word is semibold.
enum SpeechReading {
    /// Point size at the Large text setting. Scales with `textStyle`.
    static let size: CGFloat = 22
    static let textStyle: Font.TextStyle = .title2
    /// Space between words at `size`.
    static let wordGap: CGFloat = 8
    /// Space between lines at `size`.
    static let lineGap: CGFloat = 14

    static func scaledGap(_ gap: CGFloat, size: CGFloat) -> CGFloat {
        size * gap / Self.size
    }

    /// Bundled face. `Font.custom` takes this family name, not the file name.
    static let instrumentSerifName = "Instrument Serif"

    /// New York, the system serif, at `size`.
    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Instrument Serif at `size`. Only the regular face is bundled; a heavier
    /// weight is synthesized for the word under the playhead.
    static func instrumentSerif(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(instrumentSerifName, size: size).weight(weight)
    }

    static func uiFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let system = UIFont.systemFont(ofSize: size, weight: weight)
        guard let serif = system.fontDescriptor.withDesign(.serif) else { return system }
        return UIFont(descriptor: serif, size: size)
    }
}

/// One whole word. The spoken word is semibold and underlined.
///
/// The box stays the regular width of the whole word, so a heavier face
/// cannot push the line. The extra ink draws into the gap after the word.
struct SpeechReadingWord: View {
    var text: String
    var isCurrent: Bool
    var dimmed: Bool = false
    /// A filler, or any word that should sit back. Not the current-word mark.
    var quiet: Bool = false
    /// Partner words use this so they stay distinct from the speaker.
    var tint: Color? = nil
    /// New York is the reading and transcript face.
    /// Instrument Serif stays available; transcripts do not use it.
    var face: Face = .newYork
    var size: CGFloat

    enum Face {
        case newYork
        case instrumentSerif
        case system
    }

    var body: some View {
        Text(text)
            .font(font(weight: .regular))
            .foregroundStyle(ink)
            .underline(isCurrent, color: underlineColor)
            .opacity(isCurrent ? 0 : 1)
            .overlay(alignment: .leading) {
                if isCurrent {
                    Text(text)
                        .font(font(weight: .semibold))
                        .foregroundStyle(ink)
                        .underline(true, color: underlineColor)
                        .fixedSize(horizontal: true, vertical: true)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel(text)
            .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    /// The whole surface, one face. Weight changes the drawing, not the box.
    private func font(weight: Font.Weight) -> Font {
        switch face {
        case .newYork:
            return SpeechReading.font(size: size, weight: weight)
        case .instrumentSerif:
            return SpeechReading.instrumentSerif(size: size, weight: weight)
        case .system:
            return .system(size: size, weight: weight)
        }
    }

    private var underlineColor: Color {
        if let tint { return tint }
        return dimmed ? Color.secondary : Color.primary
    }

    private var ink: AnyShapeStyle {
        if let tint { return AnyShapeStyle(tint) }
        if dimmed { return AnyShapeStyle(.tertiary) }
        if quiet { return AnyShapeStyle(.secondary) }
        return AnyShapeStyle(.primary)
    }
}

/// New York at the reading size, with the reading line gap. Scales with the system text size.
private struct SpeechReadingStyle: ViewModifier {
    var weight: Font.Weight
    @ScaledMetric(relativeTo: SpeechReading.textStyle) private var size = SpeechReading.size

    func body(content: Content) -> some View {
        content
            .font(SpeechReading.font(size: size, weight: weight))
            .lineSpacing(SpeechReading.scaledGap(SpeechReading.lineGap, size: size))
    }
}

extension View {
    func speechReading(weight: Font.Weight = .regular) -> some View {
        modifier(SpeechReadingStyle(weight: weight))
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
