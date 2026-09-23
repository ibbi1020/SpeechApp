import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Stadium aurora presence — listen / connect / speak. Port of `prototypes/mic-visualizer`.
struct AuroraPill: View {
    enum Mode: Equatable, Sendable {
        case listen
        case connect
        case speak
    }

    var energy: Float
    var mode: Mode
    var animating: Bool = true
    var glass: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    /// Reference type so TimelineView can advance energy without invalidating the SwiftUI graph.
    @State private var smoother = EnergySmoother()

    private static let pillWidth: CGFloat = 132
    private static let pillHeight: CGFloat = 52
    private static let frozenTime: Double = 1.25

    private var shouldAnimate: Bool {
        animating && !reduceMotion
    }

    private var accessibilityStatus: String {
        switch mode {
        case .speak: "Speaking."
        case .connect: "Connecting."
        case .listen:
            smoother.energy > 0.28 ? "Hearing you." : "Listening."
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !shouldAnimate)) { timeline in
            let wall = timeline.date.timeIntervalSinceReferenceDate
            let rawT = shouldAnimate ? wall : Self.frozenTime
            let frameEnergy = smoother.advance(
                wall: wall,
                target: energyTarget(rawT: rawT),
                mode: mode
            )
            Canvas { context, size in
                AuroraPillRenderer.draw(
                    context: &context,
                    size: size,
                    rawT: rawT,
                    energy: frameEnergy,
                    mode: mode,
                    scale: displayScale
                )
            }
            .accessibilityHidden(true)
        }
        .frame(width: Self.pillWidth, height: Self.pillHeight)
        .glassEffect(glass ? .regular : .identity, in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityStatus)
        .onAppear {
            smoother.reset(to: initialEnergy())
        }
        .onChange(of: mode) { _, _ in
            smoother.resetClock()
        }
    }

    private func initialEnergy() -> Double {
        switch mode {
        case .connect: 0.28
        case .speak: AuroraPillMath.speakEnergyTarget(raw: Self.frozenTime)
        case .listen: max(0.1, Double(energy))
        }
    }

    private func energyTarget(rawT: Double) -> Double {
        switch mode {
        case .connect:
            0.28
        case .speak:
            AuroraPillMath.speakEnergyTarget(raw: rawT)
        case .listen:
            max(0.1, min(1, Double(energy)))
        }
    }
}

// MARK: - Energy smoother

@MainActor
private final class EnergySmoother {
    private(set) var energy: Double = 0.1
    private var lastTick: TimeInterval?

    func reset(to value: Double) {
        energy = value
        lastTick = nil
    }

    func resetClock() {
        lastTick = nil
    }

    func advance(wall: TimeInterval, target: Double, mode: AuroraPill.Mode) -> Double {
        let dt: Double
        if let lastTick {
            dt = min(0.05, max(0, wall - lastTick))
        } else {
            dt = 1.0 / 60.0
        }
        lastTick = wall
        energy = AuroraPillMath.smoothEnergy(
            current: energy,
            target: target,
            dt: dt,
            mode: mode
        )
        return energy
    }
}

// MARK: - Renderer

private enum AuroraPillRenderer {
    private static let sampleCount = 72
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    static func draw(
        context: inout GraphicsContext,
        size: CGSize,
        rawT: Double,
        energy: Double,
        mode: AuroraPill.Mode,
        scale: CGFloat
    ) {
        let e = min(1, max(0, energy))
        let tDraw = AuroraPillMath.tDraw(raw: rawT, mode: mode)
        let field = AuroraPillMath.field(energy: e, mode: mode)
        let peaks = AuroraPillMath.peaks(tDraw: tDraw, energy: e, mode: mode)
        let blur = AuroraPillMath.blurRadius(height: size.height, mode: mode)

        let stadium = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2)
        context.fill(stadium, with: .color(Color(red: 5 / 255, green: 5 / 255, blue: 8 / 255)))

        var clipped = context
        clipped.clip(to: stadium)

        // Body
        paint(
            into: &clipped,
            size: size,
            t: tDraw,
            energy: e,
            peaks: peaks,
            field: field,
            blur: blur,
            yShift: 0,
            stops: AuroraPillMath.bodyStops(energy: e, mode: mode),
            blend: .normal,
            scale: scale
        )

        // Listen shelf — low echo under the main ridge
        if mode == .listen {
            let shelfPeaks = peaks.map {
                AuroraPillMath.Peak(x: $0.x, amp: $0.amp * 0.22)
            }
            paint(
                into: &clipped,
                size: size,
                t: tDraw + 1.3,
                energy: e,
                peaks: shelfPeaks,
                field: field,
                blur: blur * 1.15,
                yShift: size.height * 0.07,
                stops: AuroraPillMath.shelfStops(energy: e),
                blend: .normal,
                scale: scale
            )
        }

        // Cyan filament — listen and speak only
        if mode != .connect {
            paint(
                into: &clipped,
                size: size,
                t: tDraw,
                energy: e,
                peaks: peaks,
                field: field,
                blur: blur * 0.8,
                yShift: -size.height * 0.015,
                stops: AuroraPillMath.filamentStops(energy: e, mode: mode),
                blend: .screen,
                scale: scale
            )
        }

        paint(
            into: &clipped,
            size: size,
            t: tDraw,
            energy: e,
            peaks: peaks,
            field: field,
            blur: blur * 1.9,
            yShift: -size.height * 0.04,
            stops: AuroraPillMath.glowStops(),
            blend: .screen,
            scale: scale
        )

