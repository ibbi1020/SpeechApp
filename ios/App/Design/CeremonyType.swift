import SwiftUI

/// SF Pro ramp for the ceremony. Headings elsewhere use the same face.
enum CeremonyPalette {
    /// White is the only accent, shared with the primary button. FocusFlight's amber
    /// is gone: it labelled airport codes there, and nothing here is an airport code.
    static let accent = Color.white
    /// One flat field. A scene can replace this later without touching a step.
    static let background = Color.black
}

enum CeremonyType {
    enum Role {
        case display
        case title
        case body
        case label
        case value
    }

    struct Metrics {
        var size: CGFloat
        var trackingEm: CGFloat
        var lineHeight: CGFloat
        var relativeTo: Font.TextStyle
        var weight: Font.Weight
        var monospacedDigits: Bool
    }

    static func metrics(_ role: Role) -> Metrics {
        switch role {
        case .display:
            Metrics(size: 40, trackingEm: -0.02, lineHeight: 1.05, relativeTo: .largeTitle, weight: .semibold, monospacedDigits: false)
        case .title:
            Metrics(size: 28, trackingEm: -0.015, lineHeight: 1.15, relativeTo: .title, weight: .semibold, monospacedDigits: false)
        case .body:
            Metrics(size: 17, trackingEm: 0, lineHeight: 1.35, relativeTo: .body, weight: .regular, monospacedDigits: false)
        case .label:
            Metrics(size: 13, trackingEm: 0.04, lineHeight: 1.2, relativeTo: .caption, weight: .medium, monospacedDigits: false)
        case .value:
            Metrics(size: 34, trackingEm: -0.02, lineHeight: 1.0, relativeTo: .largeTitle, weight: .semibold, monospacedDigits: true)
        }
    }

    static func font(_ role: Role, size: CGFloat) -> Font {
        let metrics = metrics(role)
        let font = Font.system(size: size, weight: metrics.weight)
        return metrics.monospacedDigits ? font.monospacedDigit() : font
    }
}

private struct CeremonyTextStyle: ViewModifier {
    var role: CeremonyType.Role
    @ScaledMetric private var size: CGFloat

    init(_ role: CeremonyType.Role) {
        self.role = role
        let metrics = CeremonyType.metrics(role)
        _size = ScaledMetric(wrappedValue: metrics.size, relativeTo: metrics.relativeTo)
    }

    func body(content: Content) -> some View {
        let metrics = CeremonyType.metrics(role)
        content
            .font(CeremonyType.font(role, size: size))
            .tracking(size * metrics.trackingEm)
            .lineSpacing(max(0, size * metrics.lineHeight - size))
    }
}

extension View {
    func ceremonyType(_ role: CeremonyType.Role) -> some View {
        modifier(CeremonyTextStyle(role))
    }
}

/// A number with its unit set smaller and quieter, as in FocusFlight's "1h 21m".
struct CeremonyMeasuredText: View {
    let value: String
    let unit: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .ceremonyType(.value)
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
            Text(unit)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
