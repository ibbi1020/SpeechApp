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

    @Test("catch-up over omitted words fills occupancy instead of skip-script")
    func catchUpIsOccupancyFill() {
        // Apple finals often drop "vivid waves with" then emit "very" — that is
        // ASR omission, not a user skip (session 2026-09-20T18-32-08Z).
        let aligner = TokenAligner(
            script: words(["the", "vivid", "waves", "with", "very", "wide"]),
            lookahead: 4
        )
        let events = aligner.ingest(spoken("very"))
        #expect(events.map(\.op) == [.match, .match, .match, .match, .match])
        #expect(events.map(\.scriptSurface) == ["the", "vivid", "waves", "with", "very"])
        #expect(aligner.skippedWordIDs.isEmpty)
        #expect(aligner.scriptCursor == 5)
    }

    @Test("single-letter contrast targets do not skip-script the lead-in")
    func vwContrastCatchUp() {
        let aligner = TokenAligner(
            script: words(["Keep", "v", "and", "w", "distinct"]),
            lookahead: 4
        )
        let events = aligner.ingest(spoken("w"))
        #expect(events.filter { $0.op == .skipScript }.isEmpty)
        #expect(events.filter { $0.op == .match }.count == 4)
        #expect(aligner.scriptCursor == 4)
        #expect(aligner.currentWordID == "w4")
    }

    @Test("Park Bench whole/scene catch-up does not skip-script")
    func parkBenchWholeScene() {
        // session-2026-09-20T19-08-46Z: finals jumped whole -> scene.
        let aligner = TokenAligner(
            script: words(["Read", "the", "whole", "scene", "once"]),
            lookahead: 6
        )
        _ = aligner.ingest(spoken("Read"))
        _ = aligner.ingest(spoken("the"))
        let events = aligner.ingest(spoken("scene"))
        #expect(events.filter { $0.op == .skipScript }.isEmpty)
        #expect(events.map(\.scriptSurface) == ["whole", "scene"])
        #expect(aligner.skippedWordIDs.isEmpty)
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
        _ = aligner.ingest(spoken("two")) // catch-up fills "one", match "two"
        _ = aligner.ingest(spoken("extra"))
        let marks = aligner.liveMarks()
        #expect(marks.map(\.kind) == [.extra])
        // Unread tail is still a skip mark after finish.
        _ = aligner.finish()
        #expect(aligner.liveMarks().map(\.kind) == [.extra])
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

    @Test("volatile catch-up marks omitted words as heard, not skipped")
    func volatileCatchUpHeard() {
        let aligner = TokenAligner(
            script: words(["the", "vivid", "waves", "with", "very"]),
            lookahead: 6
        )
        let preview = aligner.previewVolatile(surfaces: ["very"])
        #expect(preview.provisionalMatchedIDs == ["w0", "w1", "w2", "w3", "w4"])
        #expect(preview.provisionalSkippedIDs.isEmpty)
        #expect(preview.currentWordID == nil)
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

    @Test("unread tail after finish is still skip-script")
    func finishMarksUnreadAsSkip() {
        let aligner = TokenAligner(script: words(["the", "quick", "fox"]), lookahead: 4)
        _ = aligner.ingest(spoken("the"))
        let trailing = aligner.finish()
        #expect(trailing.map(\.op) == [.skipScript, .skipScript])
        #expect(aligner.skippedWordIDs == ["w1", "w2"])
    }

    @Test("bestScriptAlternative prefers the longer hypothesis over a short n-best")
    func prefersLongerHypothesis() {
        let aligner = TokenAligner(script: words(["we", "view", "the", "vivid", "waves"]))
        let chosen = aligner.bestScriptAlternative(
            candidates: [
                ["we"],
                ["wee"],
                ["we", "view", "the", "vivid", "waves"],
            ]
        )
        #expect(chosen == ["we", "view", "the", "vivid", "waves"])
    }

    @Test("cumulative hypothesis still occupies the tail after a prefix ASR miss")
    func resilientPrefixStripOccupiesTail() {
        // session-2026-09-20T19-17-46Z: caret stuck on "and" while volatiles
        // grew to 10 because exact prefix-strip failed on an earlier substitution.
        let aligner = TokenAligner(
            script: words(["Practice", "both", "the", "quiet", "th", "and", "the", "voiced", "th"]),
            lookahead: 8
        )
        for surface in ["Practice", "both", "the", "quiet", "th"] {
            _ = aligner.ingest(spoken(surface))
        }
        #expect(aligner.scriptCursor == 5)

        let preview = aligner.previewVolatile(surfaces: [
            "Practice", "both", "the", "quiet", "the", // ASR said "the" not "th"
            "and", "the", "voiced", "th",
        ])
        #expect(preview.provisionalMatchedIDs.contains("w5"))
        #expect(preview.provisionalMatchedIDs.contains("w7"))
        #expect(aligner.skippedWordIDs.isEmpty)
    }

    @Test("occupancySurfaces keeps raw text in the candidate set")
    func occupancySurfacesIncludesRawText() {
        let candidates = ReadingSession.occupancySurfaces(
            rawText: "we view the vivid waves",
            alternatives: [["we"], ["wee"]]
        )
        let aligner = TokenAligner(script: words(["we", "view", "the", "vivid", "waves"]))
        let chosen = aligner.bestScriptAlternative(candidates: candidates)
        #expect(chosen == ["we", "view", "the", "vivid", "waves"])
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
