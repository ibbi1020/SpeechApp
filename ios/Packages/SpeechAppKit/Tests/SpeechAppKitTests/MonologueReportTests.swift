import Testing
@testable import SpeechAppKit

@Suite("Monologue report floor")
struct MonologueReportTests {
    @Test("one short take is thin")
    func thinOneStub() {
        let report = MonologueReportBuilder.build(
            takes: [
                MonologueTake(index: 1, wallSeconds: 8, ranges: [], transcript: "hi"),
            ],
            endReason: .leftEarly
        )
        #expect(report.kind == .thin)
        #expect(report.lines.contains(where: { $0.label == "Takes" }))
        #expect(!report.lines.contains(where: { $0.label == "Phonation-time ratio" }))
        #expect(!report.lines.contains(where: { $0.label == "Turns" }))
    }

    @Test("one 90s take under a 4 min ceiling is still thin (need two counting takes)")
    func leftoverStillNeedsTwo() {
        let report = MonologueReportBuilder.build(
            takes: [
                MonologueTake(
                    index: 1,
                    wallSeconds: 90,
                    ranges: [ConversationSpeechInterval(start: 0, end: 70)],
                    transcript: "I take the bus every morning and I like it"
                ),
            ],
            endReason: .leftEarly
        )
        #expect(report.kind == .thin)
    }

    @Test("two counting takes are a full profile")
    func fullTwo() {
        let t1 = MonologueTake(
            index: 1,
            wallSeconds: 90,
            ranges: [ConversationSpeechInterval(start: 0, end: 60)],
            transcript: "I take the bus to work every day"
        )
        let t3 = MonologueTake(
            index: 3,
            wallSeconds: 80,
            ranges: [
                ConversationSpeechInterval(start: 0, end: 50),
                ConversationSpeechInterval(start: 51, end: 70),
            ],
            transcript: "I take the bus to work every day still"
        )
        let report = MonologueReportBuilder.build(takes: [t1, t3], endReason: .completed)
        #expect(report.kind == .full)
        #expect(report.lines.contains(where: { $0.label == "Phonation-time ratio" }))
        #expect(report.lines.contains(where: { $0.label == "Pause time" }))
        #expect(report.lines.contains(where: { $0.label == "Silent gaps ≥250 ms" }))
        #expect(report.lines.contains(where: { $0.label.hasPrefix("Overlap") }))
        #expect(report.lines.contains(where: { $0.label == "Pace" && $0.value.contains("spelling") }))
        #expect(!report.lines.contains(where: { $0.value.contains("Grade") }))
        #expect(!report.comparison.isEmpty)
    }

    @Test("crisis is not a fluency report")
    func crisis() {
        let report = MonologueReportBuilder.build(
            takes: [
                MonologueTake(index: 1, wallSeconds: 90, ranges: [], transcript: "kill myself"),
            ],
            endReason: .crisisReferral
        )
        #expect(report.kind == .crisis)
        #expect(report.lines.isEmpty)
        #expect(report.comparison.isEmpty)
    }
}
