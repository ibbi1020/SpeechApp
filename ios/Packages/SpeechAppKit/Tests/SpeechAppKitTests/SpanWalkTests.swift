import Foundation
import Testing
@testable import SpeechAppKit

@Suite("SpanWalk")
struct SpanWalkTests {
    private let spanCount = 5
    private var syllableCounts: [Int: Int] {
        Dictionary(uniqueKeysWithValues: (0..<spanCount).map { ($0, 4) })
    }

    @Test("sustained speaking advances one span when duration elapses")
    func advancesOneSpan() {
        let state = SpanWalkState(currentSpanIndex: 0)
        let duration = SpanWalk.syllableDuration(syllableCount: 4)

        let (started, _) = SpanWalk.tick(
            state: state,
            speaking: true,
            now: 0,
            spanCount: spanCount,
            syllableCounts: syllableCounts,
            occupancySpanIndex: 0
        )
        #expect(started.currentSpanIndex == 0)
        #expect(started.spanProgress == 0)

        let (advanced, event) = SpanWalk.tick(
            state: started,
            speaking: true,
            now: duration,
            spanCount: spanCount,
            syllableCounts: syllableCounts,
            occupancySpanIndex: 0
        )
        #expect(advanced.currentSpanIndex == 1)
        #expect(event == .advanced(from: 0, to: 1))
    }

    @Test("cannot walk more than one span ahead of occupancy")
    func oneSpanAheadCap() {
        var state = SpanWalkState(currentSpanIndex: 0)
        var now: TimeInterval = 0
        let step = SpanWalk.syllableDuration(syllableCount: 4) + 0.05

        for _ in 0..<10 {
            let (next, _) = SpanWalk.tick(
                state: state,
                speaking: true,
                now: now,
                spanCount: spanCount,
                syllableCounts: syllableCounts,
                occupancySpanIndex: 0
            )
            state = next
            now += step
        }

        #expect(state.currentSpanIndex == SpanWalk.maxSpansAhead)
        #expect(state.spanProgress == 1)
    }

    @Test("occupancy catch-up snaps live index forward, never rewinds")
    func occupancySnapForward() {
        let state = SpanWalkState(currentSpanIndex: 1, spanProgress: 0.4)
        let (snapped, event) = SpanWalk.reconcile(
            state: state,
            occupancySpanIndex: 3,
            speaking: true,
            now: 10
        )
        #expect(snapped.currentSpanIndex == 3)
        #expect(snapped.spanProgress == 0)
        #expect(event == .snapped(to: 3))
    }

    @Test("occupancy behind live index leaves live ahead")
    func occupancyBehindLeavesLive() {
        let state = SpanWalkState(currentSpanIndex: 2, spanProgress: 0.5)
        let (next, event) = SpanWalk.reconcile(
            state: state,
            occupancySpanIndex: 0,
            speaking: true,
            now: 3
        )
        #expect(next.currentSpanIndex == 2)
        #expect(next.spanProgress == 0.5)
        #expect(event == nil)
    }

    @Test("silence decays fill but does not rewind span index")
    func silenceDoesNotRewind() {
        let state = SpanWalkState(
            currentSpanIndex: 2,
            spanProgress: 0.7,
            fillSpanIndex: 2,
            speechStartedAt: 1
        )
        let (afterSilence, event) = SpanWalk.tick(
            state: state,
            speaking: false,
            now: 5,
            spanCount: spanCount,
            syllableCounts: syllableCounts,
            occupancySpanIndex: 0
        )
        #expect(afterSilence.currentSpanIndex == 2)
        #expect(afterSilence.spanProgress < 0.7)
        #expect(event == nil)
    }

    @Test("passedSpans includes indices before current once occupancy touched them")
    func passedSpansFromOccupancy() {
        let passed = SpanWalk.passedSpanIndices(
            currentSpanIndex: 2,
            occupancySpanIndex: 1,
            spanCount: spanCount
        )
        #expect(passed == [0, 1])
    }
}
