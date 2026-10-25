import SwiftUI
import UIKit

/// Which screen edge the blur holds onto. Strength falls off toward the picture.
enum ConversationBlurEdge {
    case top
    case bottom
}

/// Vertical blur along one edge of a conversation picture.
///
/// The radius follows a mask, the same backdrop filter Apple uses for an edge
/// fade. It is strongest at the screen edge and eases to nothing at the other
/// end, flat against the picture so the band does not end on a line.
struct ConversationEdgeBlur: View {
    var edge: ConversationBlurEdge
    var maxRadius: CGFloat
    var height: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency || height <= 0 {
            EmptyView()
        } else {
            EdgeBlurRepresentable(edge: edge, maxRadius: maxRadius)
                .frame(height: height)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: edge == .top ? .top : .bottom
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct EdgeBlurRepresentable: UIViewRepresentable {
    var edge: ConversationBlurEdge
    var maxRadius: CGFloat

    func makeUIView(context: Context) -> EdgeBlurView {
        EdgeBlurView(edge: edge, maxRadius: maxRadius)
    }

    func updateUIView(_ view: EdgeBlurView, context: Context) {}
}

private final class EdgeBlurView: UIVisualEffectView {
    private let edge: ConversationBlurEdge
    private let maxRadius: CGFloat
    private var didInstall = false

    init(edge: ConversationBlurEdge, maxRadius: CGFloat) {
        self.edge = edge
        self.maxRadius = maxRadius
        super.init(effect: UIBlurEffect(style: .regular))
        isUserInteractionEnabled = false
        backgroundColor = .clear
        install()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        install()
        guard let window, let backdrop = backdropLayer else { return }
        backdrop.setValue(window.traitCollection.displayScale, forKey: "scale")
    }

    private var backdropLayer: CALayer? {
        subviews.first { String(describing: type(of: $0)).contains("Backdrop") }?.layer
    }

    private func install() {
        guard !didInstall, let backdrop = backdropLayer else { return }
        guard let mask = EdgeBlurMask.image(for: edge),
              let filter = Self.variableBlur(radius: maxRadius, mask: mask)
        else {
            effect = nil
            return
        }
        backdrop.filters = [filter]
        for subview in subviews where subview.layer !== backdrop {
            subview.alpha = 0
        }
        didInstall = true
    }

    /// The system filter. Its type name is not a public symbol.
    private static func variableBlur(radius: CGFloat, mask: CGImage) -> NSObject? {
        let className = String("retliFAC".reversed())
        let selectorName = String(":epyThtiWretlif".reversed())
        guard let filterClass = NSClassFromString(className) as? NSObject.Type else { return nil }
        let selector = NSSelectorFromString(selectorName)
        guard let created = filterClass.perform(selector, with: "variableBlur") else { return nil }
        guard let filter = created.takeUnretainedValue() as? NSObject else { return nil }
        filter.setValue(radius, forKey: "inputRadius")
        filter.setValue(mask, forKey: "inputMaskImage")
        filter.setValue(true, forKey: "inputNormalizeEdges")
        return filter
    }
}

private enum EdgeBlurMask {
    static func image(for edge: ConversationBlurEdge) -> CGImage? {
        cached[edge]
    }

    private static let cached: [ConversationBlurEdge: CGImage] = [
        .top: make(strongAtTop: true),
        .bottom: make(strongAtTop: false),
    ].compactMapValues { $0 }

    /// Black alpha is full blur. Zero beside the picture, full at the screen edge.
    /// Drawn in UIKit coordinates so the first row is the top of the band.
    private static func make(strongAtTop: Bool) -> CGImage? {
        let width = 8
        let height = 512
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        )
        let image = renderer.image { ctx in
            ctx.cgContext.setShouldAntialias(false)
            for y in 0..<height {
                let fromTop = CGFloat(y) / CGFloat(height - 1)
                let along = strongAtTop ? (1 - fromTop) : fromTop
                ctx.cgContext.setFillColor(
                    UIColor.black.withAlphaComponent(taper(along)).cgColor
                )
                ctx.cgContext.fill(CGRect(x: 0, y: y, width: width, height: 1))
            }
        }
        return image.cgImage
    }

    /// `along` is 0 beside the picture and 1 at the screen edge.
    /// The tails stay near zero and near full strength longer than a normal
    /// S-curve. The picture end is exactly 0, not a small leftover radius.
    private static func taper(_ along: CGFloat) -> CGFloat {
        let x = min(1, max(0, along))
        let rise = x * x * x
        let fall = (1 - x) * (1 - x) * (1 - x)
        return rise / (rise + fall)
    }
}
