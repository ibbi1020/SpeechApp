import Foundation
import Testing
@testable import SpeechAppKit

@Suite("Visible feedback")
struct VisibleFeedbackTests {
    @Test("nothing nearby shows no note")
    func nothingNearby() {
        let pause = note(start: 10, text: "A pause")
        let choice = VisibleFeedback.marker(
            at: 0,
            among: [pause],
            previouslyInside: [],
            showing: nil
        )
        #expect(choice.marker == nil)
        #expect(choice.inside.isEmpty)
    }

    @Test("a note shows from two seconds before its marker through two seconds after")
    func insideTheWindow() {
        let pause = note(start: 10, text: "A pause")
        for time in [8.0, 10.0, 12.0] {
            let choice = VisibleFeedback.marker(
                at: time,
                among: [pause],
                previouslyInside: [],
                showing: nil
            )
            #expect(choice.marker == pause)
            #expect(choice.inside == [pause.id])
        }
    }

    @Test("a note hides just outside the two second window")
    func justOutside() {
        let pause = note(start: 10, text: "A pause")
        for time in [7.999, 12.001] {
            let choice = VisibleFeedback.marker(
                at: time,
                among: [pause],
                previouslyInside: [pause.id],
                showing: pause.id
            )
            #expect(choice.marker == nil)
            #expect(choice.inside.isEmpty)
        }
    }

    @Test("moving forward, the note that was just entered wins the overlap")
    func forwardOverlap() {
        let pause = note(start: 4, text: "A pause")
        let fillers = note(start: 6, text: "Two fillers", kind: .fillerCluster)
        let markers = [pause, fillers]

        let enteredPause = VisibleFeedback.marker(
            at: 2,
            among: markers,
            previouslyInside: [],
            showing: nil
        )
        #expect(enteredPause.marker == pause)

        let overlap = VisibleFeedback.marker(
            at: 4,
            among: markers,
            previouslyInside: enteredPause.inside,
            showing: enteredPause.marker?.id
        )
        #expect(overlap.marker == fillers)

        let afterPause = VisibleFeedback.marker(
            at: 7,
            among: markers,
            previouslyInside: overlap.inside,
            showing: overlap.marker?.id
        )
        #expect(afterPause.marker == fillers)
    }

    @Test("moving backward, the note that was just entered wins the overlap")
    func backwardOverlap() {
        let pause = note(start: 4, text: "A pause")
        let fillers = note(start: 6, text: "Two fillers", kind: .fillerCluster)
        let markers = [pause, fillers]

        let enteredFillers = VisibleFeedback.marker(
            at: 8,
            among: markers,
            previouslyInside: [],
            showing: nil
        )
        #expect(enteredFillers.marker == fillers)

        let overlap = VisibleFeedback.marker(
            at: 6,
            among: markers,
            previouslyInside: enteredFillers.inside,
            showing: enteredFillers.marker?.id
        )
        #expect(overlap.marker == pause)

        let afterFillers = VisibleFeedback.marker(
            at: 3,
            among: markers,
            previouslyInside: overlap.inside,
            showing: overlap.marker?.id
        )
        #expect(afterFillers.marker == pause)
    }

    @Test("a jump into an overlap shows the later marker")
    func jumpTie() {
        let pause = note(start: 4, text: "A pause")
        let fillers = note(start: 6, text: "Two fillers", kind: .fillerCluster)
        let choice = VisibleFeedback.marker(
            at: 5,
            among: [pause, fillers],
            previouslyInside: [],
            showing: nil
        )
        #expect(choice.marker == fillers)
    }

    @Test("an empty note is never shown")
    func emptyNoteSkipped() {
        let blank = note(start: 4, text: "")
        let choice = VisibleFeedback.marker(
            at: 4,
            among: [blank],
            previouslyInside: [],
            showing: nil
        )
        #expect(choice.marker == nil)
        #expect(choice.inside.isEmpty)
    }

    @Test("a tapped marker wins while the playhead is inside its window")
    func preferredTapWins() {
        let pause = note(start: 4, text: "A pause")
        let fillers = note(start: 6, text: "Two fillers", kind: .fillerCluster)
        let markers = [pause, fillers]
        let tapped = VisibleFeedback.marker(
            at: 5,
            among: markers,
            previouslyInside: [],
            showing: nil,
            preferred: pause.id
        )
        #expect(tapped.marker == pause)

        let left = VisibleFeedback.marker(
            at: 7,
            among: markers,
            previouslyInside: tapped.inside,
            showing: pause.id,
            preferred: pause.id
        )
        #expect(left.marker == fillers)
    }

    @Test("leaving the window clears the note")
    func leavingClears() {
        let pause = note(start: 4, text: "A pause")
        let shown = VisibleFeedback.marker(
            at: 4,
            among: [pause],
            previouslyInside: [],
            showing: nil
        )
        #expect(shown.marker == pause)

        let gone = VisibleFeedback.marker(
            at: 6.001,
            among: [pause],
            previouslyInside: shown.inside,
            showing: shown.marker?.id
        )
        #expect(gone.marker == nil)
        #expect(gone.inside.isEmpty)
    }
}

private func note(start: TimeInterval, text: String, kind: ReviewMarker.Kind = .pause) -> ReviewMarker {
    ReviewMarker(kind: kind, start: start, end: start, score: 1, note: text)
}
