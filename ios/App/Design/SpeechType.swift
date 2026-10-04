import SwiftUI
import UIKit

/// Text roles for the app.
///
/// Headings use a perfect fourth (4/3): each step is one-third larger than the one below.
/// Body stays at 16pt. Sizes are rounded to whole points.
///
/// 16 × 4/3 = 21 (h4)
/// 16 × 4/3 × 4/3 = 28 (h3)
/// 16 × 4/3 × 4/3 × 4/3 = 38 (h2)
/// 16 × 4/3 × 4/3 × 4/3 × 4/3 = 51 (h1)
///
/// Steps below body are not the same ratio. Another step down would be 12pt, which is
/// already as small as a label should go, so subtext is 14 and labels are 12.
enum SpeechType {
    /// PostScript name of `font/InstrumentSerif-Regular.ttf` (weight 400).
    static let instrumentSerif = "InstrumentSerif-Regular"

    static let bodySize: CGFloat = 16
    /// Perfect fourth. Used for the four heading steps above body.
    static let headingRatio: CGFloat = 4.0 / 3.0

    enum Role {
        case h1
        case h2
        case h3
        case h4
        case body
        case subtext
        case label
    }

    struct Metrics {
        var size: CGFloat
        /// Extra space between letters, as a fraction of the point size. Negative is tighter.
        var trackingEm: CGFloat
        /// Target line height as a multiple of the point size.
        var lineHeight: CGFloat
        /// Dynamic Type bucket. The role's own size is what you see at the Large setting.
        var relativeTo: Font.TextStyle
        var usesSerif: Bool
        var systemWeight: Font.Weight
    }

    static func metrics(_ role: Role) -> Metrics {
        switch role {
        case .h1:
            Metrics(size: stepped(4), trackingEm: -0.025, lineHeight: 1.1, relativeTo: .largeTitle, usesSerif: true, systemWeight: .regular)
        case .h2:
            Metrics(size: stepped(3), trackingEm: -0.02, lineHeight: 1.12, relativeTo: .largeTitle, usesSerif: true, systemWeight: .regular)
        case .h3:
            Metrics(size: stepped(2), trackingEm: -0.015, lineHeight: 1.15, relativeTo: .title, usesSerif: true, systemWeight: .regular)
        case .h4:
            Metrics(size: stepped(1), trackingEm: -0.01, lineHeight: 1.2, relativeTo: .title3, usesSerif: true, systemWeight: .regular)
        case .body:
            Metrics(size: bodySize, trackingEm: 0, lineHeight: 1.45, relativeTo: .body, usesSerif: false, systemWeight: .regular)
        case .subtext:
            Metrics(size: 14, trackingEm: 0, lineHeight: 1.4, relativeTo: .subheadline, usesSerif: false, systemWeight: .regular)
        case .label:
            Metrics(size: 12, trackingEm: 0.06, lineHeight: 1.25, relativeTo: .caption, usesSerif: false, systemWeight: .semibold)
        }
    }

    static func font(_ role: Role, size: CGFloat) -> Font {
        let metrics = metrics(role)
        if metrics.usesSerif {
            return .custom(instrumentSerif, size: size)
        }
        return .system(size: size, weight: metrics.systemWeight)
    }

    /// Points to add between lines so the result matches `lineHeight`.
    static func extraLeading(_ role: Role, size: CGFloat) -> CGFloat {
        let metrics = metrics(role)
        let font = uiFont(role, size: size)
        return max(0, size * metrics.lineHeight - font.lineHeight)
    }

    /// `steps` above the 16pt body, using the perfect-fourth ratio, rounded.
    private static func stepped(_ steps: Int) -> CGFloat {
        (bodySize * pow(headingRatio, CGFloat(steps))).rounded()
    }

    private static func uiFont(_ role: Role, size: CGFloat) -> UIFont {
        let metrics = metrics(role)
        if metrics.usesSerif, let font = UIFont(name: instrumentSerif, size: size) {
            return font
        }
        return .systemFont(ofSize: size, weight: uiWeight(metrics.systemWeight))
    }

    private static func uiWeight(_ weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .semibold: .semibold
        default: .regular
        }
    }

    /// Same size as `speechType` at the Large setting, scaled for `traits`.
    fileprivate static func barFont(_ role: Role, compatibleWith traits: UITraitCollection) -> UIFont {
        let metrics = metrics(role)
        let base = uiFont(role, size: metrics.size)
        return UIFontMetrics(forTextStyle: barTextStyle(metrics.relativeTo))
            .scaledFont(for: base, compatibleWith: traits)
    }

    private static func barTextStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
        if style == .largeTitle { return .largeTitle }
        if style == .title3 { return .title3 }
        return .body
    }
}

private struct SpeechTextStyle: ViewModifier {
    var role: SpeechType.Role
    @ScaledMetric private var size: CGFloat

