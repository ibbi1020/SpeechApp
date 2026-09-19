import Testing
@testable import SpeechAppKit

@Suite("TokenAligner")
struct TokenAlignerTests {
    private func words(_ surfaces: [String]) -> [ScriptWord] {
        surfaces.enumerated().map { index, surface in
            ScriptWord(id: "w\(index)", surface: surface)
        }
    }

    private func spoken(_ text: String) -> SpokenToken {
        SpokenToken(surface: text, isFinal: true)
    }

    @Test("exact match advances cursor")
    func exactMatch() {
        let aligner = TokenAligner(script: words(["the", "quick", "fox"]))
        let events = aligner.ingest(spoken("the"))
        #expect(events.map(\.op) == [.match])
        #expect(aligner.scriptCursor == 1)
        #expect(aligner.currentWordID == "w1")
    }

    @Test("skip-script when spoken word appears ahead in lookahead")
    func skipScript() {
        let aligner = TokenAligner(script: words(["the", "quick", "fox"]), lookahead: 4)
        let events = aligner.ingest(spoken("quick"))
        #expect(events.map(\.op) == [.skipScript, .match])
        #expect(events[0].scriptWordID == "w0")
        #expect(aligner.scriptCursor == 2)
    }

    @Test("common word the must not false-skip ahead")
    func noFalseSkipOnFunctionWord() {
        let aligner = TokenAligner(
            script: words(["want", "fresh", "bread", "from", "the", "store"]),
            lookahead: 6
        )
        // User is on "want"; ASR hallucinates/re-emits "the" from later in the line.
        let events = aligner.ingest(spoken("the"))
        #expect(events.map(\.op) == [.insertSpoken])
        #expect(aligner.scriptCursor == 0)
        #expect(aligner.skippedWordIDs.isEmpty)
    }

    @Test("ambiguous repeated content word must not skip")
    func noSkipWhenContentWordRepeatsInWindow() {
        let aligner = TokenAligner(
            script: words(["see", "light", "and", "light", "again"]),
            lookahead: 4
        )
        let events = aligner.ingest(spoken("light"))
        // Two "light"s in lookahead → refuse skip (would guess wrong).
        #expect(events.map(\.op) == [.insertSpoken])
        #expect(aligner.scriptCursor == 0)
    }

    @Test("volatile preview does not jump on function words")
    func volatileNoJumpOnThe() {
        let aligner = TokenAligner(
            script: words(["want", "fresh", "bread", "the", "end"]),
            lookahead: 6
        )
        let preview = aligner.previewVolatile(surfaces: ["the"])
        #expect(preview.provisionalMatchedIDs.isEmpty)
        #expect(preview.provisionalSkippedIDs.isEmpty)
        #expect(preview.currentWordID == "w0")
    }

    @Test("insert-spoken after script is exhausted")
    func insertSpoken() {
        let aligner = TokenAligner(script: words(["hi"]))
        _ = aligner.ingest(spoken("hi"))
        let events = aligner.ingest(spoken("there"))
        #expect(events.map(\.op) == [.insertSpoken])
        #expect(events[0].spokenSurface == "there")
    }

    @Test("unknown spoken word is extra and does not steal the script word")
    func holdOnUnknownSpoken() {
        let aligner = TokenAligner(script: words(["dog", "ran", "home"]), lookahead: 2)
        let events = aligner.ingest(spoken("cat"))
        #expect(events.map(\.op) == [.insertSpoken])
        #expect(events[0].spokenSurface == "cat")
        #expect(aligner.scriptCursor == 0)
        #expect(aligner.currentWordID == "w0")
    }

    @Test("repeat of previous matched word")
    func repeatWord() {
        let aligner = TokenAligner(script: words(["go", "home"]))
        _ = aligner.ingest(spoken("go"))
        let events = aligner.ingest(spoken("go"))
        #expect(events.map(\.op) == [.repeat])
    }

    @Test("finish marks remaining script as skips")
    func finishSkipsRemainder() {
        let aligner = TokenAligner(script: words(["a", "b", "c"]))
        _ = aligner.ingest(spoken("a"))
        let events = aligner.finish()
        #expect(events.map(\.op) == [.skipScript, .skipScript])
        #expect(aligner.scriptCursor == 3)
    }

    @Test("liveMarks maps skip/extra/substitute only")
    func liveMarks() {
        let aligner = TokenAligner(script: words(["one", "two"]))
        _ = aligner.ingest(spoken("two")) // skip "one", match "two"
        _ = aligner.ingest(spoken("extra"))
        let marks = aligner.liveMarks()
        #expect(marks.map(\.kind) == [.skip, .extra])
    }

    @Test("normalization ignores case and punctuation")
    func normalization() {
        let aligner = TokenAligner(script: words(["Hello,"]))
        let events = aligner.ingest(spoken("hello"))
        #expect(events.map(\.op) == [.match])
    }

    @Test("soft script match treats near-miss ASR as occupancy match")
    func softScriptMatch() {
        let aligner = TokenAligner(
            script: words(["three", "birds"]),
            configuration: .init(softScriptMatch: true)
        )
        // Accented "three" often heard as "tree" by dictation ASR
        let events = aligner.ingest(spoken("tree"))
        #expect(events.map(\.op) == [.match])
        #expect(aligner.scriptCursor == 1)
        #expect(aligner.currentWordID == "w1")
    }

