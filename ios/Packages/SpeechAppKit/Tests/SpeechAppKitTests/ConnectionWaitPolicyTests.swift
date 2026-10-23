import Foundation
import Testing
@testable import SpeechAppKit

struct ConnectionWaitPolicyTests {
    @Test("the slow line waits five seconds and a hang ends at ten")
    func thresholds() {
        #expect(ConnectionWaitPolicy.showsSlowLine(elapsed: 4.9) == false)
        #expect(ConnectionWaitPolicy.hasHung(elapsed: 4.9) == false)

        #expect(ConnectionWaitPolicy.showsSlowLine(elapsed: 5) == true)
        #expect(ConnectionWaitPolicy.hasHung(elapsed: 5) == false)

        #expect(ConnectionWaitPolicy.showsSlowLine(elapsed: 9.9) == true)
        #expect(ConnectionWaitPolicy.hasHung(elapsed: 9.9) == false)

        #expect(ConnectionWaitPolicy.showsSlowLine(elapsed: 10) == false)
        #expect(ConnectionWaitPolicy.hasHung(elapsed: 10) == true)
    }

    @Test("the line tells them the connection is slow")
    func sentence() {
        #expect(ConnectionWaitPolicy.slowLine == "Taking a bit longer than expected…")
    }

    @Test("time remaining shrinks from the hang limit and stops at zero")
    func remaining() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(ConnectionWaitPolicy.remaining(since: start, now: start) == 10)
        #expect(ConnectionWaitPolicy.remaining(since: start, now: start.addingTimeInterval(3)) == 7)
        #expect(ConnectionWaitPolicy.remaining(since: start, now: start.addingTimeInterval(10)) == 0)
        #expect(ConnectionWaitPolicy.remaining(since: start, now: start.addingTimeInterval(12)) == 0)
    }
}
