import Testing
@testable import SpeechAppKit

@Suite("Entry greeting")
struct EntryGreetingTests {
    @Test("a first-ever open says Find your voice")
    func firstRun() {
        #expect(EntryGreeting.line(hasBegunBefore: false) == "Find your voice")
    }

    @Test("every open after the first session says Speak with poise")
    func returning() {
        #expect(EntryGreeting.line(hasBegunBefore: true) == "Speak with poise")
    }

    @Test("both lines stay between two and three words")
    func shortLines() {
        for line in [EntryGreeting.line(hasBegunBefore: false), EntryGreeting.line(hasBegunBefore: true)] {
            #expect((2...3).contains(line.split(separator: " ").count))
        }
    }
}

@Suite("Practice formats")
struct PracticeFormatTests {
    @Test("the pager carries reading, monologue and conversation in that order")
    func order() {
        #expect(PracticeFormat.all.map(\.kind) == [.reading, .monologue, .conversation])
    }

    @Test("every format has a heading and a line")
    func copyPresent() {
        for format in PracticeFormat.all {
            #expect(format.title.isEmpty == false)
            #expect(format.line.isEmpty == false)
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

@Suite("Home sheets")
struct HomeSheetDragTests {
    @Test("a drag opens only past the point where Progress may cover Gallery")
    func openThreshold() {
        #expect(HomeSheetDrag.openThreshold == 0.62)
        #expect(HomeSheetDrag.commitsOpen(flickUp: false, flickDown: false, projected: 0.62) == false)
        #expect(HomeSheetDrag.commitsOpen(flickUp: false, flickDown: false, projected: 0.63))
        #expect(HomeSheetDrag.commitsOpen(flickUp: true, flickDown: false, projected: 0.1))
        #expect(HomeSheetDrag.commitsOpen(flickUp: false, flickDown: true, projected: 0.9) == false)
    }
}
