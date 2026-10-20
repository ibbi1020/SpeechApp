import AVFoundation
import Foundation

/// A background the user picked for Conversation. Off is the default.
public enum AmbientPlace: String, CaseIterable, Sendable, Equatable {
    case off
    case quietRoom
    case trainStation
    case airport
    case beach
    case summerEvening
    case rain

    /// Bundled caf name. Off has no file.
    public var resourceName: String? {
        switch self {
        case .off: nil
        case .quietRoom: "ambient-quiet-room"
        case .trainStation: "ambient-train-station"
        case .airport: "ambient-airport"
        case .beach: "ambient-beach"
        case .summerEvening: "ambient-summer-evening"
        case .rain: "ambient-rain"
        }
    }

    public var title: String {
        switch self {
        case .off: "Off"
        case .quietRoom: "Quiet room"
        case .trainStation: "Train station"
        case .airport: "Airport"
        case .beach: "Beach"
        case .summerEvening: "Summer evening"
        case .rain: "Rain"
        }
    }
}

public enum AmbientCommand: Equatable, Sendable {
    case play(AmbientPlace)
    case stop
}

/// Why the bed might stop. Partner cancel is the one case that leaves it playing.
public enum AmbientStop: Equatable, Sendable {
    case partnerCancel
    case teardown
    case pause
    case userOff
}

/// When the bed is heard, and how loud, with no audio engine.
public enum AmbientBedPolicy {
    /// Linear gain on the bed node. About −22 dB under a partner node at 1.
    public static let linearGain: Float = 0.08

    public static func command(place: AmbientPlace, phase: ConversationPhase) -> AmbientCommand {
        guard place != .off else { return .stop }
        switch phase {
        case .talking, .wrapping:
            return .play(place)
        case .idle, .countdown, .connecting, .paused, .report, .crisis, .dropped:
            return .stop
        }
    }

    public static func gain(place: AmbientPlace) -> Float {
        place == .off ? 0 : linearGain
    }

    public static func keepsPlaying(after event: AmbientStop) -> Bool {
        event == .partnerCancel
    }
}

/// Collapses a burst of background picks into one player change.
/// Older requests must not stop or reschedule the bed.
public struct AmbientBedCoalescer: Equatable, Sendable {
    public private(set) var generation = 0
    public private(set) var place: AmbientPlace = .off
    public private(set) var playing = false
    public private(set) var scheduled: AmbientPlace?
    public private(set) var audible = false

    public init() {}

    /// Records the latest pick. Returns the generation that may touch the player.
    public mutating func request(place: AmbientPlace, playing: Bool) -> Int {
        generation += 1
        self.place = place
        self.playing = playing
        return generation
    }

    public func shouldApply(_ requested: Int) -> Bool {
        requested == generation
    }

    public enum Step: Equatable, Sendable {
        /// A newer pick already replaced this one. Do not touch the player.
        case skip
        case stop
        /// This place is already looping. Leave the node alone.
        case leave(AmbientPlace)
        case restart(AmbientPlace)
    }

    public func step(for requested: Int) -> Step {
        guard requested == generation else { return .skip }
        guard playing, place != .off else { return .stop }
        if audible, scheduled == place { return .leave(place) }
        return .restart(place)
    }

    public mutating func didStop() {
        audible = false
        scheduled = nil
    }

    /// Marks `place` looping only when `requested` is still the latest pick.
    public mutating func didStart(_ place: AmbientPlace, generation requested: Int) {
        guard requested == generation else { return }
        audible = true
        scheduled = place
    }
}

/// The place chosen on this phone. Missing or unknown values read as off.
public final class AmbientPreference: @unchecked Sendable {
    public static let storageKey = "conversation.ambientPlace"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var place: AmbientPlace {
        get {
            guard let raw = defaults.string(forKey: Self.storageKey),
                  let place = AmbientPlace(rawValue: raw)
            else { return .off }
            return place
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.storageKey)
        }
    }
}

/// The playback format the conversation engine already uses for the partner.
public enum AmbientLoopFormat {
    public static let sampleRate: Double = 24_000

    public static func matches(_ buffer: AVAudioPCMBuffer) -> Bool {
        let format = buffer.format
        return format.commonFormat == .pcmFormatFloat32
            && format.sampleRate == sampleRate
            && format.channelCount == 1
    }
}
