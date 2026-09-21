import Testing
@testable import SpeechAppKit

@Suite("Conversation report floor")
struct ConversationReportTests {
    @Test("under 45s or under 3 turns is thin")
    func thin() {
        let a = ConversationReportBuilder.build(
            userSpeechSeconds: 40, userTurns: 10, endReason: .userStop
        )
        #expect(a.kind == .thin)
        let b = ConversationReportBuilder.build(
            userSpeechSeconds: 120, userTurns: 2, endReason: .wrap
        )
        #expect(b.kind == .thin)
        #expect(a.lines.count == 2) // time + turns only
    }

    @Test("45s and 3 turns is full")
    func full() {
        let r = ConversationReportBuilder.build(
            userSpeechSeconds: 45, userTurns: 3, endReason: .wrap
        )
        #expect(r.kind == .full)
    }

    @Test("crisis is not a fluency report")
    func crisis() {
        let r = ConversationReportBuilder.build(
            userSpeechSeconds: 200, userTurns: 10, endReason: .crisisReferral
        )
        #expect(r.kind == .crisis)
        #expect(!r.lines.contains(where: { $0.label == "Pace" }))
    }
}
