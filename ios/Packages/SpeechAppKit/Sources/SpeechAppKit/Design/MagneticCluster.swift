import CoreGraphics
import Foundation

/// Three discs on a triangle, and the field that pushes the other two off
/// the one you chose. Ported from `prototypes/magnetic-select`.
///
/// Pull, bounce, and give are the prototype's knobs, fixed at 55 / 55 / 50.
/// The push does not decay with distance. A decaying push closed the pair of
/// discs that sat on the same ray out of the magnet. Falloff still staggers
/// the shove, tips the disc, and shrinks the neighbours.
public enum MagneticCluster {
    public static let chip: CGFloat = 66
    public static let pad: CGFloat = 39
    public static let pitch: CGFloat = 67.5
    public static let spread: Double = 2.8
    /// How far past the cluster's own edge the group lean survives.
    public static let fade: CGFloat = 66

    public static let pull = 55.0
    public static let bounce = 55.0
    public static let give = 50.0

    /// Index 0 is the top of the triangle. Reading, monologue, conversation.
    public static let points: [CGPoint] = [
        CGPoint(x: 0, y: -39),
        CGPoint(x: 33.75, y: 19.5),
        CGPoint(x: -33.75, y: 19.5),
    ]

    public static let positionMass = 0.9
    public static let scaleXMass = 0.8
    public static let scaleYMass = 0.95
    public static let rotationMass = 1.0
    /// Scale x is stiffer than scale y, so the disc goes wide before it goes tall.
    public static let scaleXStiffness: Double = 1.24
    public static let scaleYStiffness: Double = 0.86
    public static let rotationStiffness: Double = 0.8

    public static var count: Int { points.count }

    public static var size: CGSize {
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min() ?? 0
        let minY = ys.min() ?? 0
        return CGSize(
            width: (xs.max() ?? 0) - minX + chip + pad * 2,
            height: (ys.max() ?? 0) - minY + chip + pad * 2
        )
    }

    /// Centre of a disc on the lattice, before the field moves it.
    public static func restCenter(at index: Int) -> CGPoint {
        let point = points[index]
        let minX = points.map(\.x).min() ?? 0
        let minY = points.map(\.y).min() ?? 0
        return CGPoint(
            x: point.x - minX + pad + chip / 2,
            y: point.y - minY + pad + chip / 2
        )
    }

    public struct Pose: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var scaleX: Double
        public var scaleY: Double
        public var rotation: Double

        public init(x: Double, y: Double, scaleX: Double, scaleY: Double, rotation: Double) {
            self.x = x
            self.y = y
            self.scaleX = scaleX
            self.scaleY = scaleY
            self.rotation = rotation
        }

        public static let rest = Pose(x: 0, y: 0, scaleX: 1, scaleY: 1, rotation: 0)
    }

    /// Where one disc is going, and the spring settings that take it there.
    public struct Aim: Equatable, Sendable {
        public var pose: Pose
        public var stiffness: Double
        public var delay: Double
        public var zeta: Double
    }

    public struct Hub: Equatable, Sendable {
        public var center: CGPoint
        public var radius: CGFloat
    }

    /// Rest targets for the current choice. `stagger` delays the far discs
    /// so the shove travels outward. A knob drag would pass false. This app
    /// has no knobs, so a new choice is the only caller that staggers.
    public static func aims(selected: Int, stagger: Bool) -> [Aim] {
        let metrics = metrics()
        let slots = field(selected: selected)
        return slots.indices.map { index in
            let slot = slots[index]
            let chosen = index == selected && points.indices.contains(selected)
            let far = min(slot.far, 3)
            let stiffness = 300 + 280 * (1 - far / 4)
            let scale = chosen ? metrics.grow : 1 - metrics.cower * slot.fall
            return Aim(
                pose: Pose(
                    x: slot.ux * slot.push,
                    y: slot.uy * slot.push,
                    scaleX: scale,
                    scaleY: scale,
                    rotation: slot.ux * metrics.tilt * slot.fall
                ),
                stiffness: stiffness,
                delay: stagger ? slot.far * 0.022 : 0,
                zeta: metrics.zeta
            )
        }
    }

    /// The point the group leans about, and the distance to the furthest
    /// disc's outer edge. The lean is measured in that radius.
    public static func hub(selected: Int) -> Hub {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let slots = field(selected: selected)
        var radius: CGFloat = 1
        for index in slots.indices {
            let rest = restCenter(at: index)
            let slot = slots[index]
            let settled = CGPoint(
                x: rest.x + CGFloat(slot.ux * slot.push),
                y: rest.y + CGFloat(slot.uy * slot.push)
            )
            radius = max(radius, hypot(settled.x - center.x, settled.y - center.y) + chip / 2)
        }
        return Hub(center: center, radius: radius)
    }

    /// Group lean, in points. Nothing at the centre, full at the edge, gone
    /// by `fade` past it. The same offset is applied to every disc, so the
    /// gaps do not change. A per-disc hover scale would open them.
    public static func lean(at point: CGPoint, selected: Int) -> CGSize {
        let hub = hub(selected: selected)
        let dx = point.x - hub.center.x
        let dy = point.y - hub.center.y
        let distance = hypot(dx, dy)
        guard distance > 0 else { return .zero }
        let rise = min(1, distance / hub.radius)
        let away: CGFloat = distance <= hub.radius
            ? 1
            : max(0, 1 - (distance - hub.radius) / fade)
        let drawn = rise * away * (2 + CGFloat(give / 100) * 5)
        guard drawn > 0 else { return .zero }
        return CGSize(width: dx / distance * drawn, height: dy / distance * drawn)
    }

    private struct Metrics {
        var grow: Double
        var room: Double
        var aura: Double
        var tilt: Double
        var cower: Double
        var zeta: Double
    }

    private struct Slot {
        var far: Double
        var fall: Double
        var push: Double
        var ux: Double
        var uy: Double

        static let still = Slot(far: 0, fall: 0, push: 0, ux: 0, uy: 0)
    }

    private static func metrics(
        pull rawPull: Double = pull,
        bounce rawBounce: Double = bounce
    ) -> Metrics {
        let amount = min(100, max(0, rawPull)) / 100
        let grow = 1.16 + 0.22 * amount
        return Metrics(
            grow: grow,
            room: (Double(chip) * (grow - 1)) / 2,
            aura: 3 + 9 * amount,
            tilt: 5 * amount,
            cower: 0.04 + 0.09 * amount,
            zeta: 0.9 - 0.48 * (min(100, max(0, rawBounce)) / 100)
        )
    }

    private static func field(selected: Int) -> [Slot] {
        let metrics = metrics()
        return points.indices.map { index in
            guard points.indices.contains(selected), index != selected else { return .still }
            let point = points[index]
            let origin = points[selected]
            let dx = Double(point.x - origin.x)
            let dy = Double(point.y - origin.y)
            let gap = hypot(dx, dy)
            let far = gap / Double(pitch)
            let push = metrics.room + metrics.aura
            return Slot(
                far: far,
                fall: exp(-(far - 1) / spread),
                push: push,
                ux: gap == 0 ? 0 : dx / gap,
                uy: gap == 0 ? 0 : dy / gap
            )
        }
    }
}
