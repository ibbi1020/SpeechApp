import Testing
@testable import SpeechAppKit

@Suite("Entry greeting")
struct EntryGreetingTests {
    @Test("a first-ever open says First words")
    func firstRun() {
        #expect(EntryGreeting.line(hasBegunBefore: false) == "First words")
    }

    @Test("every open after the first session says Once more")
    func returning() {
        #expect(EntryGreeting.line(hasBegunBefore: true) == "Once more")
    }

    @Test("both lines are two words")
    func twoWords() {
        for line in [EntryGreeting.line(hasBegunBefore: false), EntryGreeting.line(hasBegunBefore: true)] {
            #expect(line.split(separator: " ").count == 2)
        }
    }
}

@Suite("Hold to begin")
struct HoldToBeginTests {
    @Test("an untouched hold is at zero")
    func start() {
        #expect(HoldToBegin().fraction(elapsed: 0) == 0)
        #expect(HoldToBegin().isComplete(elapsed: 0) == false)
    }

    @Test("halfway through the duration is half filled")
    func midway() {
        let hold = HoldToBegin(duration: 1.25)
        #expect(hold.fraction(elapsed: 0.625) == 0.5)
        #expect(hold.isComplete(elapsed: 0.625) == false)
    }

    @Test("the fraction clamps at one and never overshoots")
    func clamped() {
        let hold = HoldToBegin(duration: 1.25)
        #expect(hold.fraction(elapsed: 5) == 1)
        #expect(hold.fraction(elapsed: -3) == 0)
    }

    @Test("completion lands exactly at the duration")
    func completes() {
        let hold = HoldToBegin(duration: 1.25)
        #expect(hold.isComplete(elapsed: 1.25))
        #expect(hold.isComplete(elapsed: 1.2499) == false)
    }

    @Test("a zero duration completes immediately instead of dividing by zero")
    func zeroDuration() {
        let hold = HoldToBegin(duration: 0)
        #expect(hold.fraction(elapsed: 0) == 1)
        #expect(hold.isComplete(elapsed: 0))
    }
}

@Suite("Practice formats")
struct PracticeFormatTests {
    @Test("the pager carries reading, monologue and conversation in that order")
    func order() {
        #expect(PracticeFormat.all.map(\.kind) == [.reading, .monologue, .conversation])
    }

    @Test("every format has a heading, a line and a plate")
    func copyPresent() {
        for format in PracticeFormat.all {
            #expect(format.title.isEmpty == false)
            #expect(format.line.isEmpty == false)
            #expect(format.plateName.isEmpty == false)
        }
    }

    @Test("reading sends the user to the passage library")
    func reading() {
        let control = PracticeFormat.startControl(
            for: .reading,
            budget: ConversationBudgetSnapshot(limit: 20, used: 20, month: "2026-10")
        )
        #expect(control.title == "Choose a passage")
        #expect(control.isEnabled)
        #expect(control.note == nil)
    }

    @Test("monologue never depends on the conversation budget")
    func monologue() {
        let control = PracticeFormat.startControl(
            for: .monologue,
            budget: ConversationBudgetSnapshot(limit: 20, used: 20, month: "2026-10")
        )
        #expect(control.title == "Begin a talk")
        #expect(control.isEnabled)
        #expect(control.note == nil)
    }

    @Test("conversation names what it has left instead of going dim")
    func conversationWithBudget() {
        let control = PracticeFormat.startControl(
            for: .conversation,
            budget: ConversationBudgetSnapshot(limit: 20, used: 3, month: "2026-10")
        )
        #expect(control.title == "Begin rehearsal")
        #expect(control.isEnabled)
        #expect(control.note == "3 of 20 this month")
    }

    @Test("a spent month says so in words on the button")
    func conversationSpent() {
        let control = PracticeFormat.startControl(
            for: .conversation,
            budget: ConversationBudgetSnapshot(limit: 20, used: 20, month: "2026-10")
        )
        #expect(control.title == "Back next month")
        #expect(control.isEnabled == false)
        #expect(control.note == "20 of 20 this month")
    }
}
