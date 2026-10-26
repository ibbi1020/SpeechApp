import CoreGraphics
import Foundation

/// Time and pixel mapping for the scrolling feedback wave.
///
/// A long take shows a fixed 28-second window. The needle stays at 36% of the
/// lane and the wave moves under it. A short take keeps the whole file in the
/// lane and the needle walks. `0` in a waveform sample is loudest, so empty
/// time is filled with `silence` (`1`), not `0`.
public struct TapeLayout: Equatable, Sendable {
    public static let windowSeconds: TimeInterval = 28
    public static let needleFraction: Double = 0.36
    /// DSWaveformImage: `1` is the noise floor. `0` would draw a full-height spike.
    public static let silence: Float = 1

    public static let coastSpeed: CGFloat = 90
    public static let coastStopSpeed: CGFloat = 12
    public static let coastDecay: TimeInterval = 0.42
    public static let springResponse: TimeInterval = 0.35

    public let duration: TimeInterval
    public let width: CGFloat

    public init(duration: TimeInterval, width: CGFloat) {
        self.duration = duration
        self.width = width
    }

    public var scrolls: Bool {
        duration > Self.windowSeconds && width > 0
    }

    /// Seconds across the lane. The whole take, when it already fits.
    public var window: TimeInterval {
        guard duration > 0 else { return 0 }
        return scrolls ? Self.windowSeconds : duration
    }

    public var pixelsPerSecond: CGFloat {
        guard window > 0, width > 0 else { return 0 }
        return width / CGFloat(window)
    }

    /// Left edge of the lane, in seconds. Negative at the start of a long take,
    /// so the beginning of the audio sits under the needle.
    public func viewStart(time: TimeInterval, pull: CGFloat = 0) -> TimeInterval {
        guard scrolls, pixelsPerSecond > 0 else { return 0 }
        return time - Self.needleFraction * window - Double(pull) / Double(pixelsPerSecond)
    }

    public func x(for time: TimeInterval, viewStart: TimeInterval) -> CGFloat {
        guard window > 0, width > 0 else { return 0 }
        return CGFloat((time - viewStart) / window) * width
    }

    public func needleX(at time: TimeInterval) -> CGFloat {
        if scrolls { return width * CGFloat(Self.needleFraction) }
        return x(for: time, viewStart: 0)
    }

    /// The moment under `x`. A tap sets the playhead to this, which parks that moment on the needle.
    public func time(at x: CGFloat, viewStart: TimeInterval) -> TimeInterval {
        guard width > 0, window > 0, duration > 0 else { return 0 }
        let raw = viewStart + Double(x / width) * window
        return min(duration, max(0, raw))
    }

    public struct Hold: Equatable, Sendable {
        public var time: TimeInterval
        public var pull: CGFloat

        public init(time: TimeInterval, pull: CGFloat) {
            self.time = time
            self.pull = pull
        }
    }

    /// Finger right (`translation` > 0) moves the tape backward.
    public func dragged(from downTime: TimeInterval, translation: CGFloat) -> Hold {
        guard scrolls, pixelsPerSecond > 0 else {
            return Hold(time: min(max(0, downTime), max(0, duration)), pull: 0)
        }
        let proposed = downTime - Double(translation) / Double(pixelsPerSecond)
        return clamped(proposed)
    }

    public struct Motion: Equatable, Sendable {
        public enum Phase: Equatable, Sendable {
            case coast
            case spring
            case settled
        }

        public var time: TimeInterval
        public var velocity: CGFloat
        public var pull: CGFloat
        public var pullVelocity: CGFloat
        public var phase: Phase

        public init(
            time: TimeInterval,
            velocity: CGFloat,
            pull: CGFloat,
            pullVelocity: CGFloat,
            phase: Phase
        ) {
            self.time = time
            self.velocity = velocity
            self.pull = pull
            self.pullVelocity = pullVelocity
            self.phase = phase
        }
    }

    /// `velocity` is points per second. Positive means the finger was moving right.
    public func release(
        time: TimeInterval,
        pull: CGFloat,
        velocity: CGFloat,
        reduceMotion: Bool
    ) -> Motion {
        let parked = min(max(0, time), max(0, duration))
        if reduceMotion || !scrolls {
            return Motion(time: parked, velocity: 0, pull: 0, pullVelocity: 0, phase: .settled)
        }
        if pull != 0 {
            return Motion(time: parked, velocity: 0, pull: pull, pullVelocity: velocity, phase: .spring)
        }
        if abs(velocity) > Self.coastSpeed {
            return Motion(time: parked, velocity: velocity, pull: 0, pullVelocity: 0, phase: .coast)
        }
        return Motion(time: parked, velocity: 0, pull: 0, pullVelocity: 0, phase: .settled)
    }

    public func step(_ motion: Motion, dt: TimeInterval) -> Motion {
        guard dt > 0, motion.phase != .settled else { return motion }
        switch motion.phase {
        case .coast:
            return coast(motion, dt: dt)
        case .spring:
            return spring(motion, dt: dt)
        case .settled:
            return motion
        }
    }