    init(_ role: SpeechType.Role) {
        self.role = role
        let metrics = SpeechType.metrics(role)
        _size = ScaledMetric(wrappedValue: metrics.size, relativeTo: metrics.relativeTo)
    }

    func body(content: Content) -> some View {
        let metrics = SpeechType.metrics(role)
        content
            .font(SpeechType.font(role, size: size))
            .tracking(size * metrics.trackingEm)
            .lineSpacing(SpeechType.extraLeading(role, size: size))
    }
}

/// Page title for this screen.
///
/// The title string is the screen's own navigation title, so it pushes and pops
/// with the screen. A `ToolbarItem` in the bar is a separate view the bar keeps
/// until after the transition, which is why "Orator" and "Passages" used to stick.
/// Large titles use h1. Inline titles use h4. The bar only receives those fonts.
private struct SpeechPageTitle: ViewModifier {
    var title: String
    var large: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(large ? .large : .inline)
            .background {
                SpeechBarFonts(dynamicTypeSize: dynamicTypeSize)
            }
    }
}

/// Writes h1 and h4 onto the bar without changing its material.
private struct SpeechBarFonts: UIViewControllerRepresentable {
    var dynamicTypeSize: DynamicTypeSize

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        // Read so a text-size change runs `apply` and rescales h1 and h4.
        _ = dynamicTypeSize
        controller.apply()
    }

    final class Controller: UIViewController {
        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        override func viewIsAppearing(_ animated: Bool) {
            super.viewIsAppearing(animated)
            apply()
        }

        func apply() {
            guard let bar = navigationController?.navigationBar else { return }
            SpeechBarFont.apply(to: bar)
        }
    }
}

@MainActor
private enum SpeechBarFont {
    static func apply(to bar: UINavigationBar) {
        let traits = bar.traitCollection
        assign(bar.standardAppearance, traits: traits) { bar.standardAppearance = $0 }
        if let edge = bar.scrollEdgeAppearance {
            assign(edge, traits: traits) { bar.scrollEdgeAppearance = $0 }
        }
        if let compact = bar.compactAppearance {
            assign(compact, traits: traits) { bar.compactAppearance = $0 }
        }
        if let compactEdge = bar.compactScrollEdgeAppearance {
            assign(compactEdge, traits: traits) { bar.compactScrollEdgeAppearance = $0 }
        }
    }

    private static func assign(
        _ appearance: UINavigationBarAppearance,
        traits: UITraitCollection,
        write: (UINavigationBarAppearance) -> Void
    ) {
        guard let styled = styled(appearance, traits: traits) else { return }
        write(styled)
    }

    /// `nil` when h1 and h4 are already on this appearance.
    private static func styled(
        _ appearance: UINavigationBarAppearance,
        traits: UITraitCollection
    ) -> UINavigationBarAppearance? {
        let large = SpeechType.barFont(.h1, compatibleWith: traits)
        let inline = SpeechType.barFont(.h4, compatibleWith: traits)
        let largeKern = large.pointSize * SpeechType.metrics(.h1).trackingEm
        let inlineKern = inline.pointSize * SpeechType.metrics(.h4).trackingEm
        if hasFont(appearance.largeTitleTextAttributes, large, largeKern),
           hasFont(appearance.titleTextAttributes, inline, inlineKern) {
            return nil
        }
        let copy = appearance.copy()
        copy.largeTitleTextAttributes = merged(copy.largeTitleTextAttributes, font: large, kern: largeKern)
        copy.titleTextAttributes = merged(copy.titleTextAttributes, font: inline, kern: inlineKern)
        return copy
    }

    private static func hasFont(
        _ attributes: [NSAttributedString.Key: Any],
        _ font: UIFont,
        _ kern: CGFloat
    ) -> Bool {
        guard let current = attributes[.font] as? UIFont, current == font else { return false }
        return abs(kernValue(attributes[.kern]) - kern) < 0.05
    }

    private static func kernValue(_ value: Any?) -> CGFloat {
        if let kern = value as? CGFloat { return kern }
        if let kern = value as? NSNumber { return CGFloat(kern.doubleValue) }
        return 0
    }

    private static func merged(
        _ attributes: [NSAttributedString.Key: Any],
        font: UIFont,
        kern: CGFloat
    ) -> [NSAttributedString.Key: Any] {
        var attributes = attributes
        attributes[.font] = font
        attributes[.kern] = kern
        return attributes
    }
}

extension View {
    func speechType(_ role: SpeechType.Role) -> some View {
        modifier(SpeechTextStyle(role))
    }

    /// Page title. The string stays on this screen so the back button can name it.
    /// Large titles use h1. Inline titles use h4.
    func speechPageTitle(_ title: String, large: Bool = false) -> some View {
        modifier(SpeechPageTitle(title: title, large: large))
    }
}
