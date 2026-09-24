# Monologue v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a local 4/3/2 regimen: familiar topic, optional notes, three takes under 4/3/2 minute ceilings, then an honest named-index profile (or a thin report).

**Architecture:** SpeechAppKit owns the session brain (phase, clock, skip, takes, crisis keywords, extractors, report) and is fully testable on macOS with `ControllableTimeSource` — no mic, no OpenAI. The iOS App target owns SwiftUI plus Reading’s existing `MicAudioSource` + `LiveTranscriptionEngine` (user-only listen). Never start WebRTC / `LiveConversationMouth`. Never store PCM.

**Tech Stack:** Swift 6 / iOS 26, Swift Testing (`swift test` in SpeechAppKit), SpeechAppKit (no new SPM deps), App target SwiftUI. Reuse `ConversationTimeSource`, `ConversationSpeechMetrics`, `ConversationPauseTime`, `ConversationPace`, `CrisisGate`, `OpenPromptBank`, `SpeechChrome`, `AuroraPill`, `CrisisReferralView`.

**Spec:** `docs/superpowers/specs/2026-09-24-monologue-format-design.md`

---

## Do not build (v1)

If a task below does not name it, **do not add it**:

- OpenAI Realtime, WebRTC, `ConversationMouth`, mint, Conversation start budget
- 3-2-1 warmup, planning countdown, silence auto-pause, fill-to-zero quota
- Generated form / grammar / GOP / CEFR / letter / “Fluency 78” / improvement badge
- Filled-pause UI, pause *location*, lexical diversity-as-better, PREP / narrative-arc scoring
- Named listener, speaker embeddings, `PCMStore`, milestone snippets, `TokenAligner`
- “same talk” / “repeat” / “tell it again” copy
- A second Stop next to Done
- Daily cadence cap, 3/3/3 A/B, composer / topic picker beyond **Another topic**

---

## File map

New kit types live under `Monologue/` so Reading and Conversation stay untouched except two shared extractors (`ConversationPauseTime.count`, Home / AppModel / RootView).

| Path | Responsibility |
|---|---|
| `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Conversation/ConversationPauseTime.swift` | Add gap **count** on the same ≥250 ms gaps |
| `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Monologue/MonologuePhonation.swift` | PTR = spoken / wall |
| `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Monologue/MonologueOverlap.swift` | Jaccard token overlap % |
| `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Monologue/MonologuePhase.swift` | Phase, end reason, ceilings |
| `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Monologue/MonologueTake.swift` | One take’s wall, ranges, transcript |
| `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Monologue/MonologueReport.swift` | Thin / full / crisis builder |
| `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Monologue/MonologuePromptCursor.swift` | Assigned prompt + skip |
| `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Monologue/MonologuePromptStore.swift` | Last prompt persistence |
| `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Monologue/MonologueSession.swift` | The brain |
| `ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/Monologue*.swift` | Kit tests |
| `ios/App/Screens/HomeView.swift` | Three equal glass rows |
| `ios/App/AppModel.swift` | Routes + age-gate pending start |
| `ios/App/RootView.swift` | Monologue destination |
| `ios/App/Screens/MonologueSessionView.swift` | Planning / live / between / pause |
| `ios/App/Screens/MonologueReportView.swift` | Named-index profile |
| `ios/project.yml` | Mic / speech usage strings cover talking |

**Reuse:** `CrisisReferralView`, `MintClient.crisis()`, `ConversationRoutePause`, `AuroraPill` **listen only**, `SpeechPrimaryButtonStyle`, `OpenPromptBank` / `opens.json`.

**Never reuse for this format:** `LiveConversationMouth`, `FakeConversationMouth`, Conversation 1.5 min silence auto-pause, Reading 3-2-1, `PCMStore`.

**Test root:** `cd ios/Packages/SpeechAppKit`

---

## Slice A — session brain (`swift test`, no mic)

Do not open Xcode until Slice B.

### Task 1: Pause count on the existing ≥250 ms gaps

**Files:**
- Modify: `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Conversation/ConversationPauseTime.swift`
- Test: `ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/ConversationPauseTimeTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `ConversationPauseTimeTests.swift`:

```swift
    @Test("counts gaps of at least 250ms")
    func countsQualifyingGaps() {
        let count = ConversationPauseTime.count(from: [
            ConversationSpeechInterval(start: 0, end: 1),
            ConversationSpeechInterval(start: 1.125, end: 2),
            ConversationSpeechInterval(start: 2.5, end: 3),
        ])
        #expect(count == 2)
    }

    @Test("a single range has no pause count")
    func singleRangeCount() {
        let count = ConversationPauseTime.count(from: [
            ConversationSpeechInterval(start: 0, end: 4),
        ])
        #expect(count == 0)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ios/Packages/SpeechAppKit && swift test --filter ConversationPauseTimeTests`

Expected: FAIL — `count(from:)` not found.

- [ ] **Step 3: Write minimal implementation**

Add to `ConversationPauseTime`:

```swift
    public static func count(
        from ranges: [ConversationSpeechInterval],
        minimumGap: TimeInterval = minimumGap
    ) -> Int {
        let merged = ConversationSpeechMetrics.merged(ranges)
        guard merged.count >= 2 else { return 0 }
        var total = 0
        for index in 1..<merged.count {
            let gap = merged[index].start - merged[index - 1].end
            if gap >= minimumGap {
                total += 1
            }
        }
        return total
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ConversationPauseTimeTests`

Expected: PASS (old duration tests + new count tests).

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Conversation/ConversationPauseTime.swift \
  ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/ConversationPauseTimeTests.swift
git commit -m "$(cat <<'EOF'
feat: count silent gaps ≥250ms for Monologue pause frequency

EOF
)"
```

---

### Task 2: Phonation-time ratio

**Files:**
- Create: `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Monologue/MonologuePhonation.swift`
- Test: `ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/MonologuePhonationTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import SpeechAppKit

