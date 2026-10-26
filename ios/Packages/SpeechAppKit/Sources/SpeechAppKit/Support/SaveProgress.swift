import Foundation

/// One real step of saving a take. The ring moves only when one of these moves.
public enum SaveStep: String, Sendable, Equatable, CaseIterable {
    case catchingWords
    case reading
    case cleaning
    case encoding
    case writing

    /// The one line under the ring.
    public var sentence: String {
        switch self {
        case .catchingWords:
            "Catching the last words"
        case .cleaning:
            "Cleaning the recording"
        case .reading, .encoding, .writing:
            "Saving your take"
        }
    }
}

/// How far a save has gotten. Time passing does not move this.
///
/// Slice sizes come from how long the take is. Cleaning is most of a short take.
/// A take past three minutes, or a save on the simulator, skips cleaning and
/// spends the ring on encoding. A skipped step is removed. The ring does not jump.
public struct SaveProgress: Sendable, Equatable {
    /// Shown value while the take is still being saved. 1 means it is ready.
    public static let waitingCap = 0.92

    /// Words when a step has not moved for a while. The ring stays where it is.
    public static let slowLine = "Taking a bit longer than expected…"
    public static let stillSavingLine = "Still saving."

    /// A step that has not moved for this long gets the slow line.
    public static let slowLineDelay: TimeInterval = 8

    /// A step that has not moved for this long says the save is still going.
    public static let stillSavingDelay: TimeInterval = 20

    /// Offline denoise is slower than realtime, so takes past this skip it.
    public static let cleanLimit: TimeInterval = 180

    private var slices: [SaveStep: Double]
    private var current: SaveStep
    private var fraction: Double

    public init(durationSeconds: TimeInterval, willClean: Bool, includesTranscription: Bool) {
        let duration = max(0, durationSeconds)
        let raw: [SaveStep: Double] = [
            .catchingWords: includesTranscription ? 4 : 0,
            .reading: 0.1 * duration,
            .cleaning: willClean ? 1.5 * duration : 0,
            .encoding: willClean ? 0.3 * duration : 0.5 * duration,
            .writing: 1,
        ]
        let total = raw.values.reduce(0, +)
        let planned = raw.mapValues { $0 / total }
        slices = planned
        current = SaveStep.allCases.first { planned[$0, default: 0] > 0 } ?? .writing
        fraction = 0
    }

    /// Cleaning runs on device for takes up to three minutes. The simulator skips it.
    public static func needsCleaning(durationSeconds: TimeInterval, runsOnSimulator: Bool) -> Bool {
        !runsOnSimulator && durationSeconds <= cleanLimit
    }

    public static func showsSlowLine(unchangedFor seconds: TimeInterval) -> Bool {
        seconds >= slowLineDelay
    }

    public static func showsStillSaving(unchangedFor seconds: TimeInterval) -> Bool {
        seconds >= stillSavingDelay
    }

    /// This step's share of the ring right now. Skipped steps are 0.
    public func slice(_ step: SaveStep) -> Double {
        slices[step, default: 0]
    }

    public var step: SaveStep { current }

    /// `ready` is the manifest with audio, or a real save error. That is the only 1.
    public func displayedFraction(ready: Bool) -> Double {
        if ready { return 1 }
        return min(worked, Self.waitingCap)
    }

    /// Move to a step. A later step drops whatever is left of the ones before it,
    /// so skipping cleaning does not add that slice. A smaller fraction does not rewind.
    public func updating(_ step: SaveStep, fraction newFraction: Double) -> SaveProgress {
        var copy = self
        let clamped = min(1, max(0, newFraction.isFinite ? newFraction : 0))
        guard let target = SaveStep.allCases.firstIndex(of: step),
              let now = SaveStep.allCases.firstIndex(of: copy.current)
        else { return copy }
        if target < now { return copy }
        while copy.current != step {
            let before = copy.current
            copy.dropRemainderOfCurrent()
            if copy.current == before { break }
        }
        copy.fraction = max(copy.fraction, clamped)
        return copy
    }

    /// Share of the ring already earned. Steps after the current one are not included.
    private var worked: Double {
        var value = 0.0
        for step in SaveStep.allCases {
            let slice = slices[step, default: 0]
            if step == current {
                value += slice * min(1, max(0, fraction))
                return value
            }
            value += slice
        }
        return value
    }

    /// Keep the part of this step already shown. Give the rest to the later steps.
    private mutating func dropRemainderOfCurrent() {
        guard let index = SaveStep.allCases.firstIndex(of: current) else { return }
        let held = min(1, max(0, fraction))
        let original = slices[current, default: 0]
        let used = original * held
        let unused = original - used
        slices[current] = used
        let later = SaveStep.allCases.suffix(from: SaveStep.allCases.index(after: index))
        let laterSum = later.reduce(0.0) { $0 + slices[$1, default: 0] }
        if unused > 0, laterSum > 0 {
            for step in later {
                let share = slices[step, default: 0] / laterSum
                slices[step, default: 0] += unused * share
            }
        }
        if let next = later.first {
            current = next
            fraction = 0
        } else {
            fraction = 1
        }
    }
}

/// Called from the save as each step moves. `fraction` is 0...1 inside that step.
public typealias SaveProgressHandler = @Sendable (SaveStep, Double) -> Void
