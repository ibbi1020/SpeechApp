import Testing
@testable import SpeechAppKit

struct ConversationFloorTests {
    @Test("interruptHeard gives the floor to the user without a turn")
    func interruptHeardOwnsOrb() {
        var floor = ConversationFloor()
        #expect(floor.owner == .partner)
        floor.apply(.interruptHeard)
        #expect(floor.owner == .user)
        floor.apply(.interruptDropped)
        #expect(floor.owner == .partner)
    }

    @Test("speechStarted keeps the floor on the user until speechStopped")
    func speechStartedOwnsUntilStop() {
        var floor = ConversationFloor()
        floor.apply(.speechStarted)
        #expect(floor.owner == .user)
        floor.apply(.audioDelta)
        #expect(floor.owner == .user)
        floor.apply(.speechStopped)
        #expect(floor.owner == .partner)
    }

    @Test("partner audio during a held barge-in does not reclaim the floor")
    func audioDeltaDoesNotStealHeldFloor() {
        var floor = ConversationFloor()
        floor.apply(.interruptHeard)
        floor.apply(.audioDelta)
        #expect(floor.owner == .user)
    }

    @Test("partnerCaption does not move the floor")
    func captionLeavesFloor() {
        var floor = ConversationFloor(owner: .user)
        floor.apply(.partnerCaption("Hello"))
        #expect(floor.owner == .user)
    }
}