@Suite("Monologue phonation-time ratio")
struct MonologuePhonationTests {
    @Test("speech over wall is the ratio")
    func ratio() {
        let spoken = ConversationSpeechMetrics.unionDuration([
            ConversationSpeechInterval(start: 0, end: 6),
            ConversationSpeechInterval(start: 8, end: 10),
        ])
        #expect(MonologuePhonation.ratio(spoken: spoken, wall: 10) == 0.8)
    }

    @Test("zero wall is nil")
    func zeroWall() {
        #expect(MonologuePhonation.ratio(spoken: 4, wall: 0) == nil)
    }

    @Test("paused clock is already excluded from wall by the caller")
    func leftoverCeilingStillValid() {
        // 90s talk under a 240s ceiling still has a ratio.
        #expect(MonologuePhonation.ratio(spoken: 70, wall: 90) == 70.0 / 90.0)
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter MonologuePhonationTests`

Expected: FAIL — `MonologuePhonation` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Speech time / take-clock wall time (Towell; De Jong).
/// Caller must pass wall that already excludes Pause / system-interrupt freeze.
public enum MonologuePhonation {
    public static func ratio(spoken: TimeInterval, wall: TimeInterval) -> Double? {
        guard wall > 0 else { return nil }
        return spoken / wall
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter MonologuePhonationTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Monologue/MonologuePhonation.swift \
  ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/MonologuePhonationTests.swift
git commit -m "$(cat <<'EOF'
feat: add phonation-time ratio extractor for Monologue

EOF
)"
```

---

### Task 3: Take-to-take token overlap

**Files:**
- Create: `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Monologue/MonologueOverlap.swift`
- Test: `ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/MonologueOverlapTests.swift`

Jaccard on unique lowercase whitespace tokens. High overlap is expected, not a fail. Empty vs empty → `nil`.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import SpeechAppKit

@Suite("Monologue token overlap")
struct MonologueOverlapTests {
    @Test("identical wording is 100")
    func identical() {
        let percent = MonologueOverlap.tokenPercent(
            previous: "I take the bus to work",
            current: "I take the bus to work"
        )
        #expect(percent == 100)
    }

    @Test("disjoint wording is 0")
    func disjoint() {
        let percent = MonologueOverlap.tokenPercent(
            previous: "cats sleep",
            current: "dogs run"
        )
        #expect(percent == 0)
    }

    @Test("partial overlap is Jaccard on unique tokens")
    func partial() {
        // {a,b} vs {b,c} → 1/3
        let percent = MonologueOverlap.tokenPercent(previous: "a b", current: "b c")
        #expect(percent == 100.0 / 3.0)
    }

    @Test("empty pair is nil")
    func empty() {
        #expect(MonologueOverlap.tokenPercent(previous: "  ", current: "") == nil)
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter MonologueOverlapTests`

Expected: FAIL — type not found.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Token-set Jaccard × 100. Descriptive overlap, not originality.
public enum MonologueOverlap {
    public static func tokenPercent(previous: String, current: String) -> Double? {
        let a = Set(tokens(previous))
        let b = Set(tokens(current))
        if a.isEmpty && b.isEmpty { return nil }
        let union = a.union(b)
        guard !union.isEmpty else { return nil }
        return 100.0 * Double(a.intersection(b).count) / Double(union.count)
    }

    public static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .split { $0.isWhitespace || $0.isNewline }
            .map(String.init)
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter MonologueOverlapTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Monologue/MonologueOverlap.swift \
  ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/MonologueOverlapTests.swift
git commit -m "$(cat <<'EOF'
feat: add take-to-take token overlap for Monologue

EOF
)"
```

---

### Task 4: Phase, ceilings, take record

**Files:**
- Create: `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Monologue/MonologuePhase.swift`
- Create: `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Monologue/MonologueTake.swift`
- Test: `ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/MonologuePhaseTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import SpeechAppKit

@Suite("Monologue phase and ceilings")
struct MonologuePhaseTests {
    @Test("ceilings are 4 then 3 then 2 minutes")
    func ceilings() {
        #expect(MonologueCeiling.seconds(forTake: 1) == 240)
        #expect(MonologueCeiling.seconds(forTake: 2) == 180)
        #expect(MonologueCeiling.seconds(forTake: 3) == 120)
    }

    @Test("a take counts at 30s wall")
    func countingFloor() {
        let short = MonologueTake(
            index: 1,
            wallSeconds: 8,
            ranges: [],
            transcript: "hi"
        )
        let long = MonologueTake(
            index: 1,
            wallSeconds: 30,
            ranges: [ConversationSpeechInterval(start: 0, end: 20)],
            transcript: "hello there"
        )
        #expect(short.counts == false)
        #expect(long.counts == true)
    }

    @Test("crisis is not a fluency end")
    func crisisEnd() {
        #expect(MonologueEndReason.crisisReferral.showsReport == false)
        #expect(MonologueEndReason.completed.showsReport == true)
        #expect(MonologueEndReason.leftEarly.showsReport == true)
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter MonologuePhaseTests`

Expected: FAIL — types not found.

- [ ] **Step 3: Write minimal implementation**

`MonologuePhase.swift`:

```swift
import Foundation

public enum MonologuePhase: Equatable, Sendable {
    case planning, taking, paused, between, report, crisis
}

public enum MonologueEndReason: Equatable, Sendable {
    case completed, leftEarly, crisisReferral

    public var showsReport: Bool { self != .crisisReferral }
}

public enum MonologueCeiling {
    public static let all: [TimeInterval] = [240, 180, 120]

    public static func seconds(forTake take: Int) -> TimeInterval {
        all[take - 1]
    }
}
```

`MonologueTake.swift`:

```swift
import Foundation

public struct MonologueTake: Equatable, Sendable {
    public static let countingWall: TimeInterval = 30

    public let index: Int
    public let wallSeconds: TimeInterval
    public let ranges: [ConversationSpeechInterval]
    public let transcript: String

    public init(
        index: Int,
        wallSeconds: TimeInterval,
        ranges: [ConversationSpeechInterval],
        transcript: String
    ) {
        self.index = index
        self.wallSeconds = wallSeconds
        self.ranges = ranges
        self.transcript = transcript
    }

    public var counts: Bool { wallSeconds >= Self.countingWall }

    public var spokenSeconds: TimeInterval {
        ConversationSpeechMetrics.unionDuration(ranges)
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter MonologuePhaseTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Monologue/MonologuePhase.swift \
  ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Monologue/MonologueTake.swift \
  ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/MonologuePhaseTests.swift
git commit -m "$(cat <<'EOF'
feat: add Monologue phase, ceilings, and counting-take floor

EOF
)"
```

---

### Task 5: Report builder (thin / full / crisis)

**Files:**
- Create: `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Monologue/MonologueReport.swift`
- Test: `ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/MonologueReportTests.swift`

Rules from the spec:

- Crisis → `kind == .crisis`, no metric lines.
- Counting takes = `wallSeconds >= 30`.
- Full profile if **≥ 2 counting takes**: per counting take, time spoken, PTR, pause time, pause count; overlap vs previous counting take; optional pace when spoken > 0; one comparison sentence from **first vs last counting take** using actual deltas (never a score).
- Else thin: duration (sum of take walls) + take count only. No zeros for PTR / pauses / overlap / pace.

Pace value must include the spelling-syllable caveat. Pause count label is **Silent gaps ≥250 ms**. Never include Turns, GOP, Grade, Fluency.

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter MonologueReportTests`

Expected: FAIL — `MonologueReportBuilder` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public struct MonologueReport: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable { case thin, full, crisis }

    public struct Line: Equatable, Sendable {
        public let label: String
        public let value: String
        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
    }

    public let id: UUID
    public let kind: Kind
    public let endReason: MonologueEndReason
    public let takeCount: Int
    public let lines: [Line]
    public let comparison: String

    public init(
        id: UUID = UUID(),
        kind: Kind,
        endReason: MonologueEndReason,
        takeCount: Int,
        lines: [Line],
        comparison: String
    ) {
        self.id = id
        self.kind = kind
        self.endReason = endReason
        self.takeCount = takeCount
        self.lines = lines
        self.comparison = comparison
    }
}

public enum MonologueReportBuilder {
    public static func build(
        takes: [MonologueTake],
        endReason: MonologueEndReason
    ) -> MonologueReport {
        if endReason == .crisisReferral {
            return MonologueReport(
                kind: .crisis,
                endReason: endReason,
                takeCount: takes.count,
                lines: [],
                comparison: ""
            )
        }

        let counting = takes.filter(\.counts)
        if counting.count < 2 {
            let wall = takes.reduce(0.0) { $0 + $1.wallSeconds }
            return MonologueReport(
                kind: .thin,
                endReason: endReason,
                takeCount: takes.count,
                lines: [
                    MonologueReport.Line(label: "Time spoken", value: format(wall)),
                    MonologueReport.Line(label: "Takes", value: "\(takes.count)"),
                ],
                comparison: ""
            )
        }

        var lines: [MonologueReport.Line] = []
        var previous: MonologueTake?
        for take in counting {
            lines.append(MonologueReport.Line(label: "Take \(take.index)", value: format(take.wallSeconds)))
            let spoken = take.spokenSeconds
            if let ptr = MonologuePhonation.ratio(spoken: spoken, wall: take.wallSeconds) {
                lines.append(MonologueReport.Line(
                    label: "Phonation-time ratio",
                    value: String(format: "%.2f", ptr)
                ))
            }
            let pause = ConversationPauseTime.seconds(from: take.ranges)
            lines.append(MonologueReport.Line(label: "Pause time", value: String(format: "%.1fs", pause)))
            lines.append(MonologueReport.Line(
                label: "Silent gaps ≥250 ms",
                value: "\(ConversationPauseTime.count(from: take.ranges))"
            ))
            if let pace = ConversationPace.syllablesPerMinute(
                transcript: take.transcript,
                speechSeconds: spoken
            ) {
                lines.append(MonologueReport.Line(
                    label: "Pace",
                    value: String(format: "%.0f / min (spelling estimate)", pace)
                ))
            }
            if let previous,
               let overlap = MonologueOverlap.tokenPercent(
                previous: previous.transcript,
                current: take.transcript
               ) {
                lines.append(MonologueReport.Line(
                    label: "Overlap vs take \(previous.index)",
                    value: String(format: "%.0f%%", overlap)
                ))
            }
            previous = take
        }

        let first = counting.first!
        let last = counting.last!
        return MonologueReport(
            kind: .full,
            endReason: endReason,
            takeCount: takes.count,
            lines: lines,
            comparison: comparison(first: first, last: last)
        )
    }

    public static func comparison(first: MonologueTake, last: MonologueTake) -> String {
        let timeWord = last.spokenSeconds >= first.spokenSeconds ? "more" : "less"
        let firstGaps = ConversationPauseTime.count(from: first.ranges)
        let lastGaps = ConversationPauseTime.count(from: last.ranges)
        let gapWord = lastGaps <= firstGaps ? "fewer" : "more"
        return "Take \(last.index) vs take \(first.index): \(timeWord) talking time, \(gapWord) long gaps."
    }

    private static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return "\(s / 60)m \(s % 60)s"
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter MonologueReportTests`

Expected: PASS. If overlap/pace assertions are brittle, keep the labels and caveat; do not invent a composite.

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Monologue/MonologueReport.swift \
  ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/MonologueReportTests.swift
git commit -m "$(cat <<'EOF'
feat: build thin vs full Monologue profile with no composite grade

EOF
)"
```

---

### Task 6: Prompt cursor (assign + Another topic)

**Files:**
- Create: `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Monologue/MonologuePromptCursor.swift`
- Test: `ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/MonologuePromptCursorTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import SpeechAppKit

@Suite("Monologue prompt cursor")
struct MonologuePromptCursorTests {
    @Test("last prompt is reopened when it still exists")
    func reopenLast() {
        var cursor = MonologuePromptCursor(
            prompts: ["alpha", "bravo", "charlie"],
            lastPrompt: "bravo"
        )
        #expect(cursor.current == "bravo")
        cursor.skip()
        #expect(cursor.current == "charlie")
        cursor.skip()
        #expect(cursor.current == "alpha")
    }

    @Test("missing last prompt starts at the first item")
    func missingLast() {
        let cursor = MonologuePromptCursor(
            prompts: ["alpha", "bravo"],
            lastPrompt: "ghost"
        )
        #expect(cursor.current == "alpha")
    }

    @Test("bundled opens are a valid familiar bank")
    func bundled() throws {
        let bank = try OpenPromptBank.loadBundled()
        let cursor = MonologuePromptCursor(prompts: bank.prompts, lastPrompt: nil)
        #expect(!cursor.current.isEmpty)
        #expect(!cursor.current.lowercased().contains("suicide"))
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter MonologuePromptCursorTests`

Expected: FAIL

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public struct MonologuePromptCursor: Equatable, Sendable {
    public let prompts: [String]
    public private(set) var index: Int

    public init(prompts: [String], lastPrompt: String?) {
        precondition(!prompts.isEmpty, "prompt bank is empty")
        self.prompts = prompts
        if let lastPrompt, let found = prompts.firstIndex(of: lastPrompt) {
            self.index = found
        } else {
            self.index = 0
        }
    }

    public var current: String { prompts[index] }

    public mutating func skip() {
        index = (index + 1) % prompts.count
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter MonologuePromptCursorTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Monologue/MonologuePromptCursor.swift \
  ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/MonologuePromptCursorTests.swift
git commit -m "$(cat <<'EOF'
feat: cycle Monologue topics without a composer

EOF
)"
```

---

### Task 7: Last-prompt store

**Files:**
- Create: `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Monologue/MonologuePromptStore.swift`
- Test: `ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/MonologuePromptStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import SpeechAppKit

@Suite("Monologue last prompt")
struct MonologuePromptStoreTests {
    @Test("memory store round-trips")
    func memory() {
        let store = InMemoryMonologuePromptStore()
        #expect(store.lastPrompt == nil)
        store.lastPrompt = "How was your commute today?"
        #expect(store.lastPrompt == "How was your commute today?")
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter MonologuePromptStoreTests`

Expected: FAIL

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public protocol MonologuePromptStore: AnyObject, Sendable {
    var lastPrompt: String? { get set }
}

public final class InMemoryMonologuePromptStore: MonologuePromptStore, @unchecked Sendable {
    public var lastPrompt: String?
    public init(lastPrompt: String? = nil) {
        self.lastPrompt = lastPrompt
    }
}

public final class UserDefaultsMonologuePromptStore: MonologuePromptStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "monologue.lastPrompt"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var lastPrompt: String? {
        get { defaults.string(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter MonologuePromptStoreTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Monologue/MonologuePromptStore.swift \
  ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/MonologuePromptStoreTests.swift
git commit -m "$(cat <<'EOF'
feat: persist last Monologue topic for silent return

EOF
)"
```

---

### Task 8: Session — planning, ready, clock freeze

**Files:**
- Create: `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Monologue/MonologueSession.swift`
- Test: `ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/MonologueSessionTests.swift`

Session is `@MainActor` like `ConversationSession`. Clock uses `ConversationTimeSource`. **Silence does not auto-pause.** Pause freezes elapsed. Ready does **not** wait for a 3-2-1. Notes are writable in planning/between and ignored by the take snapshot (UI hides them).

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import SpeechAppKit

@Suite("Monologue session clock")
struct MonologueSessionClockTests {
    @MainActor
    @Test("I'm ready starts take 1 at 4:00 with no warmup")
    func readyStartsTake() {
        let time = ControllableTimeSource(now: 0)
        let session = MonologueSession(
            prompts: ["A familiar topic"],
            store: InMemoryMonologuePromptStore(),
            time: time
        )
        #expect(session.phase == .planning)
        #expect(session.takeNumber == 1)
        session.notes = "keyword outline"
        session.ready()
        #expect(session.phase == .taking)
        #expect(session.remaining == 240)
        #expect(session.store.lastPrompt == "A familiar topic")
        time.advance(10)
        #expect(session.elapsed == 10)
        #expect(session.remaining == 230)
    }

    @MainActor
    @Test("pause freezes the take clock")
    func pauseFreezes() {
        let time = ControllableTimeSource(now: 0)
        let session = makeSession(time: time)
        session.ready()
        time.advance(5)
        session.pause()
        #expect(session.phase == .paused)
        time.advance(30)
        #expect(session.elapsed == 5)
        session.resume()
        #expect(session.phase == .taking)
        time.advance(2)
        #expect(session.elapsed == 7)
    }

    @MainActor
    @Test("long silence does not auto-pause")
    func silenceStaysOnTape() async {
        let time = ControllableTimeSource(now: 0)
        let session = makeSession(time: time)
        session.ready()
        time.advance(90)
        await session.tick()
        #expect(session.phase == .taking)
        #expect(session.elapsed == 90)
    }

    @MainActor
    @Test("Another topic does not start a take")
    func skipStaysPlanning() {
        let session = MonologueSession(
            prompts: ["one", "two"],
            store: InMemoryMonologuePromptStore(),
            time: ControllableTimeSource()
        )
        session.skipTopic()
        #expect(session.prompt == "two")
        #expect(session.phase == .planning)
    }
}

@MainActor
private func makeSession(
    time: ControllableTimeSource = ControllableTimeSource(now: 0),
    store: some MonologuePromptStore = InMemoryMonologuePromptStore()
) -> MonologueSession {
    MonologueSession(prompts: ["Talk about breakfast"], store: store, time: time)
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter MonologueSessionClockTests`

Expected: FAIL — `MonologueSession` not found.

- [ ] **Step 3: Write minimal implementation**

Enough of `MonologueSession` to pass this task (skip / ready / pause / resume / elapsed / tick no-op except when remaining hits 0 — not required yet):

```swift
import Foundation
import Observation

@MainActor
@Observable
public final class MonologueSession {
    public private(set) var phase: MonologuePhase = .planning
    public private(set) var takeNumber: Int = 1
    public private(set) var takes: [MonologueTake] = []
    public private(set) var report: MonologueReport?
    public private(set) var possibleMinorFlag = false
    public var notes: String = ""
    public var reuseLine: String = ""
    public let store: any MonologuePromptStore

    public var prompt: String { cursor.current }
    public var ceiling: TimeInterval { MonologueCeiling.seconds(forTake: takeNumber) }

    public var elapsed: TimeInterval {
        guard let origin else { return 0 }
        let extra = (phase == .paused ? (time.now - (pausedAt ?? time.now)) : 0)
        return max(0, time.now - origin - pausedAccumulated - extra)
    }

    public var remaining: TimeInterval { max(0, ceiling - elapsed) }

    public var betweenCopy: String {
        switch takes.last?.index {
        case 1: return "Three minutes."
        case 2: return "Two minutes."
        default: return ""
        }
    }

    private var cursor: MonologuePromptCursor
    private let time: any ConversationTimeSource
    private var origin: TimeInterval?
    private var pausedAccumulated: TimeInterval = 0
    private var pausedAt: TimeInterval?
    private var liveRanges: [ConversationSpeechInterval] = []
    private var liveTranscript: String = ""

    public init(
        prompts: [String],
        store: any MonologuePromptStore,
        time: any ConversationTimeSource
    ) {
        self.cursor = MonologuePromptCursor(prompts: prompts, lastPrompt: store.lastPrompt)
        self.store = store
        self.time = time
    }

    public func skipTopic() {
        guard phase == .planning || phase == .between else { return }
        cursor.skip()
    }

    public func ready() {
        guard phase == .planning || phase == .between else { return }
        store.lastPrompt = prompt
        liveRanges = []
        liveTranscript = ""
        pausedAccumulated = 0
        pausedAt = nil
        origin = time.now
        phase = .taking
    }

    public func pause() {
        guard phase == .taking else { return }
        pausedAt = time.now
        phase = .paused
    }

    public func resume() {
        guard phase == .paused, let pausedAt else { return }
        pausedAccumulated += time.now - pausedAt
        self.pausedAt = nil
        phase = .taking
    }

    public func tick() async {
        guard phase == .taking, remaining <= 0 else { return }
        finishTake()
    }

    public func done() { finishTake() }

    public func confirmLeave() {
        guard phase != .report, phase != .crisis else { return }
        if takes.isEmpty, phase == .planning {
            return
        }
        if phase == .taking || phase == .paused {
            snapshotTake()
        }
        emitReport(reason: takes.count == 3 ? .completed : .leftEarly)
    }

    public func ingestText(_ text: String) {
        guard phase == .taking else { return }
        switch CrisisGate.evaluate(text) {
        case .crisis:
            emitCrisis()
        case .possibleMinor:
            possibleMinorFlag = true
            rememberTranscript(text)
        case .therapyOverride, .allow:
            rememberTranscript(text)
        }
    }

    public func ingestRanges(_ ranges: [ConversationSpeechInterval]) {
        guard phase == .taking else { return }
        liveRanges = ranges
    }

    private func rememberTranscript(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        liveTranscript = trimmed
    }

    private func finishTake() {
        guard phase == .taking || phase == .paused else { return }
        snapshotTake()
        origin = nil
        pausedAt = nil
        if takeNumber == 3 {
            emitReport(reason: .completed)
            return
        }
        takeNumber += 1
        phase = .between
    }

    private func snapshotTake() {
        let wall = elapsed
        takes.append(
            MonologueTake(
                index: takeNumber,
                wallSeconds: wall,
                ranges: liveRanges,
                transcript: liveTranscript
            )
        )
        liveRanges = []
        liveTranscript = ""
    }

    private func emitReport(reason: MonologueEndReason) {
        report = MonologueReportBuilder.build(takes: takes, endReason: reason)
        phase = reason == .crisisReferral ? .crisis : .report
    }

    private func emitCrisis() {
        report = MonologueReportBuilder.build(takes: takes, endReason: .crisisReferral)
        phase = .crisis
        origin = nil
    }
}
```

`confirmLeave` from planning with zero takes is a no-op (UI Back → home). That matches “nothing to score.” From a live or between screen it snapshots if needed and opens the report.

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter MonologueSessionClockTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Monologue/MonologueSession.swift \
  ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/MonologueSessionTests.swift
git commit -m "$(cat <<'EOF'
feat: start Monologue takes without a warmup and freeze on Pause

EOF
)"
```

---

### Task 9: Session — Done, 0:00, between copy, take 3 → report

**Files:**
- Modify: `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Monologue/MonologueSession.swift`
- Modify: `ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/MonologueSessionTests.swift`

- [ ] **Step 1: Write the failing test**

Add a new suite in the same test file (or keep appending):

```swift
@Suite("Monologue session takes")
struct MonologueSessionTakeTests {
    @MainActor
    @Test("Done after take 1 goes between with Three minutes")
    func afterTake1() {
        let time = ControllableTimeSource(now: 0)
        let session = makeSession(time: time)
        session.ready()
        time.advance(40)
        session.ingestRanges([ConversationSpeechInterval(start: 0, end: 30)])
        session.ingestText("I take the bus")
        session.done()
        #expect(session.phase == .between)
        #expect(session.betweenCopy == "Three minutes.")
        #expect(session.takeNumber == 2)
        #expect(session.takes.count == 1)
    }

    @MainActor
    @Test("0:00 ends the take the same as Done")
    func zeroEqualsDone() async {
        let time = ControllableTimeSource(now: 0)
        let session = makeSession(time: time)
        session.ready()
        time.advance(240)
        await session.tick()
        #expect(session.phase == .between)
        #expect(session.takes.first?.wallSeconds == 240)
    }

    @MainActor
    @Test("take 3 Done opens the report")
    func take3Report() {
        let time = ControllableTimeSource(now: 0)
        let session = makeSession(time: time)
        for _ in 1...3 {
            session.ready()
            time.advance(35)
            session.ingestRanges([ConversationSpeechInterval(start: 0, end: 30)])
            session.ingestText("I take the bus to work every day")
            session.done()
        }
        #expect(session.phase == .report)
        #expect(session.report?.kind == .full)
        #expect(session.report?.endReason == .completed)
    }

    @MainActor
    @Test("between copy after take 2 is Two minutes")
    func afterTake2() {
        let time = ControllableTimeSource(now: 0)
        let session = makeSession(time: time)
        session.ready(); time.advance(35); session.done()
        session.ready(); time.advance(35); session.done()
        #expect(session.phase == .between)
        #expect(session.betweenCopy == "Two minutes.")
        #expect(session.takeNumber == 3)
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter MonologueSessionTakeTests`

Expected: FAIL only if `finishTake` / `tick` from Task 8 is incomplete. If Task 8 already implemented `done`/`tick`/`betweenCopy`, this should go green — do not rewrite. If it fails, finish those methods as in Task 8’s implementation block.

- [ ] **Step 3: Implement only what is missing**

Keep leftover unused (no fill-to-zero). Do not auto-start the next take.

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter MonologueSession`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Monologue/MonologueSession.swift \
  ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/MonologueSessionTests.swift
git commit -m "$(cat <<'EOF'
feat: shrink Monologue ceilings 4 to 3 to 2 and report after take 3

EOF
)"
```

---

### Task 10: Session — crisis keywords and leave-to-report

**Files:**
- Modify: `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Monologue/MonologueSession.swift`
- Modify: `ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/MonologueSessionTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
@Suite("Monologue session crisis and leave")
struct MonologueSessionCrisisTests {
    @MainActor
    @Test("keyword crisis skips the fluency report")
    func crisis() {
        let session = makeSession()
        session.ready()
        session.ingestText("I want to kill myself")
        #expect(session.phase == .crisis)
        #expect(session.report?.kind == .crisis)
        #expect(session.report?.lines.isEmpty == true)
    }

    @MainActor
    @Test("empty Apple text is not 988")
    func emptyNotCrisis() {
        let session = makeSession()
        session.ready()
        session.ingestText("   ")
        #expect(session.phase == .taking)
    }

    @MainActor
    @Test("Back after a counting take opens a report")
    func leaveOpensReport() {
        let time = ControllableTimeSource(now: 0)
        let session = makeSession(time: time)
        session.ready()
        time.advance(40)
        session.ingestRanges([ConversationSpeechInterval(start: 0, end: 30)])
        session.confirmLeave()
        #expect(session.phase == .report)
        #expect(session.report?.kind == .thin)
        #expect(session.report?.endReason == .leftEarly)
    }

    @MainActor
    @Test("Back on planning with no take does not fabricate a report")
    func leavePlanning() {
        let session = makeSession()
        session.confirmLeave()
        #expect(session.phase == .planning)
        #expect(session.report == nil)
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter MonologueSessionCrisisTests`

Expected: FAIL only if ingest/crisis/leave from Task 8 is incomplete.

- [ ] **Step 3: Implement only what is missing**

`ingestText` must run `CrisisGate` on volatile ∪ final the view will feed (the session does not distinguish; the view calls it on both). Fail closed on `.crisis`. Empty → allow.

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter MonologueSession`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Monologue/MonologueSession.swift \
  ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/MonologueSessionTests.swift
git commit -m "$(cat <<'EOF'
feat: halt Monologue on crisis keywords and allow leaving to a thin report

EOF
)"
```

---

## Slice B — SwiftUI shell

Kit tests stay green. `xcodegen generate` then build in Xcode after Task 12.

### Task 11: Home — three equal glass rows

**Files:**
- Modify: `ios/App/Screens/HomeView.swift`

Replace the Conversation hero + “More to read” section with three equal rows, same glass as today’s Reading row. Conversation budget is tertiary on the Conversation row only.

- [ ] **Step 1: There is no kit test. Replace `HomeView` body with:**

```swift
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    formatRow(title: "Read a passage") {
                        model.route = .library
                    }
                    formatRow(
                        title: "Start a conversation",
                        footnote: model.budget.label,
                        disabled: !model.budget.startEnabled
                    ) {
                        model.requestStartConversation()
                    }
                    formatRow(title: "Talk about something") {
                        model.requestStartMonologue()
                    }
                }
                .padding(.horizontal, SpeechSpacing.page)
                .padding(.top, SpeechSpacing.related)
                .padding(.bottom, 40)
            }
```

Row helper (same file):

```swift
    private func formatRow(
        title: String,
        footnote: String? = nil,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
                action()
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let footnote {
                    Text(footnote)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
    }
```

Delete `conversationCard` and `readSection`. Do not put “More to read”, “4/3/2”, or “Monologue” on screen.

- [ ] **Step 2: Commit even if `requestStartMonologue` does not compile yet** — if it doesn’t, do Task 12 in the same working tree before this commit.

If compiling is blocked, continue immediately to Task 12 and commit both together:

```bash
git commit -m "$(cat <<'EOF'
feat: put Reading, Conversation, and Talk on equal home rows

EOF
)"
```

---

### Task 12: Routes, age gate, RootView

**Files:**
- Modify: `ios/App/AppModel.swift`
- Modify: `ios/App/RootView.swift`
- Modify: `ios/App/Screens/AgeAttestationView.swift` (title must not say Conversation when pending is monologue)

- [ ] **Step 1: Extend `AppModel.Route`**

```swift
        case monologue
        case monologueReport(MonologueReport)
```

Add:

```swift
    enum PendingStart: Equatable {
        case conversation, monologue
    }

    var pendingStart: PendingStart = .conversation

    func requestStartMonologue() {
        if !account.attested18 {
            pendingStart = .monologue
            route = .ageGate
            return
        }
        startMonologue()
    }

    func startMonologue() {
        route = .monologue
    }

    func finishMonologue(report: MonologueReport, possibleMinorFlag: Bool = false) {
        notePossibleMinorIfNeeded(possibleMinorFlag)
        if report.kind == .crisis {
            route = .crisis
            return
        }
        route = .monologueReport(report)
    }
```

Change `requestStartConversation` to set `pendingStart = .conversation` before the age gate.

Change `continueAfterAgeGate`:

```swift
    private func continueAfterAgeGate() {
        switch pendingStart {
        case .conversation:
            startConversation()
        case .monologue:
            startMonologue()
        }
    }
```

Monologue must **not** go through `confirmAIDisclosure`. Do not consume `budget`.

- [ ] **Step 2: RootView**

Add `monologuePresented` analog to `conversationPresented` for `.monologue` and `.monologueReport` only (crisis stays on the existing conversation destination so `CrisisReferralView` is reused).

```swift
                .navigationDestination(isPresented: monologuePresented) {
                    monologueDestination
                }
```

```swift
    private var monologuePresented: Binding<Bool> {
        Binding(
            get: {
                switch model.route {
                case .monologue, .monologueReport: true
                default: false
                }
            },
            set: { presented in
                if !presented {
                    switch model.route {
                    case .monologue, .monologueReport:
                        model.goHome()
                    default:
                        break
                    }
                }
            }
        )
    }

    @ViewBuilder
    private var monologueDestination: some View {
        switch model.route {
        case .monologueReport(let report):
            MonologueReportView(report: report)
        default:
            MonologueSessionView()
        }
    }
```

Age gate for Talk still uses `conversationPresented` (`.ageGate`). Change `AgeAttestationView` `.navigationTitle("Conversation")` to `.navigationTitle("")` or `"SpeechApp"` so the first-run Talk path is not labeled Conversation.

- [ ] **Step 3: Stub views so the project compiles**

If Task 13/14 are not done, add temporary:

```swift
struct MonologueSessionView: View {
    var body: some View { Text("Talk") }
}
struct MonologueReportView: View {
    let report: MonologueReport
    var body: some View { Text("Report") }
}
```

Replace them in the next two tasks — do not leave the stubs.

- [ ] **Step 4: Commit**

```bash
git add ios/App/AppModel.swift ios/App/RootView.swift ios/App/Screens/HomeView.swift \
  ios/App/Screens/AgeAttestationView.swift
git commit -m "$(cat <<'EOF'
feat: route Talk about something without Realtime or the monthly start budget

EOF
)"
```

---

### Task 13: MonologueSessionView (planning / live / between / pause)

**Files:**
- Create: `ios/App/Screens/MonologueSessionView.swift`

Copy chrome language from `ReadingSessionView` / `ConversationSessionView`: `SpeechScreenBackground`, serif passage, `safeAreaInset` bottom bar, `speechGlassCircle`, `AuroraPill` **mode `.listen` only**.

Behavior:

| Phase | Page | Chrome |
|---|---|---|
| planning / between | Serif `session.prompt`, `TextEditor` notes, reuse field if `takes.last?.index == 1 \|\| takes.last?.index == 2`, between copy, text button **Another topic** | **I’m ready** (`SpeechPrimaryButtonStyle(showsTint: true)`). No aurora. |
| taking | Topic line only (`session.prompt`). Digital countdown `remaining` as `m:ss`. | Pause, aurora listen, **Done** (filled / tinted circle, accessibility **Done** — not Stop). |
| paused | Same plus **Paused.** Never “you went quiet.” | Play (resume), frozen aurora, Done. |
| report / crisis | View should already have called `finishMonologue` | — |

Back: if `phase == .planning` && `takes.isEmpty`, `model.goHome()`. Else confirmationDialog **Leave this talk?** / **Leave** / **Keep going**. Leave calls `session.confirmLeave()` then `finishMonologue`.

Done calls `session.done()`; if phase becomes `.report`, finish. I’m ready calls `session.ready()` then starts listen (Task 15). For this task, I’m ready may only flip phase (listen in Task 15).

Countdown label:

```swift
    private func clockLabel(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
```

Drive `tick` with `Timer.publish(every: 1, ...)` like Conversation.

Do **not** show notes or reuse line while `phase == .taking || phase == .paused`.

Do **not** show metrics between takes.

Reuse field: `TextField` one line, bound to `session.reuseLine`, visible when `session.takes.last?.index != nil` (after take 1 and 2). Placeholder something like **One thing to reuse** — not “grammar feedback.”

Another topic: `session.skipTopic()` only in planning/between.

- [ ] **Step 1: Implement the view** (full file in the repo; follow ConversationSessionView structure: `body` ZStack, `liveCanvas` / `planningCanvas`, `bottomChrome`, `actionRow`).

Planning canvas:

```swift
            Text(session.prompt)
                .font(.system(size: 22, weight: .regular, design: .serif))
                .lineSpacing(10)
```

Live canvas: same prompt as a **topic line** (`.title3` serif), then countdown `.title` monospacedDigit.

Filled Done control (not a second Stop):

```swift
                Button {
                    session.done()
                    routeIfFinished()
                } label: {
                    Image(systemName: "checkmark")
                        .speechGlassCircle(tint: .accentColor)
                }
                .accessibilityLabel("Done")
```

- [ ] **Step 2: `routeIfFinished`**

```swift
    private func routeIfFinished() {
        guard let session else { return }
        if session.phase == .report || session.phase == .crisis, let report = session.report {
            model.finishMonologue(
                report: report,
                possibleMinorFlag: session.possibleMinorFlag
            )
        }
    }
```

Create the session in `.task`:

```swift
        let bank = try OpenPromptBank.loadBundled()
        session = MonologueSession(
            prompts: bank.prompts,
            store: UserDefaultsMonologuePromptStore(),
            time: SystemTimeSource()
        )
```

- [ ] **Step 3: Commit**

```bash
git add ios/App/Screens/MonologueSessionView.swift
git commit -m "$(cat <<'EOF'
feat: add Monologue planning, live, and between chrome

EOF
)"
```

---

### Task 14: MonologueReportView

**Files:**
- Create: `ios/App/Screens/MonologueReportView.swift`

Mirror `ConversationReportView`: serif title **Your talk**, lines card, thin copy **Too little speech to score the rest.**, comparison as body text when `!report.comparison.isEmpty`, Done / Back to home → `model.goHome()`.

No “Grade”, no extra accuracy card.

```swift
        .navigationTitle("Your talk")
```

- [ ] **Step 1: Implement and replace any stub from Task 12.**

- [ ] **Step 2: Commit**

```bash
git add ios/App/Screens/MonologueReportView.swift
git commit -m "$(cat <<'EOF'
feat: show the Monologue named-index profile after the regimen

EOF
)"
```

---

## Slice C — on-device listen

### Task 15: Live capture (no 3-2-1, no PCM, no WebRTC)

**Files:**
- Modify: `ios/App/Screens/MonologueSessionView.swift`
- Modify: `ios/project.yml` usage strings

On **I’m ready** (not on appear):

1. Request mic + speech authorization (copy `ReadingSessionView.requestMic` / `LiveTranscriptionEngine.requestSpeechAuthorization`).
2. `LiveTranscriptionEngine().prepareIfNeeded()` — **do not** run a 3-2-1 overlay. No `countdownRemaining`. No `ReadingCountdownOverlay`.
3. `MicAudioSource()` + engine `start`. This is allowed here because there is no WebRTC session. Do **not** construct `PCMStore`. Do **not** start `LiveConversationMouth`.
4. Pump `engine.updates`:
   - `session.ingestText(update.rawText)` on every update (volatile ∪ final — fail closed). Treat `rawText` as the **current full hypothesis for this take** (assign, do not concatenate or you will duplicate n-grams and inflate overlap).
   - Build `[ConversationSpeechInterval]` from `SpokenToken` `startTime`/`endTime` where both exist; `session.ingestRanges`.
5. Pump audio chunks: `speechEnergy = min(1, rms / 0.06)` like Reading; pass into `AuroraPill(energy:mode:.listen)`.
6. On `done` / 0:00 / confirmLeave / crisis: `engine.stop()`, stop the audio source, drop buffers. Sequential process-and-delete = **do not keep PCM**.

Contextual phrases: `[session.prompt]` only (known topic, not a script).

If I’m ready is tapped for take 2/3, start a **new** engine for that take (do not hold take 1 PCM).

- [ ] **Step 1: Implement the listen loop in the view** (private methods `beginListen()` / `stopListen()`). Call `beginListen()` at the end of `ready()` UI action. Call `stopListen()` at the start of `done()`, `confirmLeave`, and when routing to crisis.

- [ ] **Step 2: Update `ios/project.yml` (and generated Info.plist via xcodegen)**

`NSMicrophoneUsageDescription`:

```
SpeechApp uses the microphone so you can read aloud, talk on a topic, or rehearse with an AI partner. Partner audio is streamed to OpenAI. Reading and topic talks are scored on this device. We do not keep the recording.
```

`NSSpeechRecognitionUsageDescription`:

```
SpeechApp uses on-device speech recognition to follow reading and to time topic talks. Recognition runs on your device.
```

Run: `cd ios && xcodegen generate`

- [ ] **Step 3: Commit**

```bash
git add ios/App/Screens/MonologueSessionView.swift ios/project.yml ios/App/Info.plist
git commit -m "$(cat <<'EOF'
feat: listen on-device for Monologue takes without Realtime or stored PCM

EOF
)"
```

---

### Task 16: System interrupt pause

**Files:**
- Modify: `ios/App/Screens/MonologueSessionView.swift`

Reuse Conversation’s rules: `scenePhase != .active` → `session.pause()`; `AVAudioSession.routeChangeNotification` → pause if `ConversationRoutePause.shouldPause(reason:)`. Volume 0 is not pause. Do **not** add 1.5 min silence auto-pause. Abandoned-pause TTL is **not** in the Monologue spec — do not copy Conversation’s 10 min hang-up.

- [ ] **Step 1: Add `.onChange(of: scenePhase)` and route-change observer** calling `session.pause()` when `phase == .taking`.

- [ ] **Step 2: Commit**

```bash
git add ios/App/Screens/MonologueSessionView.swift
git commit -m "$(cat <<'EOF'
feat: freeze the Monologue take clock on background and route loss

EOF
)"
```

---

### Task 17: Docs — what exists in code

**Files:**
- Modify: `docs/formats.md` “What exists in code today”

After Slice C works on a device, change Monologue from spec-only to: session loop in the app, local recorder, report after the regimen. Keep Conversation/Reading descriptions accurate.

- [ ] **Step 1: Update the paragraph. Do not reintroduce the 5–15 min one-shot.**

- [ ] **Step 2: Commit**

```bash
git add docs/formats.md
git commit -m "$(cat <<'EOF'
docs: note Monologue v1 is in the app

EOF
)"
```

---

## Device smoke (not automated)

After Task 16:

1. Home shows three equal rows; Conversation still respects the monthly budget; Talk does not.
2. Talk opens last topic if you already finished one; **Another topic** cycles; I’m ready starts 4:00 immediately.
3. Pause freezes the digits; leftover at Done is unused; 0:00 ends the take.
4. After take 1 the page says **Three minutes.** and shows notes + reuse line, not metrics.
5. Take 3 opens **Your talk** with PTR / pauses / overlap, or thin copy if you left early.
6. Saying a crisis keyword full-screens 988, not the profile.
7. Copy never includes “same talk”, “repeat”, or “tell it again.”

---

## Self-review (coverage)

| Spec requirement | Task |
|---|---|
| 4/3/2 ceilings, Done-early, 0:00 = Done | 4, 9 |
| No 3-2-1 / no planning countdown | 8, 13, 15 |
| Notes hidden on-mic; reuse line after take 1 | 8, 13 |
| Another topic; silent last-prompt return | 6, 7, 8 |
| Pause freeze; no silence auto-pause | 8, 16 |
| Pause/aurora listen/Done; Back confirm | 13 |
| Between page = planning aesthetic, duration copy only | 9, 13 |
| Counting ≥30 s; full if ≥2; thin otherwise | 4, 5 |
| PTR, pause time, pause count, overlap, optional pace + caveat | 1–3, 5 |
| No composite / GOP / grammar / turns | 5, 14 |
| Crisis 988 + POST `/crisis` via existing view | 10, 13, CrisisReferralView |
| Local SpeechAnalyzer; no Realtime; no PCM; no embeddings | 15 |
| Equal home rows | 11 |
| 18+ still; no chatbot disclosure | 12 |