        paintColorAccents(
            into: &clipped,
            size: size,
            tDraw: tDraw,
            energy: e,
            peaks: peaks,
            field: field,
            blur: blur,
            mode: mode,
            scale: scale
        )
    }

    private static func paintColorAccents(
        into context: inout GraphicsContext,
        size: CGSize,
        tDraw: Double,
        energy e: Double,
        peaks: [AuroraPillMath.Peak],
        field: AuroraPillMath.Field,
        blur: CGFloat,
        mode: AuroraPill.Mode,
        scale: CGFloat
    ) {
        guard mode == .listen else { return }

        let k = AuroraPillMath.smoothstep(0.36, 0.78, e)
        guard k > 0.02 else { return }

        for (index, peak) in peaks.enumerated() {
            let tall = k * AuroraPillMath.smoothstep(0.62, 0.95, peak.amp)
            guard tall > 0.02 else { continue }

            if index == peaks.count - 1 {
                paint(
                    into: &context,
                    size: size,
                    t: tDraw,
                    energy: e,
                    peaks: [peak],
                    field: field,
                    blur: blur * 0.85,
                    yShift: -size.height * 0.02,
                    stops: AuroraPillMath.magentaStops(tall: tall),
                    blend: .screen,
                    scale: scale
                )
            }
            paint(
                into: &context,
                size: size,
                t: tDraw,
                energy: e,
                peaks: [AuroraPillMath.Peak(x: peak.x, amp: peak.amp * 1.05)],
                field: field,
                blur: blur * 0.65,
                yShift: -size.height * 0.03,
                stops: AuroraPillMath.greenStops(tall: tall),
                blend: .screen,
                scale: scale
            )
        }
    }

    private static func paint(
        into context: inout GraphicsContext,
        size: CGSize,
        t: Double,
        energy: Double,
        peaks: [AuroraPillMath.Peak],
        field: AuroraPillMath.Field,
        blur: CGFloat,
        yShift: CGFloat,
        stops: [AuroraPillMath.GradientStop],
        blend: GraphicsContext.BlendMode,
        scale: CGFloat
    ) {
        guard let image = makeBlurredHill(
            size: size,
            t: t,
            energy: energy,
            peaks: peaks,
            field: field,
            blur: blur,
            yShift: yShift,
            stops: stops,
            scale: scale
        ) else { return }

        context.blendMode = blend
        context.draw(Image(uiImage: image), in: CGRect(origin: .zero, size: size))
        context.blendMode = .normal
    }

    /// Blur-then-crop so soft light meets a hard capsule edge after clip.
    private static func makeBlurredHill(
        size: CGSize,
        t: Double,
        energy: Double,
        peaks: [AuroraPillMath.Peak],
        field: AuroraPillMath.Field,
        blur: CGFloat,
        yShift: CGFloat,
        stops: [AuroraPillMath.GradientStop],
        scale: CGFloat
    ) -> UIImage? {
        let pad = blur * 2.5
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: size.width + pad * 2, height: size.height + pad * 2),
            format: format
        )
        let unblurred = renderer.image { ctx in
            let cg = ctx.cgContext
            cg.translateBy(x: pad, y: pad)

            let path = ridgePath(
                size: size,
                pad: pad,
                t: t,
                energy: energy,
                peaks: peaks,
                field: field,
                yShift: yShift
            )
            cg.addPath(path)
            cg.clip()

            let top = (0.22 - energy * 0.14) * Double(size.height)
            let colors = stops.map { stop in
                UIColor(
                    red: stop.color.r / 255,
                    green: stop.color.g / 255,
                    blue: stop.color.b / 255,
                    alpha: stop.color.a
                ).cgColor
            } as CFArray
            let locations = stops.map(\.location)
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: locations
            ) else { return }

            cg.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: top),
                end: CGPoint(x: 0, y: size.height),
                options: []
            )
        }

        return gaussianBlurred(unblurred, blurPoints: blur, scale: scale, cropSize: size, pad: pad)
    }

    private static func ridgePath(
        size: CGSize,
        pad: CGFloat,
        t: Double,
        energy: Double,
        peaks: [AuroraPillMath.Peak],
        field: AuroraPillMath.Field,
        yShift: CGFloat
    ) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -pad, y: size.height + pad))
        for i in 0...Self.sampleCount {
            let xn = Double(i) / Double(Self.sampleCount)
            let y = AuroraPillMath.ridgeY(
                xn: xn,
                t: t,
                energy: energy,
                peaks: peaks,
                field: field
            ) * Double(size.height) + Double(yShift)
            path.addLine(to: CGPoint(x: xn * Double(size.width), y: y))
        }
        path.addLine(to: CGPoint(x: size.width + pad, y: size.height + pad))
        path.closeSubpath()
        return path
    }

    private static func gaussianBlurred(
        _ image: UIImage,
        blurPoints: CGFloat,
        scale: CGFloat,
        cropSize: CGSize,
        pad: CGFloat
    ) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let ciImage = CIImage(cgImage: cgImage)
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = ciImage.clampedToExtent()
        filter.radius = Float(blurPoints * scale)
        guard let output = filter.outputImage?.cropped(to: ciImage.extent),
              let blurred = ciContext.createCGImage(output, from: output.extent)
        else {
            return image
        }

        let crop = CGRect(
            x: pad * scale,
            y: pad * scale,
            width: cropSize.width * scale,
            height: cropSize.height * scale
        ).integral
        let final = blurred.cropping(to: crop) ?? blurred
        return UIImage(cgImage: final, scale: scale, orientation: .up)
    }
}
