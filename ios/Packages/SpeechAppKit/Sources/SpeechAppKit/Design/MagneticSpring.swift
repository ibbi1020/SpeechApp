import Foundation

/// One damped spring. The magnetic cluster runs five of these per disc
/// (x, y, scale x, scale y, rotation) so the squash can lead the settle.
///
/// `dt` is seconds. Damping is a ratio of critical, not a raw coefficient,
/// so the same Bounce means the same arrival on every disc.
public struct MagneticSpring: Equatable, Sendable {
    public var value: Double
    public var velocity: Double
    public var target: Double
    public var delay: Double
    public var stiffness: Double
    public var mass: Double
    public var damping: Double

    public init(value: Double) {
        self.value = value
        self.velocity = 0
        self.target = value
        self.delay = 0
        self.stiffness = 300
        self.mass = 1
        self.damping = 30
    }

    /// Point the spring at a new rest. Delay is applied only when the target
    /// actually changes, so a stream of identical aims cannot hold it still.
    /// `snap` is Reduce Motion: no travel, no blur's sibling in the springs.
    public mutating func aim(
        target: Double,
        stiffness: Double,
        mass: Double,
        zeta: Double,
        delay: Double,
        snap: Bool
    ) {
        self.stiffness = stiffness
        self.mass = mass
        self.damping = 2 * (stiffness * mass).squareRoot() * zeta
        if snap {
            value = target
            velocity = 0
            self.target = target
            self.delay = 0
            return
        }
        if self.target != target {
            self.target = target
            self.delay = delay
        }
    }

    /// Advances one step. Returns true while there is still motion left,
    /// including a delay that has not elapsed.
    public mutating func step(dt: Double) -> Bool {
        let dt = min(0.032, max(0, dt))
        if delay > 0 {
            delay = max(0, delay - dt)
            return true
        }
        let delta = target - value
        if abs(delta) < 0.02, abs(velocity) < 0.02 {
            value = target
            velocity = 0
            return false
        }
        let acceleration = (stiffness * delta - damping * velocity) / mass
        velocity += acceleration * dt
        value += velocity * dt
        return true
    }
}
