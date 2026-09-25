import Foundation

/// Pure WebRTC-stat samples so mic vs partner playback levels can be tested
/// without linking WebRTC into SpeechAppKit.
public struct ConversationAudioStat: Sendable, Equatable {
    public var type: String
    public var kind: String?
    public var remoteSource: Bool?
    public var audioLevel: Float

    public init(
        type: String,
        kind: String? = nil,
        remoteSource: Bool? = nil,
        audioLevel: Float
    ) {
        self.type = type
        self.kind = kind
        self.remoteSource = remoteSource
        self.audioLevel = audioLevel
    }
}

public enum ConversationAudioLevels {
    /// Local mic: media-source / local track. Skips remote tracks.
    public static func input(from stats: [ConversationAudioStat]) -> Float {
        var level: Float = 0
        for stat in stats {
            guard isAudio(stat) else { continue }
            switch stat.type {
            case "media-source":
                level = max(level, stat.audioLevel)
            case "track":
                if stat.remoteSource == true { continue }
                level = max(level, stat.audioLevel)
            default:
                continue
            }
        }
        return level
    }

    /// Partner playback: inbound-rtp audio and remote tracks.
    public static func output(from stats: [ConversationAudioStat]) -> Float {
        var level: Float = 0
        for stat in stats {
            guard isAudio(stat) else { continue }
            switch stat.type {
            case "inbound-rtp":
                level = max(level, stat.audioLevel)
            case "track":
                if stat.remoteSource == true {
                    level = max(level, stat.audioLevel)
                }
            default:
                continue
            }
        }
        return level
    }

    private static func isAudio(_ stat: ConversationAudioStat) -> Bool {
        stat.kind == nil || stat.kind == "audio"
    }
}