    public struct Slice: Equatable, Sendable {
        public var samples: [Float]
        /// Points to shift the slice. Negative moves it left by less than one sample.
        public var offset: CGFloat

        public init(samples: [Float], offset: CGFloat) {
            self.samples = samples
            self.offset = offset
        }
    }

    /// One screen of samples. Indexes outside `cache` are silence, which is the empty side of the tape.
    public func slice(cache: [Float], viewStart: TimeInterval, scale: CGFloat) -> Slice {
        guard scale > 0, width > 0 else { return Slice(samples: [], offset: 0) }
        let count = Int(width * scale)
        guard count > 0 else { return Slice(samples: [], offset: 0) }
        guard duration > 0, !cache.isEmpty else {
            return Slice(samples: Array(repeating: Self.silence, count: count), offset: 0)
        }
        let origin = viewStart / duration * Double(cache.count)
        let first = Int(floor(origin))
        let fraction = origin - Double(first)
        let samples: [Float] = (0..<count).map { index in
            let cacheIndex = first + index
            guard cacheIndex >= 0, cacheIndex < cache.count else { return Self.silence }
            return cache[cacheIndex]
        }
        return Slice(samples: samples, offset: -CGFloat(fraction) / scale)
    }

    public struct WidthBridge: Equatable, Sendable {
        public var scale: CGFloat
        public var shift: CGFloat

        public init(scale: CGFloat, shift: CGFloat) {
            self.scale = scale
            self.shift = shift
        }
    }

    /// Keeps the sample under the needle under the needle while a new width is still decoding.
    public static func widthBridge(oldWidth: CGFloat, newWidth: CGFloat) -> WidthBridge {
        guard oldWidth > 0, newWidth > 0 else { return WidthBridge(scale: 1, shift: 0) }
        let scale = newWidth / oldWidth
        let shift = CGFloat(needleFraction) * oldWidth * (scale - 1)
        return WidthBridge(scale: scale, shift: shift)
    }

    /// Label times inside the visible window. `every` is the spacing, in seconds.
    public func marks(viewStart: TimeInterval, every: TimeInterval) -> [TimeInterval] {
        guard every > 0, window > 0, duration > 0 else { return [] }
        let end = viewStart + window
        var time = (viewStart / every).rounded(.up) * every
        var marks: [TimeInterval] = []
        while time <= end + 0.000_1 {
            if time >= -0.000_1, time <= duration + 0.000_1 {
                marks.append(min(duration, max(0, time)))
            }
            time += every
            if marks.count > 64 { break }
        }
        return marks
    }

    private func clamped(_ proposed: TimeInterval) -> Hold {
        if proposed < 0 {
            let over = CGFloat(-proposed) * pixelsPerSecond
            return Hold(time: 0, pull: rubberband(over: over, dimension: width))
        }
        if proposed > duration {
            let over = CGFloat(proposed - duration) * pixelsPerSecond
            return Hold(time: duration, pull: -rubberband(over: over, dimension: width))
        }
        return Hold(time: proposed, pull: 0)
    }

    private func coast(_ motion: Motion, dt: TimeInterval) -> Motion {
        guard pixelsPerSecond > 0 else {
            return Motion(time: motion.time, velocity: 0, pull: 0, pullVelocity: 0, phase: .settled)
        }
        var velocity = motion.velocity * CGFloat(exp(-dt / Self.coastDecay))
        let proposed = motion.time - Double(velocity) * dt / Double(pixelsPerSecond)
        if proposed < 0 || proposed > duration {
            let held = clamped(proposed)
            return Motion(
                time: held.time,
                velocity: 0,
                pull: held.pull,
                pullVelocity: velocity,
                phase: .spring
            )
        }
        if abs(velocity) < Self.coastStopSpeed {
            velocity = 0
            return Motion(time: proposed, velocity: 0, pull: 0, pullVelocity: 0, phase: .settled)
        }
        return Motion(time: proposed, velocity: velocity, pull: 0, pullVelocity: 0, phase: .coast)
    }

    private func spring(_ motion: Motion, dt: TimeInterval) -> Motion {
        let omega = (2 * Double.pi) / Self.springResponse
        let pull = Double(motion.pull)
        let velocity = Double(motion.pullVelocity)
        let acceleration = -omega * omega * pull - 2 * omega * velocity
        let nextVelocity = velocity + acceleration * dt
        let nextPull = pull + nextVelocity * dt
        if abs(nextPull) < 0.4, abs(nextVelocity) < 8 {
            return Motion(time: motion.time, velocity: 0, pull: 0, pullVelocity: 0, phase: .settled)
        }
        return Motion(
            time: motion.time,
            velocity: 0,
            pull: CGFloat(nextPull),
            pullVelocity: CGFloat(nextVelocity),
            phase: .spring
        )
    }

    private func rubberband(over: CGFloat, dimension: CGFloat) -> CGFloat {
        let coefficient: CGFloat = 0.55
        guard dimension > 0, over > 0 else { return 0 }
        return (over * dimension * coefficient) / (dimension + coefficient * over)
    }
}
