import Testing
@testable import SpeechAppKit

struct ConversationAudioLevelsTests {
    @Test("input reads local mic and skips remote tracks")
    func inputIgnoresRemote() {
        let stats: [ConversationAudioStat] = [
            .init(type: "media-source", kind: "audio", audioLevel: 0.4),
            .init(type: "track", kind: "audio", remoteSource: true, audioLevel: 0.9),
            .init(type: "track", kind: "audio", remoteSource: false, audioLevel: 0.2),
        ]
        #expect(ConversationAudioLevels.input(from: stats) == 0.4)
    }

    @Test("output reads inbound-rtp and remote tracks, not the mic")
    func outputReadsPlayback() {
        let stats: [ConversationAudioStat] = [
            .init(type: "media-source", kind: "audio", audioLevel: 0.8),
            .init(type: "inbound-rtp", kind: "audio", audioLevel: 0.35),
            .init(type: "track", kind: "audio", remoteSource: true, audioLevel: 0.5),
        ]
        #expect(ConversationAudioLevels.output(from: stats) == 0.5)
    }

    @Test("output is zero when only the mic is present")
    func outputZeroWithoutPlayback() {
        let stats: [ConversationAudioStat] = [
            .init(type: "media-source", kind: "audio", audioLevel: 0.6),
            .init(type: "track", kind: "audio", remoteSource: false, audioLevel: 0.4),
        ]
        #expect(ConversationAudioLevels.output(from: stats) == 0)
    }
}