    @Test("soft script match accepts stem truncations")
    func softScriptMatchStem() {
        let aligner = TokenAligner(
            script: words(["running", "fast"]),
            configuration: .init(softScriptMatch: true)
        )
        let events = aligner.ingest(spoken("runnin"))
        #expect(events.map(\.op) == [.match])
    }

    @Test("soft script match does not collapse unrelated words")
    func softScriptMatchRejectsDistant() {
        let aligner = TokenAligner(
            script: words(["dog", "ran"]),
            configuration: .init(softScriptMatch: true)
        )
        let events = aligner.ingest(spoken("cat"))
        #expect(events.map(\.op) == [.insertSpoken])
        #expect(aligner.scriptCursor == 0)
    }

    @Test("volatile preview jumps ahead and reports provisional skips")
    func volatilePreviewKeepGoingJump() {
        let aligner = TokenAligner(script: words(["the", "quick", "brown", "fox"]), lookahead: 6)
        let preview = aligner.previewVolatile(surfaces: ["brown"])
        #expect(preview.provisionalMatchedIDs == ["w2"])
        #expect(preview.provisionalSkippedIDs == ["w0", "w1"])
        #expect(preview.currentWordID == "w3")
    }

    @Test("volatile preview advances cursor without committing events")
    func volatilePreview() {
        let aligner = TokenAligner(script: words(["the", "quick", "fox"]))
        let preview = aligner.previewVolatile(surfaces: ["the", "quick"])
        #expect(preview.currentWordID == "w2")
        #expect(preview.provisionalMatchedIDs == ["w0", "w1"])
        #expect(aligner.scriptCursor == 0)
        #expect(aligner.events.isEmpty)
    }

    @Test("volatile preview does not paint skips on mismatch")
    func volatilePreviewStaysOnMismatch() {
        let aligner = TokenAligner(script: words(["the", "quick", "fox"]))
        _ = aligner.ingest(spoken("the"))
        let preview = aligner.previewVolatile(surfaces: ["the", "zzzz"])
        #expect(preview.currentWordID == "w1")
        #expect(preview.provisionalMatchedIDs.isEmpty)
        #expect(aligner.events.map(\.op) == [.match])
    }

    @Test("commit provisional matches advances cursor like finals")
    func commitProvisional() {
        let aligner = TokenAligner(script: words(["the", "quick", "fox"]))
        let preview = aligner.previewVolatile(surfaces: ["the", "quick"])
        #expect(preview.provisionalMatchedIDs == ["w0", "w1"])
        let events = aligner.commitProvisionalMatches(preview.provisionalMatchedIDs)
        #expect(events.map(\.op) == [.match, .match])
        #expect(aligner.scriptCursor == 2)
        #expect(aligner.finish().map(\.op) == [.skipScript])
    }

    @Test("monotonic caret never moves backward")
    func monotonicCaret() {
        let aligner = TokenAligner(script: words(["the", "quick", "fox"]))
        _ = aligner.ingest(spoken("the"))
        #expect(aligner.monotonicWordID(proposing: "w0") == "w1")
        #expect(aligner.monotonicWordID(proposing: "w2") == "w2")
    }

    @Test("skip-script ids are the missed words")
    func skipScriptIDs() {
        let aligner = TokenAligner(script: words(["the", "quick", "fox"]), lookahead: 4)
        _ = aligner.ingest(spoken("quick"))
        #expect(aligner.skippedWordIDs == ["w0"])
    }

    @Test("bestScriptAlternative prefers the alt that matches next script words")
    func bestScriptAlternative() {
        let aligner = TokenAligner(script: words(["the", "quick", "fox"]))
        let chosen = aligner.bestScriptAlternative(
            candidates: [
                ["a", "slow", "dog"],
                ["the", "quick", "fox"],
                ["the", "quick", "cat"],
            ]
        )
        #expect(chosen == ["the", "quick", "fox"])
    }

    @Test("sliding contextual phrases prefer upcoming unigrams")
    func slidingContextualPhrases() {
        let surfaces = (0..<60).map { "word\($0)" }
        let words = surfaces.enumerated().map { ScriptWord(id: "w\($0)", surface: $1) }
        let passage = Passage(id: "p", title: "P", words: words)
        let phrases = ReadingSession.contextualPhrases(for: passage, fromIndex: 0, limit: 40)
        #expect(phrases.count <= 100)
        #expect(phrases.contains("word0"))
        #expect(phrases.contains("word39"))
        #expect(!phrases.contains("word0 word1 word2"))
    }

    @Test("commitHeardTrail promotes sticky-heard words at the cursor")
    func commitHeardTrail() {
        let aligner = TokenAligner(script: words(["the", "quick", "fox", "jumps"]))
        _ = aligner.ingest(spoken("the"))
        // Simulate sticky heard of next two without finals.
        let events = aligner.commitHeardTrail(Set(["w1", "w2"]))
        #expect(events.map(\.op) == [.match, .match])
        #expect(aligner.scriptCursor == 3)
        #expect(aligner.currentWordID == "w3")
    }

    @Test("soft match does not collapse ship and sheep")
    func shipSheepNotSoft() {
        #expect(TokenAligner.isSoftMatch("ship", "sheep") == false)
        #expect(TokenAligner.isSoftMatch("sheep", "ship") == false)
        let aligner = TokenAligner(
            script: words(["ship", "then"]),
            configuration: .init(softScriptMatch: true)
        )
        let events = aligner.ingest(spoken("sheep"))
        #expect(events.map(\.op) == [.insertSpoken])
        #expect(aligner.scriptCursor == 0)
    }
}
