import Testing
@testable import SpeechAppKit

@Suite("Review markers")
struct ReviewMarkersTests {
    @Test("cap formula")
    func cap() {
        #expect(ReviewMarkers.maxMarkers(durationSeconds: 60) == 3)
        #expect(ReviewMarkers.maxMarkers(durationSeconds: 120) == 4)
        #expect(ReviewMarkers.maxMarkers(durationSeconds: 180) == 5)
        #expect(ReviewMarkers.maxMarkers(durationSeconds: 240) == 6)
        #expect(ReviewMarkers.maxMarkers(durationSeconds: 540) == 7)
        #expect(ReviewMarkers.maxMarkers(durationSeconds: 0) == 0)
    }

    @Test("marks leading silence of 1.5s+ but not trailing")
    func leadingNotTrailing() {
        let words = [
            RecordedWord(surface: "Hello", start: 2.0, end: 2.3),
            RecordedWord(surface: "there", start: 2.4, end: 2.8),
        ]
        let markers = ReviewMarkers.build(words: words, durationSeconds: 10)
        #expect(markers.contains { $0.kind == .pause && $0.start == 0 && $0.score == 2.0 })
        #expect(!markers.contains { $0.start > 2.8 })
    }

    @Test("ignores silences under 1.5s")
    func shortGapIgnored() {
        let words = [
            RecordedWord(surface: "a", start: 0, end: 0.2),
            RecordedWord(surface: "b", start: 1.0, end: 1.2),
        ]
        let markers = ReviewMarkers.build(words: words, durationSeconds: 60)
        #expect(!markers.contains { $0.kind == .pause })
    }

    @Test("clusters two fillers within 6s")
    func fillerCluster() {
        let words = [
            RecordedWord(surface: "I", start: 0, end: 0.2),
            RecordedWord(surface: "um", start: 1.0, end: 1.2),
            RecordedWord(surface: "uh", start: 2.0, end: 2.2),
            RecordedWord(surface: "went", start: 3.0, end: 3.3),
        ]
        let markers = ReviewMarkers.build(words: words, durationSeconds: 60)
        let cluster = markers.first { $0.kind == .fillerCluster }
        #expect(cluster != nil)
        #expect(cluster?.note.contains("2 fillers") == true)
    }

    @Test("single filler is not a marker")
    func singleFiller() {
        let words = [
            RecordedWord(surface: "I", start: 0, end: 0.2),
            RecordedWord(surface: "um", start: 1.0, end: 1.2),
            RecordedWord(surface: "went", start: 2.0, end: 2.3),
        ]
        let markers = ReviewMarkers.build(words: words, durationSeconds: 60)
        #expect(!markers.contains { $0.kind == .fillerCluster })
    }

    @Test("ranks by score and respects spacing")
    func rankingAndSpacing() {
        // Four long pauses; on a 60s take cap=3 and spacing≈7.8s.
        let words = [
            RecordedWord(surface: "a", start: 0, end: 0.2),
            RecordedWord(surface: "b", start: 5.0, end: 5.2),   // 4.8s gap
            RecordedWord(surface: "c", start: 8.0, end: 8.2),   // 2.8s gap
            RecordedWord(surface: "d", start: 20.0, end: 20.2), // 11.8s gap
            RecordedWord(surface: "e", start: 40.0, end: 40.2), // 19.8s gap
        ]
        let markers = ReviewMarkers.build(words: words, durationSeconds: 60)
        #expect(markers.count <= 3)
        // Longest gap (19.8) should be present; short 2.8s gap near the 4.8s one should yield.
        #expect(markers.contains { abs($0.score - 19.8) < 0.01 })
        #expect(!markers.contains { abs($0.score - 2.8) < 0.01 })
        // Selected markers stay in time order for the scrubber.
        let starts = markers.map(\.start)
        #expect(starts == starts.sorted())
    }

    @Test("detects restart of two words")
    func restart() {
        let words = [
            RecordedWord(surface: "I", start: 0, end: 0.2),
            RecordedWord(surface: "went", start: 0.3, end: 0.5),
            RecordedWord(surface: "I", start: 0.7, end: 0.9),
            RecordedWord(surface: "went", start: 1.0, end: 1.2),
            RecordedWord(surface: "home", start: 1.3, end: 1.6),
        ]
        let markers = ReviewMarkers.build(words: words, durationSeconds: 60)
        #expect(markers.contains { $0.kind == .restart })
        #expect(markers.contains { $0.note.contains("started this part again") })
    }

    @Test("pause note uses the settled wording")
    func pauseCopy() {
        let note = ReviewMarkers.note(for: .pause, score: 4, end: 5, start: 1)
        #expect(note == "A 4-second pause. Listen: were you looking for a word, or your next point?")
    }
}
