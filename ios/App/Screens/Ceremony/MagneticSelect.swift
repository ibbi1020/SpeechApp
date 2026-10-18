import SpeechAppKit
import SwiftUI

/// Three discs. The one you press turns white and the other two are pushed
/// off it. Names live in the type above, because a disc does not carry a word.
struct MagneticSelect: View {
    @Binding var selection: PracticeFormat.Kind

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var motion: MagneticMotion
    @State private var poses: [MagneticCluster.Pose]
    @State private var moving = false
    @State private var lean: CGSize = .zero
    @State private var hovered: PracticeFormat.Kind?

    init(selection: Binding<PracticeFormat.Kind>) {
        _selection = selection
        let motion = MagneticMotion(selected: Self.index(of: selection.wrappedValue))
        _motion = State(initialValue: motion)
        _poses = State(initialValue: motion.poses)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: moving == false)) { context in
            cluster
                .onChange(of: context.date) { _, date in
                    guard moving else { return }
                    moving = motion.step(to: date)
                    poses = motion.poses
                }
        }
        .id(moving)
        .frame(width: MagneticCluster.size.width, height: MagneticCluster.size.height)
        .onContinuousHover { phase in
            guard reduceMotion == false else { return }
            switch phase {
            case .active(let location):
                withAnimation(leanMotion) {
                    lean = MagneticCluster.lean(at: location, selected: Self.index(of: selection))
                }
            case .ended:
                withAnimation(leanMotion) { lean = .zero }
            }
        }
        .onChange(of: selection) { _, kind in
            motion.retarget(
                selected: Self.index(of: kind),
                stagger: reduceMotion == false,
                snap: reduceMotion
            )
            poses = motion.poses
            moving = reduceMotion == false
        }
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Exercise")
        .accessibilityAdjustableAction { adjustment in
            guard let index = PracticeFormat.all.firstIndex(where: { $0.kind == selection }) else { return }
            switch adjustment {
            case .increment:
                select(index: index + 1)
            case .decrement:
                select(index: index - 1)
            @unknown default:
                break
            }
        }
    }

    private var cluster: some View {
        ZStack {
            ForEach(Array(PracticeFormat.all.enumerated()), id: \.element.id) { index, format in
                disc(format, index: index)
            }
        }
        .frame(width: MagneticCluster.size.width, height: MagneticCluster.size.height)
    }

    private func disc(_ format: PracticeFormat, index: Int) -> some View {
        let chosen = format.kind == selection
        let pose = poses.indices.contains(index) ? poses[index] : .rest
        let center = MagneticCluster.restCenter(at: index)
        return Button {
            selection = format.kind
        } label: {
            Circle()
                .fill(fill(chosen: chosen, hovered: hovered == format.kind))
                .overlay {
                    if chosen == false {
                        Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                    }
                }
                .background {
                    if chosen == false, reduceTransparency == false {
                        Circle().fill(.ultraThinMaterial)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(format.title)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityRemoveTraits(chosen ? [] : .isSelected)
        .frame(width: MagneticCluster.chip, height: MagneticCluster.chip)
        .offset(lean)
        .rotationEffect(.degrees(pose.rotation))
        .scaleEffect(x: pose.scaleX, y: pose.scaleY)
        .position(x: center.x + pose.x, y: center.y + pose.y)
        .zIndex(chosen ? 1 : 0)
        .onHover { inside in
            if inside {
                hovered = format.kind
            } else if hovered == format.kind {
                hovered = nil
            }
        }
    }

    /// Unchosen is a frosted disc. Hover steps it toward white without
    /// changing its size. The chosen disc is white, because there is no picture.
    private func fill(chosen: Bool, hovered: Bool) -> Color {
        if chosen { return .white }
        if reduceTransparency { return .white.opacity(hovered ? 0.55 : 0.28) }
        // 34% white mixed into the 18% slab. A flat 12% of white disappears on black.
        return .white.opacity(hovered ? 0.4588 : 0.18)
    }

    /// Same curve as the prototype's skin. A group translation, so the gaps stay.
    private var leanMotion: Animation {
        .timingCurve(0.22, 1, 0.36, 1, duration: 0.22)
    }

    private static func index(of kind: PracticeFormat.Kind) -> Int {
        PracticeFormat.all.firstIndex { $0.kind == kind } ?? 0
    }

    private func select(index: Int) {
        let kinds = PracticeFormat.all.map(\.kind)
        guard kinds.indices.contains(index) else { return }
        selection = kinds[index]
    }
}

/// Springs for the three discs. A class so a frame can continue a settle
/// that started on the previous one, the same way the hum field keeps its dots.
@MainActor
private final class MagneticMotion {
    private struct Chip {
        var x: MagneticSpring
        var y: MagneticSpring
        var scaleX: MagneticSpring
        var scaleY: MagneticSpring
        var rotation: MagneticSpring

        var pose: MagneticCluster.Pose {
            MagneticCluster.Pose(
                x: x.value,
                y: y.value,
                scaleX: scaleX.value,
                scaleY: scaleY.value,
                rotation: rotation.value
            )
        }
    }

    private var chips: [Chip]
    private var last: Date?
    private(set) var poses: [MagneticCluster.Pose]

    init(selected: Int) {
        chips = (0 ..< MagneticCluster.count).map { _ in
            Chip(
                x: MagneticSpring(value: 0),
                y: MagneticSpring(value: 0),
                scaleX: MagneticSpring(value: 1),
                scaleY: MagneticSpring(value: 1),
                rotation: MagneticSpring(value: 0)
            )
        }
        poses = Array(repeating: .rest, count: MagneticCluster.count)
        retarget(selected: selected, stagger: false, snap: true)
    }

    func retarget(selected: Int, stagger: Bool, snap: Bool) {
        let aims = MagneticCluster.aims(selected: selected, stagger: stagger)
        for index in chips.indices {
            let aim = aims[index]
            let stiffness = aim.stiffness
            var chip = chips[index]
            chip.x.aim(
                target: aim.pose.x,
                stiffness: stiffness,
                mass: MagneticCluster.positionMass,
                zeta: aim.zeta,
                delay: aim.delay,
                snap: snap
            )
            chip.y.aim(
                target: aim.pose.y,
                stiffness: stiffness,
                mass: MagneticCluster.positionMass,
                zeta: aim.zeta,
                delay: aim.delay,
                snap: snap
            )
            chip.scaleX.aim(
                target: aim.pose.scaleX,
                stiffness: stiffness * MagneticCluster.scaleXStiffness,
                mass: MagneticCluster.scaleXMass,
                zeta: aim.zeta,
                delay: aim.delay,
                snap: snap
            )
            chip.scaleY.aim(
                target: aim.pose.scaleY,
                stiffness: stiffness * MagneticCluster.scaleYStiffness,
                mass: MagneticCluster.scaleYMass,
                zeta: aim.zeta,
                delay: aim.delay,
                snap: snap
            )
            chip.rotation.aim(
                target: aim.pose.rotation,
                stiffness: stiffness * MagneticCluster.rotationStiffness,
                mass: MagneticCluster.rotationMass,
                zeta: aim.zeta,
                delay: aim.delay,
                snap: snap
            )
            chips[index] = chip
        }
        last = nil
        if snap {
            poses = chips.map(\.pose)
        }
    }

    /// True while any spring is still moving.
    func step(to date: Date) -> Bool {
        let dt: Double
        if let last {
            dt = min(0.032, max(0, date.timeIntervalSince(last)))
        } else {
            dt = 1.0 / 60.0
        }
        self.last = date
        var moving = false
        for index in chips.indices {
            var chip = chips[index]
            if chip.x.step(dt: dt) { moving = true }
            if chip.y.step(dt: dt) { moving = true }
            if chip.scaleX.step(dt: dt) { moving = true }
            if chip.scaleY.step(dt: dt) { moving = true }
            if chip.rotation.step(dt: dt) { moving = true }
            chips[index] = chip
        }
        poses = chips.map(\.pose)
        return moving
    }
}
