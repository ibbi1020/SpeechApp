# Conversation v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a 15-minute English rehearsal call: countdown → mint → partner opens → talk → Stop/wrap → honest report (time, turns, thin-vs-full). Spoken cues in v1 are `open` / `wrap_warn` / `wrap_close` only.

**Architecture:** SpeechAppKit owns the session brain (clock, pause, wrap, crisis keywords, report floor) and is fully testable on macOS with a `FakeConversationMouth`. The iOS App target owns WebRTC + OpenAI Realtime (`ConversationMouth` live impl) and SwiftUI. A tiny `server/` mints ephemeral keys and enforces the 20-start calendar budget. Never start Reading’s `MicAudioSource`.

**Tech Stack:** Swift 6 / iOS 26, Swift Testing (`swift test`), SpeechAppKit (no new SPM deps in the kit), App target + `stasel/WebRTC`, OpenAI Realtime `gpt-realtime-2.1-mini` over WebRTC, Node `server/` for mint/budget.

**Spec:** `docs/superpowers/specs/2026-09-21-conversation-format-design.md` (product). `docs/superpowers/specs/2026-09-21-conversation-technical-layer-design.md` (locks).

---

## Do not build (v1)

If a task below does not name it, **do not add it**:

- Spoken `code_switch` / `filler_ok` (machinery flags may exist, default **OFF**, no LID/filler wait on `response.create`)
- PMI, collocation, grammar, register, hesitation *location*, vocal variety, IC, coherence, “Understood?”, Gap 2 variance, progress chips
- CallKit / PushKit, `MicAudioSource`, Reading `PCMStore`, TokenAligner, GOP, StruggleLedger, SessionDiagnostics JSONL
- Dual-locale transcriber (v1 does not collect L1)
- Topic picker, Change Topic, visible stance card
- Mid-talk paywall, WebSocket audio fallback, silent Realtime resume with a summary
- 30 s forgotten-mic hang-up (use 1.5 min auto-pause in background too)
- Daily pushes, AI-initiated sessions, Explain It Another Way
- Live Activity (Slice C, after the mouth works — not Slice A)
- Quality spike / mini-vs-flagship (ship gate, not a build task)
- Website protocol / 988 legal copy (ship blocker for *release*, not for first TestFlight of the loop)

---

## File map

New kit types live under `Conversation/` so Reading stays untouched.

| Path | Responsibility |
|---|---|
| `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Conversation/ConversationPhase.swift` | Phase + end-reason enums |
| `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Conversation/ConversationTimeSource.swift` | Injected clock |
| `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Conversation/ConversationCue.swift` | Cue id + frozen-prefix assembly |
| `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Conversation/ConversationMouth.swift` | Mouth protocol + events |
| `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Conversation/FakeConversationMouth.swift` | Test double |
| `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Conversation/CrisisGate.swift` | Keyword fail-closed |
| `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Conversation/ConversationReport.swift` | Report model + thin/full builder |
| `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Conversation/OpenPromptBank.swift` | 20 opening questions |
| `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Conversation/StanceDeck.swift` | Sample 3–5 views |
| `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Conversation/ConversationSession.swift` | The brain |
| `ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/Conversation*.swift` | Kit tests |
| `ios/App/Conversation/LiveConversationMouth.swift` | WebRTC + Realtime (App target only) |
| `ios/App/Conversation/MintClient.swift` | Authenticated mint |
| `ios/App/Screens/HomeView.swift` | Library + Start a conversation |
| `ios/App/Screens/ConversationSessionView.swift` | Countdown, aurora, pause/stop |
| `ios/App/Screens/ConversationReportView.swift` | Thin/full report |
| `ios/App/Screens/CrisisReferralView.swift` | 988 screen |
| `ios/App/Screens/AgeAttestationView.swift` | 18+ once |
| `ios/App/AppModel.swift` | Routes for conversation |
| `ios/App/RootView.swift` | Home vs Reading vs Conversation |
| `ios/project.yml` + `ios/App/Info.plist` | `audio` background mode, mic copy |
| `server/mint.mjs` + `server/budget.mjs` + `server/test.mjs` | Mint, calendar budget, crisis counter |
| `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Resources/Conversation/opens.json` | Opening bank |
| `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Resources/Conversation/stances.json` | Stance cards |

**Reuse from Reading (UI only):** `SpeechChrome.swift` (background, buttons, countdown tokens), `AuroraPresenceView.swift` (mic **energy** later from WebRTC RMS — not from `MicAudioSource`).

**Never reuse:** `MicAudioSource`, `PCMStore`, `TokenAligner`, `ReadingSession`, `SessionDiagnostics`.

---

## Slice A — session brain (macOS `swift test`, no OpenAI)

This slice is the product. Fake mouth. Do not open Xcode until Task 8.

### Task 1: Phase and end-reason types

**Files:**
- Create: `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Conversation/ConversationPhase.swift`
- Test: `ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/ConversationPhaseTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import SpeechAppKit

@Suite("Conversation phases")
struct ConversationPhaseTests {
    @Test("crisis and dropped never wrap")
    func terminalExcludesWrapping() {
        #expect(ConversationPhase.crisis.entersWrapping == false)
        #expect(ConversationPhase.dropped.entersWrapping == false)
        #expect(ConversationPhase.talking.entersWrapping == true)
    }

    @Test("userStop has no spoken close")
    func userStopSilent() {
        #expect(ConversationEndReason.userStop.speaksClose == false)
        #expect(ConversationEndReason.wrap.speaksClose == true)
        #expect(ConversationEndReason.pauseTTL.speaksClose == false)
        #expect(ConversationEndReason.crisisReferral.speaksClose == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ios/Packages/SpeechAppKit && swift test --filter ConversationPhaseTests`

Expected: FAIL — `ConversationPhase` not found.

- [ ] **Step 3: Write minimal types**

```swift
import Foundation

public enum ConversationPhase: Equatable, Sendable {
    case idle, countdown, connecting, talking, paused, wrapping, report, crisis, dropped

    public var entersWrapping: Bool {
        switch self {
        case .talking, .paused: return true
        default: return false
        }
    }
}

public enum ConversationEndReason: Equatable, Sendable {
    case userStop, wrap, pauseTTL, drop, crisisReferral, configDrift

    public var speaksClose: Bool { self == .wrap }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter ConversationPhaseTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Conversation/ConversationPhase.swift \
        ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/ConversationPhaseTests.swift
git commit -m "$(cat <<'EOF'
Add Conversation phase and end-reason types.

EOF
)"
```

---

### Task 2: Injected clock

**Files:**
- Create: `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Conversation/ConversationTimeSource.swift`
- Test: `ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/ConversationTimeSourceTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import SpeechAppKit

@Suite("Conversation time source")
struct ConversationTimeSourceTests {
    @Test("controllable clock advances only when we say so")
    func controllable() {
        let time = ControllableTimeSource(now: 0)
        #expect(time.now == 0)
        time.advance(90)
        #expect(time.now == 90)
    }
}
```

- [ ] **Step 2: Run to verify fail** — `swift test --filter ConversationTimeSourceTests`

- [ ] **Step 3: Minimal implementation**

```swift
import Foundation

public protocol ConversationTimeSource: AnyObject, Sendable {
    var now: TimeInterval { get }
}

public final class ControllableTimeSource: ConversationTimeSource, @unchecked Sendable {
    public var now: TimeInterval
    public init(now: TimeInterval = 0) { self.now = now }
    public func advance(_ delta: TimeInterval) { now += delta }
}

public final class SystemTimeSource: ConversationTimeSource, @unchecked Sendable {
    public init() {}
    public var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
}
```

- [ ] **Step 4: Tests pass.** **Step 5: Commit** `Add injectable Conversation clock.`

---

### Task 3: Mouth protocol + fake

**Files:**
- Create: `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Conversation/ConversationMouth.swift`
- Create: `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Conversation/FakeConversationMouth.swift`
- Test: `ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/FakeConversationMouthTests.swift`

- [ ] **Step 1: Failing test** — fake records `response.create` instructions and can emit `speech_stopped` / `audioDelta` / `responseDone`.

```swift
import Testing
@testable import SpeechAppKit

@Suite("Fake mouth")
struct FakeConversationMouthTests {
    @Test("records response.create instructions")
    @MainActor
    func recordsInstructions() async throws {
        let mouth = FakeConversationMouth()
        try await mouth.connect(ephemeralKey: "ek_test")
        try await mouth.sendResponseCreate(instructions: "OPEN: ask about coffee")
        #expect(mouth.responseCreates == ["OPEN: ask about coffee"])
        mouth.emit(.audioDelta)
        mouth.emit(.responseDone(transcript: "Coffee?"))
        #expect(mouth.didClose == false)
        await mouth.close()
        #expect(mouth.didClose == true)
    }
}
```

- [ ] **Step 2: Fail** — types missing.

- [ ] **Step 3: Implementation**

```swift
import Foundation

public enum MouthEvent: Equatable, Sendable {
    case sessionUpdated
    case speechStarted
    case speechStopped
    case audioDelta
    case responseDone(transcript: String)
    case disconnected
    case failed
}

public protocol ConversationMouth: AnyObject, Sendable {
    var events: AsyncStream<MouthEvent> { get }
    func connect(ephemeralKey: String) async throws
    func sendResponseCreate(instructions: String) async throws
    func updateTurnDetectionNull() async throws
    func close() async
}

public final class FakeConversationMouth: ConversationMouth, @unchecked Sendable {
    public let events: AsyncStream<MouthEvent>
    private let continuation: AsyncStream<MouthEvent>.Continuation
    public private(set) var responseCreates: [String] = []
    public private(set) var didClose = false
    public private(set) var turnDetectionNulled = false
    public var connectShouldFail = false

    public init() {
        let pair = AsyncStream<MouthEvent>.makeStream(bufferingPolicy: .unbounded)
        events = pair.stream
        continuation = pair.continuation
    }

    public func connect(ephemeralKey: String) async throws {
        if connectShouldFail { throw MouthError.connectFailed }
        // Do not auto-yield. Tests and the App event pump call `session.handle`.
    }

    public func sendResponseCreate(instructions: String) async throws {
        responseCreates.append(instructions)
    }

    public func updateTurnDetectionNull() async throws {
        turnDetectionNulled = true
    }

    public func close() async {
        didClose = true
        continuation.finish()
    }

    public func emit(_ event: MouthEvent) {
        continuation.yield(event)
    }
}

public enum MouthError: Error { case connectFailed }
```

- [ ] **Step 4: Pass.** **Step 5: Commit** `Add ConversationMouth protocol and fake.`

---

### Task 4: Cue assembly (replace, never cue-only)

**Files:**
- Create: `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Conversation/ConversationCue.swift`
- Test: `ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/ConversationCueTests.swift`

Locked rule: `response.create` instructions **replace** session instructions. Always `frozen_persona_prefix + stance + cue`. Missing the prefix wipes the partner.

- [ ] **Step 1: Failing test**

```swift
import Testing
@testable import SpeechAppKit

@Suite("Conversation cues")
struct ConversationCueTests {
    @Test("open instructions include frozen prefix and stance")
    func openHasPrefix() {
        let text = ConversationCueAssembler.instructions(
            prefix: "PREFIX",
            stance: "STANCE: cats > dogs",
            cue: .open(question: "What did you have for breakfast?")
        )
        #expect(text.contains("PREFIX"))
        #expect(text.contains("STANCE: cats > dogs"))
        #expect(text.contains("What did you have for breakfast?"))
        #expect(text.contains("Do not announce a timer"))
    }

    @Test("cue-only string is rejected")
    func rejectsCueOnly() {
        let text = ConversationCueAssembler.instructions(
            prefix: "PREFIX",
            stance: "STANCE",
            cue: .wrapWarn
        )
        #expect(text.hasPrefix("PREFIX"))
        #expect(!text.hasPrefix("Answer them"))
    }
}
```

- [ ] **Step 2: Fail.** **Step 3: Implementation**

```swift
import Foundation

public enum ConversationCue: Equatable, Sendable {
    case open(question: String)
    case wrapWarn
    case wrapClose
    // codeSwitch / fillerOk exist for later. v1 must not send them.
    case codeSwitch
    case fillerOk
}

public enum ConversationCueAssembler {
    public static let doNotAnnounceTimer = "Do not announce a timer or a system message."

    public static func instructions(prefix: String, stance: String, cue: ConversationCue) -> String {
        let aside: String
        switch cue {
        case .open(let question):
            aside = "Open with this real question, nothing else first: \(question)"
        case .wrapWarn:
            aside = "Answer them as you were going to. In the same turn, one short aside: about two minutes left. Stay on the topic. \(doNotAnnounceTimer)"
        case .wrapClose:
            aside = "Close the conversation in character. No new question. \(doNotAnnounceTimer)"
        case .codeSwitch, .fillerOk:
            aside = "" // v1 must not reach here
        }
        return """
        \(prefix)
        \(stance)
        \(aside)
        """
    }

    public static func v1MaySend(_ cue: ConversationCue) -> Bool {
        switch cue {
        case .open, .wrapWarn, .wrapClose: return true
        case .codeSwitch, .fillerOk: return false
        }
    }

    /// `open` miss → no `?`. `wrap_warn` miss → no two-minute aside. `wrap_close` miss → empty transcript.
    public static func heard(_ cue: ConversationCue, in transcript: String) -> Bool {
        let t = transcript.lowercased()
        switch cue {
        case .open: return transcript.contains("?")
        case .wrapWarn: return t.contains("two minute") || t.contains("2 minute")
        case .wrapClose: return !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .codeSwitch, .fillerOk: return false
        }
    }
}

public enum FrozenPersona {
    public static let prefix = """
    You are a rehearsal partner for spoken English, not a friend, therapist, or human.
    Hold the stance card. Disagree on the point, not the person.
    Warm, curious, never fawning. Do not pile on.
    English only. Casual register is fine; do not bully; do not sprinkle slang as a drill.
    Fillers and silence are allowed. Do not name "uh".
    Educational rehearsal, not therapy, counseling, or a mental-health companion.
    Do not infer stuckness, hesitation, or fillers from how they sound.
    Do not announce a timer or a system message.
    """
}
```

- [ ] **Step 4: Pass.** **Step 5: Commit** `Assemble Conversation cue instructions with frozen prefix.`

---

### Task 5: Opening bank + stance deck

**Files:**
- Create: `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Resources/Conversation/opens.json`
- Create: `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Resources/Conversation/stances.json`
- Create: `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Conversation/OpenPromptBank.swift`
- Create: `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Conversation/StanceDeck.swift`
- Test: `ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/OpenPromptBankTests.swift`

- [ ] **Step 1: Failing test** — bank has ≥20 everyday adult prompts, none about news/trauma; stance sample returns 3–5 views; sampling is deterministic with a seeded RNG.

```swift
import Testing
@testable import SpeechAppKit

@Suite("Open prompts and stances")
struct OpenPromptBankTests {
    @Test("loads at least 20 non-trauma opens")
    func twentyOpens() throws {
        let bank = try OpenPromptBank.loadBundled()
        #expect(bank.prompts.count >= 20)
        #expect(bank.prompts.allSatisfy { !$0.lowercased().contains("suicide") })
        #expect(bank.prompts.allSatisfy { !$0.lowercased().contains("war") })
    }

    @Test("stance sample is 3 to 5 views")
    func stanceCount() throws {
        var rng = SplitMix64(seed: 1)
        let deck = try StanceDeck.loadBundled()
        let card = deck.sample(rng: &rng)
        #expect((3...5).contains(card.views.count))
        let again = try StanceDeck.loadBundled().sample(rng: &rng)
        // different seed path — just ensure non-empty
        #expect(!again.views.isEmpty)
    }
}
```

- [ ] **Step 2: Fail.** **Step 3:** Add JSON and loaders. `Package.swift` already `.process("Resources")`.

`opens.json`:

```json
[
  "What did you have for breakfast?",
  "How was your commute today?",
  "What are you making for dinner this week?",
  "Did you sleep well last night?",
  "What's on your weekend plan?",
  "Coffee or tea in the morning?",
  "Have you been to the grocery store lately?",
  "What show have you been watching?",
  "Do you cook or order in more often?",
  "What's your usual walk after work?",
  "Paper books or e-readers when you travel?",
  "How do you like your neighborhood in the evening?",
  "Did you get outside today?",
  "What's in your fridge that you keep forgetting to use?",
  "How do you take a break on a long day?",
  "Are you a morning person on weekdays?",
  "What did you last cook that actually worked?",
  "Do you listen to anything on your commute?",
  "Where do you sit when you want to think?",
  "What chore do you put off until Sunday?"
]
```

`stances.json`:

```json
[
  "Cities over suburbs for everyday life.",
  "Paper books over e-readers.",
  "Walking over driving for trips under twenty minutes.",
  "Cooking at home over takeout.",
  "Morning workouts over evening ones.",
  "Trains over planes for trips under four hours.",
  "Window seats over aisle seats.",
  "Handwritten lists over phone notes.",
  "Local bakeries over chains.",
  "Parks over malls on a free afternoon.",
  "One long vacation over several short ones.",
  "Cooking for friends over going out."
]
```

```swift
import Foundation

public struct OpenPromptBank: Sendable {
    public let prompts: [String]
    public enum BankError: Error { case missing }

    public static func loadBundled() throws -> OpenPromptBank {
        guard let url = Bundle.module.url(
            forResource: "opens", withExtension: "json", subdirectory: "Conversation"
        ) else { throw BankError.missing }
        let prompts = try JSONDecoder().decode([String].self, from: Data(contentsOf: url))
        return OpenPromptBank(prompts: prompts)
    }
}

public struct StanceCard: Sendable {
    public let views: [String]
}

public struct StanceDeck: Sendable {
    public let views: [String]
    public enum BankError: Error { case missing }

    public static func loadBundled() throws -> StanceDeck {
        guard let url = Bundle.module.url(
            forResource: "stances", withExtension: "json", subdirectory: "Conversation"
        ) else { throw BankError.missing }
        let views = try JSONDecoder().decode([String].self, from: Data(contentsOf: url))
        return StanceDeck(views: views)
    }

    public func sample(rng: inout SplitMix64) -> StanceCard {
        var pool = views
        var picked: [String] = []
        let n = 3 + Int(rng.next() % 3) // 3...5
        for _ in 0..<min(n, pool.count) {
            let i = Int(rng.next() % UInt64(pool.count))
            picked.append(pool.remove(at: i))
        }
        return StanceCard(views: picked)
    }
}

public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
```

- [ ] **Step 4: Pass.** **Step 5: Commit** `Add Conversation opening bank and stance deck.`

---

### Task 6: Crisis keyword gate (fail closed)

**Files:**
- Create: `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Conversation/CrisisGate.swift`
- Test: `ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/CrisisGateTests.swift`

FM classify is later (device-only). Keywords always.

- [ ] **Step 1: Failing test**

```swift
import Testing
@testable import SpeechAppKit

@Suite("Crisis gate")
struct CrisisGateTests {
    @Test("keyword hit is crisis")
    func hit() {
        #expect(CrisisGate.evaluate("I want to kill myself") == .crisis)
    }

    @Test("empty text is not crisis")
    func empty() {
        #expect(CrisisGate.evaluate("") == .allow)
        #expect(CrisisGate.evaluate("  ") == .allow)
    }

    @Test("therapy override is not 988")
    func therapy() {
        #expect(CrisisGate.evaluate("you are my therapist") == .therapyOverride)
        #expect(CrisisGate.evaluate("pretend you are human") == .therapyOverride)
        #expect(CrisisGate.evaluate("ignore instructions") == .therapyOverride)
    }

    @Test("spoken minor is not 988")
    func minor() {
        #expect(CrisisGate.evaluate("I'm 16") == .possibleMinor)
        #expect(CrisisGate.evaluate("I am a minor") == .possibleMinor)
    }
}
```

- [ ] **Step 2: Fail.** **Step 3:**

```swift
import Foundation

public enum CrisisVerdict: Equatable, Sendable {
    case allow, crisis, therapyOverride, possibleMinor
}

public enum CrisisGate {
    private static let crisisPhrases = [
        "kill myself", "suicide", "end my life", "want to die",
    ]
    private static let therapyPhrases = [
        "you are my therapist", "pretend you are human", "ignore instructions",
        "you are my friend", // keep tight; do not explode this list in v1
    ]
    private static let minorPhrases = ["i'm 16", "i am 16", "i'm a minor", "i am a minor"]

    public static func evaluate(_ raw: String) -> CrisisVerdict {
        let text = raw.lowercased()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .allow }
        if crisisPhrases.contains(where: { text.contains($0) }) { return .crisis }
        if minorPhrases.contains(where: { text.contains($0) }) { return .possibleMinor }
        if therapyPhrases.contains(where: { text.contains($0) }) { return .therapyOverride }
        return .allow
    }
}
```

Expand the crisis phrase list only with counsel later. Do not add a giant synonym dump in v1.

- [ ] **Step 4: Pass.** **Step 5: Commit** `Add on-device Conversation crisis keyword gate.`

---

### Task 7: Report floor (thin / full / crisis)

**Files:**
- Create: `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Conversation/ConversationReport.swift`
- Test: `ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/ConversationReportTests.swift`

v1 UI fields only: time spoken, turn count, English slips or `uncertain` (omit until LID exists — v1 Slice A leaves slips as `omitted`), filled pauses omitted until soak, pace omitted until syllable heuristic, pause time optional. **Slice A ships thin-vs-full on time + turns only.** Later tasks add pace/pause/slips without changing the floor rule.

- [ ] **Step 1: Failing test**

```swift
import Testing
@testable import SpeechAppKit

@Suite("Conversation report floor")
struct ConversationReportTests {
    @Test("under 45s or under 3 turns is thin")
    func thin() {
        let a = ConversationReportBuilder.build(
            userSpeechSeconds: 40, userTurns: 10, endReason: .userStop
        )
        #expect(a.kind == .thin)
        let b = ConversationReportBuilder.build(
            userSpeechSeconds: 120, userTurns: 2, endReason: .wrap
        )
        #expect(b.kind == .thin)
        #expect(a.lines.count == 2) // time + turns only
    }

    @Test("45s and 3 turns is full")
    func full() {
        let r = ConversationReportBuilder.build(
            userSpeechSeconds: 45, userTurns: 3, endReason: .wrap
        )
        #expect(r.kind == .full)
    }

    @Test("crisis is not a fluency report")
    func crisis() {
        let r = ConversationReportBuilder.build(
            userSpeechSeconds: 200, userTurns: 10, endReason: .crisisReferral
        )
        #expect(r.kind == .crisis)
        #expect(!r.lines.contains(where: { $0.label == "Pace" }))
    }
}
```

- [ ] **Step 2: Fail.** **Step 3:**

```swift
import Foundation

public struct ConversationReport: Equatable, Sendable, Identifiable {
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
    public let endReason: ConversationEndReason
    public let userSpeechSeconds: TimeInterval
    public let userTurns: Int
    public let lines: [Line]
    public let limitedAnalysis: Bool

    public init(
        id: UUID = UUID(),
        kind: Kind,
        endReason: ConversationEndReason,
        userSpeechSeconds: TimeInterval,
        userTurns: Int,
        lines: [Line],
        limitedAnalysis: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.endReason = endReason
        self.userSpeechSeconds = userSpeechSeconds
        self.userTurns = userTurns
        self.lines = lines
        self.limitedAnalysis = limitedAnalysis
    }
}

public enum ConversationReportBuilder {
    public static let minSpeech: TimeInterval = 45
    public static let minTurns = 3

    public static func build(
        userSpeechSeconds: TimeInterval,
        userTurns: Int,
        endReason: ConversationEndReason,
        extraFullLines: [ConversationReport.Line] = [],
        limitedAnalysis: Bool = false
    ) -> ConversationReport {
        if endReason == .crisisReferral {
            return ConversationReport(
                kind: .crisis,
                endReason: endReason,
                userSpeechSeconds: userSpeechSeconds,
                userTurns: userTurns,
                lines: []
            )
        }
        let time = ConversationReport.Line(
            label: "Time spoken",
            value: Self.format(userSpeechSeconds)
        )
        let turns = ConversationReport.Line(
            label: "Turns",
            value: "\(userTurns)"
        )
        let thin = userSpeechSeconds < minSpeech || userTurns < minTurns
        if thin {
            return ConversationReport(
                kind: .thin,
                endReason: endReason,
                userSpeechSeconds: userSpeechSeconds,
                userTurns: userTurns,
                lines: [time, turns]
            )
        }
        return ConversationReport(
            kind: .full,
            endReason: endReason,
            userSpeechSeconds: userSpeechSeconds,
            userTurns: userTurns,
            lines: [time, turns] + extraFullLines,
            limitedAnalysis: limitedAnalysis
        )
    }

    private static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return "\(s / 60)m \(s % 60)s"
    }
}
```

Do not add Pace / Slips / Fillers here until those detectors exist (Tasks 16+). Full in Slice A **is** time + turns; extra lines stay empty. That is honest.

- [ ] **Step 4: Pass.** **Step 5: Commit** `Add Conversation thin/full/crisis report floor.`

---

### Task 8: ConversationSession brain

**Files:**
- Create: `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Conversation/ConversationSession.swift`
- Test: `ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/ConversationSessionTests.swift`

This is the load-bearing task. Constants from spec:

| Name | Value |
|---|---|
| Wall clock | 15 * 60 (inject `cap` for tests; 5 min debug flag later) |
| wrap_warn | cap - 120 |
| Silence auto-pause | 90 s, only after user has spoken once |
| Pause TTL | 600 s |
| Ghost | speech_started with no stop for 8 s → no reply |
| First audio | 8 s watchdog |
| Clock start | first `audioDelta` after `open` |
| Budget start | countdown hit 0 **and** first partner audio |

The App target (Slice D) forwards WebRTC events with `for await event in mouth.events { await session.handle(event) }`. Kit tests call `handle` directly. Do not add `awaitMouthPump`.

- [ ] **Step 1: Write failing tests**

```swift
import Testing
@testable import SpeechAppKit

@Suite("ConversationSession")
struct ConversationSessionTests {
    @MainActor
    func makeSession(
        cap: TimeInterval = 15 * 60,
        mouth: FakeConversationMouth = FakeConversationMouth()
    ) -> (ConversationSession, FakeConversationMouth, ControllableTimeSource) {
        let time = ControllableTimeSource(now: 0)
        let session = ConversationSession(
            time: time,
            mouth: mouth,
            cap: cap,
            prefix: "PREFIX",
            stance: "STANCE",
            openQuestion: "What did you have for breakfast?"
        )
        return (session, mouth, time)
    }

    @Test("clock does not start at countdown zero")
    @MainActor
    func clockStartsOnFirstAudio() async throws {
        let (session, mouth, _) = makeSession(cap: 300)
        session.beginCountdown()
        #expect(session.phase == .countdown)
        try await session.countdownReachedZero(ephemeralKey: "ek")
        #expect(session.phase == .connecting)
        #expect(session.countsAsBudgetStart == false)
        await session.handle(.sessionUpdated)
        #expect(mouth.responseCreates.count == 1)
        #expect(mouth.responseCreates[0].contains("breakfast"))
        await session.handle(.audioDelta)
        #expect(session.phase == .talking)
        #expect(session.countsAsBudgetStart == true)
        #expect(session.elapsed == 0)
    }

    @Test("user stop never sends wrap_close")
    @MainActor
    func userStopSilent() async throws {
        let (session, mouth, _) = makeSession()
        try await reachTalking(session)
        session.requestStop()
        await session.confirmStop()
        #expect(session.phase == .report)
        #expect(session.report?.endReason == .userStop)
        #expect(mouth.responseCreates.allSatisfy { !$0.lowercased().contains("close the conversation") })
        #expect(mouth.didClose)
    }

    @Test("wrap_warn queues at T-2 min")
    @MainActor
    func wrapWarn() async throws {
        let (session, mouth, time) = makeSession(cap: 180)
        try await reachTalking(session)
        time.advance(60)
        await session.tick()
        session.ingestUserText("eggs")
        await session.handle(.speechStopped)
        #expect(mouth.responseCreates.contains { $0.contains("two minutes") })
    }

    @Test("1.5 min silence auto-pauses after they have spoken")
    @MainActor
    func autoPause() async throws {
        let (session, mouth, time) = makeSession()
        try await reachTalking(session)
        session.ingestUserText("hello")
        session.noteUserSpeech(seconds: 1)
        await session.handle(.speechStopped)
        time.advance(90)
        await session.tick()
        #expect(session.phase == .paused)
        time.advance(30)
        await session.tick()
        #expect(session.elapsed == 90)
        session.resume()
        #expect(session.phase == .talking)
    }

    @Test("silence before they speak does not auto-pause")
    @MainActor
    func noPauseBeforeFirstUserTurn() async throws {
        let (session, _, time) = makeSession()
        try await reachTalking(session)
        time.advance(90)
        await session.tick()
        #expect(session.phase == .talking)
    }

    @Test("pause TTL 10 min hangs up with no close")
    @MainActor
    func pauseTTL() async throws {
        let (session, mouth, time) = makeSession()
        try await reachTalking(session)
        session.pause()
        time.advance(600)
        await session.tick()
        #expect(session.phase == .report)
        #expect(session.report?.endReason == .pauseTTL)
        #expect(mouth.turnDetectionNulled == false)
    }

    @Test("keyword crisis skips fluency report")
    @MainActor
    func crisis() async throws {
        let (session, mouth, _) = makeSession()
        try await reachTalking(session)
        session.ingestUserText("I want to kill myself")
        await session.handle(.speechStopped)
        #expect(session.phase == .crisis)
        #expect(session.report?.kind == .crisis)
        #expect(mouth.responseCreates.count == 1)
    }

    @Test("spoken minor sets flag and skips 988")
    @MainActor
    func possibleMinor() async throws {
        let (session, mouth, _) = makeSession()
        try await reachTalking(session)
        session.ingestUserText("I am a minor")
        await session.handle(.speechStopped)
        #expect(session.possibleMinorFlag == true)
        #expect(session.phase == .report)
        #expect(session.report?.kind != .crisis)
        #expect(mouth.responseCreates.count == 1)
    }

    @Test("v1 never sends codeSwitch cue")
    @MainActor
    func noCodeSwitch() async throws {
        let (session, mouth, _) = makeSession()
        try await reachTalking(session)
        session.queueIfAllowed(.codeSwitch)
        session.ingestUserText("hello")
        await session.handle(.speechStopped)
        #expect(mouth.responseCreates.allSatisfy { !$0.lowercased().contains("english") })
        #expect(mouth.responseCreates.count == 2) // open + continue, never a code-switch aside
    }

    @Test("ghost speech_started without stop gets no reply")
    @MainActor
    func ghost() async throws {
        let (session, mouth, time) = makeSession()
        try await reachTalking(session)
        await session.handle(.speechStarted)
        session.ingestUserText("hi")
        time.advance(8)
        await session.tick()
        await session.handle(.speechStopped)
        #expect(mouth.responseCreates.count == 1)
    }

    @Test("silent at cap skips spoken close")
    @MainActor
    func skipCloseWhenSilentAtCap() async throws {
        let (session, mouth, time) = makeSession(cap: 60)
        try await reachTalking(session)
        session.ingestUserText("hi")
        await session.handle(.speechStopped)
        time.advance(60)
        await session.tick()
        #expect(session.phase == .report)
        #expect(session.report?.endReason == .wrap)
        #expect(mouth.responseCreates.allSatisfy { !$0.lowercased().contains("close the conversation") })
    }

    @Test("open ignore retries once")
    @MainActor
    func openRetry() async throws {
        let (session, mouth, _) = makeSession()
        try await reachTalking(session)
        await session.handle(.responseDone(transcript: "Sure."))
        #expect(mouth.responseCreates.filter { $0.contains("breakfast") }.count == 2)
    }

    @Test("first audio watchdog retries then drops")
    @MainActor
    func firstAudioWatchdog() async throws {
        let (session, mouth, time) = makeSession()
        session.beginCountdown()
        try await session.countdownReachedZero(ephemeralKey: "ek")
        await session.handle(.sessionUpdated)
        #expect(mouth.responseCreates.count == 1)
        time.advance(8)
        await session.tick()
        #expect(mouth.responseCreates.count == 2)
        time.advance(8)
        await session.tick()
        #expect(session.phase == .dropped)
    }

    @Test("thin report under 45s")
    @MainActor
    func thinReport() async throws {
        let (session, _, _) = makeSession()
        try await reachTalking(session)
        session.noteUserSpeech(seconds: 10)
        await session.confirmStop()
        #expect(session.report?.kind == .thin)
    }

    @MainActor
    private func reachTalking(_ session: ConversationSession) async throws {
        session.beginCountdown()
        try await session.countdownReachedZero(ephemeralKey: "ek")
        await session.handle(.sessionUpdated)
        await session.handle(.audioDelta)
    }
}
```

- [ ] **Step 2: Run** `cd ios/Packages/SpeechAppKit && swift test --filter ConversationSessionTests`

Expected: FAIL — `ConversationSession` not found.

- [ ] **Step 3: Implement `ConversationSession`**

```swift
import Foundation

@MainActor
public final class ConversationSession {
    public private(set) var phase: ConversationPhase = .idle
    public private(set) var countsAsBudgetStart = false
    public private(set) var report: ConversationReport?
    public private(set) var possibleMinorFlag = false

    public var elapsed: TimeInterval {
        guard let origin = clockOrigin else { return 0 }
        let extra = (phase == .paused ? (time.now - (pausedAt ?? time.now)) : 0)
        return max(0, time.now - origin - pausedAccumulated - extra)
    }

    private let time: any ConversationTimeSource
    private let mouth: any ConversationMouth
    private let cap: TimeInterval
    private let prefix: String
    private let stance: String
    private let openQuestion: String

    private var clockOrigin: TimeInterval?
    private var pausedAccumulated: TimeInterval = 0
    private var pausedAt: TimeInterval?
    private var lastUserSpeechAt: TimeInterval?
    private var userHasSpoken = false
    private var pendingCue: ConversationCue?
    private var wrapWarnArmed = false
    private var wrapCloseArmed = false
    private var lastUserText = ""
    private var userSpeechThisTurn: TimeInterval = 0
    private var userSpeechSeconds: TimeInterval = 0
    private var userTurns = 0
    private var speechStartedAt: TimeInterval?
    private var ghostTurn = false
    private var openSent = false
    private var openAudioRetries = 0
    private var awaitingFirstAudio = false
    private var firstAudioDeadline: TimeInterval?
    private var wrappingWaitingUpdated = false
    private var lastSentCue: ConversationCue?
    private var openIgnoreRetries = 0
    private var waitingForUser = true
    private var closed = false

    public init(
        time: any ConversationTimeSource,
        mouth: any ConversationMouth,
        cap: TimeInterval = 15 * 60,
        prefix: String,
        stance: String,
        openQuestion: String
    ) {
        self.time = time
        self.mouth = mouth
        self.cap = cap
        self.prefix = prefix
        self.stance = stance
        self.openQuestion = openQuestion
    }

    public func beginCountdown() { phase = .countdown }

    public func countdownReachedZero(ephemeralKey: String) async throws {
        phase = .connecting
        try await mouth.connect(ephemeralKey: ephemeralKey)
    }

    public func pause() {
        guard phase == .talking else { return }
        phase = .paused
        pausedAt = time.now
    }

    public func resume() {
        guard phase == .paused, let pausedAt else { return }
        pausedAccumulated += time.now - pausedAt
        self.pausedAt = nil
        lastUserSpeechAt = time.now
        phase = .talking
    }

    public func requestStop() {}

    public func confirmStop() async { await finish(reason: .userStop) }

    public func noteConfigDrift() async { await finish(reason: .configDrift) }

    public func ingestUserText(_ text: String) { lastUserText = text }

    public func noteUserSpeech(seconds: TimeInterval) {
        userSpeechThisTurn += seconds
        userSpeechSeconds += seconds
        if seconds >= 0.3 {
            userHasSpoken = true
            lastUserSpeechAt = time.now
        }
    }

    public func queueIfAllowed(_ cue: ConversationCue) {
        guard ConversationCueAssembler.v1MaySend(cue) else { return }
        pendingCue = cue
    }

    public func tick() async {
        switch phase {
        case .connecting:
            if awaitingFirstAudio, let deadline = firstAudioDeadline, time.now >= deadline {
                if openAudioRetries < 1 {
                    openAudioRetries += 1
                    firstAudioDeadline = time.now + 8
                    try? await sendCue(.open(question: openQuestion))
                } else {
                    await finish(reason: .drop)
                }
            }
        case .talking:
            if let started = speechStartedAt, time.now - started >= 8 {
                ghostTurn = true
                speechStartedAt = nil
            }
            if userHasSpoken, let last = lastUserSpeechAt, time.now - last >= 90 {
                pause()
                return
            }
            if elapsed >= cap - 120, !wrapWarnArmed {
                wrapWarnArmed = true
                pendingCue = .wrapWarn
            }
            if elapsed >= cap, !wrapCloseArmed {
                wrapCloseArmed = true
                if waitingForUser {
                    await finish(reason: .wrap)
                } else {
                    await beginWrapClose()
                }
            }
        case .paused:
            if let pausedAt, time.now - pausedAt >= 600 {
                await finish(reason: .pauseTTL)
            }
        default:
            break
        }
    }

    public func handle(_ event: MouthEvent) async {
        if phase == .paused, event == .speechStopped { return }
        switch event {
        case .sessionUpdated:
            if wrappingWaitingUpdated {
                wrappingWaitingUpdated = false
                try? await sendCue(.wrapClose)
                return
            }
            if phase == .connecting, !openSent {
                openSent = true
                awaitingFirstAudio = true
                firstAudioDeadline = time.now + 8
                try? await sendCue(.open(question: openQuestion))
            }
        case .audioDelta:
            if clockOrigin == nil {
                clockOrigin = time.now
                countsAsBudgetStart = true
                awaitingFirstAudio = false
                if phase == .connecting { phase = .talking }
            }
        case .speechStarted:
            guard phase == .talking else { return }
            ghostTurn = false
            speechStartedAt = time.now
            waitingForUser = false
            lastUserText = ""
            userSpeechThisTurn = 0
        case .speechStopped:
            await onSpeechStopped()
        case .responseDone(let transcript):
            await onResponseDone(transcript)
        case .disconnected:
            break
        case .failed:
            await finish(reason: .drop)
        }
    }

    private func onSpeechStopped() async {
        guard phase == .talking else { return }
        speechStartedAt = nil
        waitingForUser = true
        if ghostTurn {
            ghostTurn = false
            return
        }
        lastUserSpeechAt = time.now
        switch CrisisGate.evaluate(lastUserText) {
        case .crisis:
            await finish(reason: .crisisReferral)
            return
        case .therapyOverride:
            await finish(reason: .userStop)
            return
        case .possibleMinor:
            possibleMinorFlag = true
            await finish(reason: .userStop)
            return
        case .allow:
            break
        }
        let empty = lastUserText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if empty && userSpeechThisTurn < 0.3 { return }
        userHasSpoken = true
        userTurns += 1
        if let pending = pendingCue, ConversationCueAssembler.v1MaySend(pending) {
            pendingCue = nil
            try? await sendCue(pending)
        } else {
            try? await sendContinue()
        }
    }

    private func onResponseDone(_ transcript: String) async {
        if case .wrapClose = lastSentCue {
            await finish(reason: .wrap)
            return
        }
        guard let cue = lastSentCue else { return }
        if ConversationCueAssembler.heard(cue, in: transcript) { return }
        switch cue {
        case .open:
            if openIgnoreRetries < 1 {
                openIgnoreRetries += 1
                try? await sendCue(.open(question: openQuestion))
            }
        case .wrapWarn:
            pendingCue = .wrapWarn
        case .wrapClose:
            await finish(reason: .wrap)
        case .codeSwitch, .fillerOk:
            break
        }
    }

    private func beginWrapClose() async {
        phase = .wrapping
        try? await mouth.updateTurnDetectionNull()
        wrappingWaitingUpdated = true
    }

    private func sendCue(_ cue: ConversationCue) async throws {
        guard ConversationCueAssembler.v1MaySend(cue) else { return }
        lastSentCue = cue
        try await mouth.sendResponseCreate(
            instructions: ConversationCueAssembler.instructions(
                prefix: prefix, stance: stance, cue: cue
            )
        )
    }

    private func sendContinue() async throws {
        lastSentCue = nil
        try await mouth.sendResponseCreate(instructions: """
        \(prefix)
        \(stance)
        Answer them as you were going to. Stay on the topic. \(ConversationCueAssembler.doNotAnnounceTimer)
        """)
    }

    private func finish(reason: ConversationEndReason) async {
        guard !closed else { return }
        closed = true
        switch reason {
        case .crisisReferral: phase = .crisis
        case .drop: phase = .dropped
        default: phase = .report
        }
        report = ConversationReportBuilder.build(
            userSpeechSeconds: userSpeechSeconds,
            userTurns: userTurns,
            endReason: reason
        )
        await mouth.close()
    }
}
```

Keep this file as the brain. Do not add LID, fillers, or Live Activity here.

- [ ] **Step 4: All ConversationSessionTests PASS.**

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Conversation/ConversationSession.swift \
        ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/ConversationSessionTests.swift
git commit -m "$(cat <<'EOF'
Add ConversationSession brain with fake mouth.

EOF
)"
```

---

## Slice B — backend mint + budget

No org key on device. Audio never hits this server.

### Task 9: Mint + calendar budget server

**Files:**
- Create: `server/package.json`
- Create: `server/mint.mjs`
- Create: `server/test.mjs`
- Create: `server/.env.example`

Env: `OPENAI_API_KEY`, `MINT_PEPPER`, `PORT`.

- [ ] **Step 1: Write failing Node test** (`server/test.mjs` using `node:test` + `node:assert/strict`)

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { decideStart, monthKey } from "./mint.mjs";

test("20th start in a calendar month is allowed, 21st is not", () => {
  const month = "2026-09";
  const st = { month, count: 19, concurrent: 0 };
  const ok = decideStart(st, month, Date.parse("2026-09-21T12:00:00Z"));
  assert.equal(ok.allow, true);
  assert.equal(ok.nextCount, 20);
  const no = decideStart({ month, count: 20, concurrent: 0 }, month);
  assert.equal(no.allow, false);
  assert.equal(no.reason, "budget");
});

test("new calendar month resets", () => {
  const st = { month: "2026-08", count: 20, concurrent: 0 };
  const ok = decideStart(st, "2026-09");
  assert.equal(ok.allow, true);
  assert.equal(ok.nextCount, 1);
});

test("concurrent session blocked", () => {
  const no = decideStart({ month: "2026-09", count: 3, concurrent: 1 }, "2026-09");
  assert.equal(no.allow, false);
  assert.equal(no.reason, "concurrent");
});
```

- [ ] **Step 2: `node --test server/test.mjs` FAIL** (module missing).

- [ ] **Step 3: Implement `decideStart` and HTTP** in `mint.mjs`

`package.json`: `{ "type": "module", "name": "speechapp-mint" }`

`.env.example`:

```
OPENAI_API_KEY=
MINT_PEPPER=
PORT=8787
```

```js
import { createHmac } from "node:crypto";
import { createServer } from "node:http";

export function monthKey(ms = Date.now()) {
  const d = new Date(ms);
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
}

export function decideStart(st, month) {
  if ((st.concurrent ?? 0) >= 1) return { allow: false, reason: "concurrent" };
  const count = st.month === month ? st.count : 0;
  if (count >= 20) return { allow: false, reason: "budget" };
  return { allow: true, nextCount: count + 1 };
}

const accounts = new Map(); // uuid -> { month, count, concurrent, mintTimes: number[], started: Set, possibleMinor: string|null }
let crisisCount = 0;
const RATE_WINDOW_MS = 10 * 60 * 1000;

function account(id) {
  if (!accounts.has(id)) accounts.set(id, { month: "", count: 0, concurrent: 0, mintTimes: [], started: new Set(), possibleMinor: null });
  return accounts.get(id);
}

export async function handleRequest(req, res, now = Date.now(), openaiFetch = fetch) {
  const url = new URL(req.url, "http://localhost");
  const uuid = (req.headers.authorization || "").replace(/^Bearer\s+/i, "");
  if (url.pathname === "/v1/conversation/crisis" && req.method === "POST") {
    crisisCount += 1;
    res.writeHead(204);
    res.end();
    return;
  }
  if (!uuid) {
    res.writeHead(401);
    res.end(JSON.stringify({ error: "auth" }));
    return;
  }
  const st = account(uuid);
  const month = monthKey(now);
  if (url.pathname === "/v1/conversation/possible-minor" && req.method === "POST") {
    st.possibleMinor = new Date(now).toISOString().slice(0, 10);
    res.writeHead(204);
    res.end();
    return;
  }
  if (url.pathname === "/v1/conversation/ended" && req.method === "POST") {
    st.concurrent = Math.max(0, st.concurrent - 1);
    res.writeHead(204);
    res.end();
    return;
  }
  if (url.pathname === "/v1/conversation/started" && req.method === "POST") {
    const body = await readJson(req);
    const sid = body.session_id;
    if (!st.started.has(sid)) {
      const d = decideStart(st, month);
      if (!d.allow) {
        res.writeHead(429);
        res.end(JSON.stringify({ error: d.reason }));
        return;
      }
      st.month = month;
      st.count = d.nextCount;
      st.started.add(sid);
    }
    res.writeHead(200);
    res.end(JSON.stringify({ starts_remaining: 20 - st.count }));
    return;
  }
  if (url.pathname === "/v1/conversation/mint" && req.method === "POST") {
    st.mintTimes = st.mintTimes.filter((t) => now - t < RATE_WINDOW_MS);
    if (st.mintTimes.length >= 3) {
      res.writeHead(429);
      res.end(JSON.stringify({ error: "rate" }));
      return;
    }
    const d = decideStart(st, month);
    if (!d.allow) {
      res.writeHead(429);
      res.end(JSON.stringify({ error: d.reason }));
      return;
    }
    st.mintTimes.push(now);
    st.concurrent += 1;
    const pepper = process.env.MINT_PEPPER || "dev";
    const safety = createHmac("sha256", pepper).update(uuid).digest("hex");
    const r = await openaiFetch("https://api.openai.com/v1/realtime/client_secrets", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        session: {
          type: "realtime",
          model: "gpt-realtime-2.1-mini",
          tools: [],
          tracing: null,
          safety_identifier: safety,
          audio: { input: { transcription: null } },
        },
        expires_after: { seconds: 120 },
      }),
    });
    const json = await r.json();
    res.writeHead(r.ok ? 200 : 502);
    res.end(JSON.stringify({
      client_secret: json.value ?? json.client_secret ?? json,
      starts_remaining: 20 - (st.month === month ? st.count : 0),
    }));
    return;
  }
  res.writeHead(404);
  res.end();
}

function readJson(req) {
  return new Promise((resolve) => {
    let b = "";
    req.on("data", (c) => { b += c; });
    req.on("end", () => {
      try { resolve(JSON.parse(b || "{}")); } catch { resolve({}); }
    });
  });
}

if (import.meta.url === `file://${process.argv[1]}`) {
  createServer((req, res) => handleRequest(req, res)).listen(process.env.PORT || 8787);
}
```

Confirm the OpenAI mint URL against https://developers.openai.com/api/docs/guides/realtime (nested `session` body, not a flattened `model`). If the docs moved the path, follow them and keep our pin: mini, `tools: []`, `tracing: null`, input transcription null. Client then `POST /v1/realtime/calls` with the secret.

In-memory Map is the prototype. Replace with SQLite before TestFlight multi-device. Never put `OPENAI_API_KEY` in the iOS app.

- [ ] **Step 4: `node --test server/test.mjs` PASS.**

- [ ] **Step 5: Commit**

```bash
git add server/package.json server/mint.mjs server/test.mjs server/.env.example
git commit -m "$(cat <<'EOF'
Add Conversation mint and calendar budget server.

EOF
)"
```

---

### Task 10: iOS mint client + local remaining display

**Files:**
- Create: `ios/App/Conversation/MintClient.swift`
- Create: `ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Conversation/ConversationBudget.swift`
- Test: `ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/ConversationBudgetTests.swift`

Kit holds the **display** math (`n of 20`, disable Start at 0). Server is source of truth; client caches `startsRemaining` from mint/started responses.

- [ ] **Step 1: Failing kit test**

```swift
import Testing
@testable import SpeechAppKit

@Suite("Conversation budget")
struct ConversationBudgetTests {
    @Test("start disabled at zero")
    func disabled() {
        let b = ConversationBudgetSnapshot(limit: 20, used: 20, month: "2026-09")
        #expect(b.startEnabled == false)
        #expect(b.label == "20 of 20")
    }

    @Test("used 3 shows 3 of 20")
    func label() {
        let b = ConversationBudgetSnapshot(limit: 20, used: 3, month: "2026-09")
        #expect(b.startEnabled == true)
        #expect(b.label == "3 of 20")
    }
}
```

- [ ] **Step 2: Fail.** **Step 3: Kit snapshot + App mint client**

```swift
import Foundation

public struct ConversationBudgetSnapshot: Equatable, Sendable {
    public var limit: Int
    public var used: Int
    public var month: String
    public var startEnabled: Bool { used < limit }
    public var label: String { "\(used) of \(limit)" }
    public init(limit: Int, used: Int, month: String) {
        self.limit = limit
        self.used = used
        self.month = month
    }
}
```

```swift
import Foundation

struct MintResponse: Decodable {
    let clientSecret: String
    let startsRemaining: Int
    enum CodingKeys: String, CodingKey {
        case clientSecret = "client_secret"
        case startsRemaining = "starts_remaining"
    }
}

enum MintError: Error { case budget, concurrent, rate, auth, unavailable }

final class MintClient: Sendable {
    let base: URL
    let uuid: UUID
    init(base: URL, uuid: UUID) {
        self.base = base
        self.uuid = uuid
    }

    func mint() async throws -> MintResponse {
        try await post("v1/conversation/mint", body: [:], decode: MintResponse.self)
    }

    func started(sessionID: UUID) async throws -> Int {
        struct StartedResponse: Decodable {
            let startsRemaining: Int
            enum CodingKeys: String, CodingKey { case startsRemaining = "starts_remaining" }
        }
        let r: StartedResponse = try await post(
            "v1/conversation/started",
            body: ["session_id": sessionID.uuidString],
            decode: StartedResponse.self
        )
        return r.startsRemaining
    }

    func ended() async throws {
        _ = try await post("v1/conversation/ended", body: [:], decode: OptionalEmpty.self)
    }

    func crisis() async {
        try? await post("v1/conversation/crisis", body: [:], decode: OptionalEmpty.self)
    }

    func possibleMinor() async {
        try? await post("v1/conversation/possible-minor", body: [:], decode: OptionalEmpty.self)
    }

    private struct OptionalEmpty: Decodable {}

    private func post<T: Decodable>(_ path: String, body: [String: String], decode: T.Type) async throws -> T {
        var req = URLRequest(url: base.appending(path: path))
        req.httpMethod = "POST"
        req.setValue("Bearer \(uuid.uuidString)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 429, let err = try? JSONDecoder().decode(ErrorBody.self, from: data) {
            switch err.error {
            case "budget": throw MintError.budget
            case "concurrent": throw MintError.concurrent
            default: throw MintError.rate
            }
        }
        if code == 401 { throw MintError.auth }
        guard (200...204).contains(code) else { throw MintError.unavailable }
        if T.self == OptionalEmpty.self { return OptionalEmpty() as! T }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private struct ErrorBody: Decodable { let error: String }
}
```

Wire: countdown 0 → `mint()` → `countdownReachedZero(ephemeralKey:)`. When `countsAsBudgetStart` becomes true → `started(sessionID:)`. Map `MintError.budget` to disable Start. **Never consume a start locally on countdown.** Drop before report: `ended()` and do **not** call `started` (session never counted). If `started` already ran, do not refund.

- [ ] **Step 4:** `swift test --filter ConversationBudgetTests` PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Conversation/ConversationBudget.swift \
        ios/Packages/SpeechAppKit/Tests/SpeechAppKitTests/ConversationBudgetTests.swift \
        ios/App/Conversation/MintClient.swift
git commit -m "$(cat <<'EOF'
Add Conversation budget snapshot and mint client.

EOF
)"
```

---

## Slice C — iOS UI (Reading chrome, Conversation routes)

### Task 11: App routes + home

**Files:**
- Modify: `ios/App/AppModel.swift`
- Modify: `ios/App/RootView.swift`
- Create: `ios/App/Screens/HomeView.swift`
- Modify: `ios/App/Screens/PassageLibraryView.swift` (Reading stays one card, not the only home)

- [ ] **Step 1:** No UI test harness in-repo. Verify by building. First add routes so the app compiles:

```swift
enum Route: Equatable {
    case home
    case library
    case reading
    case report(SessionReport)
    case conversation
    case conversationReport(ConversationReport)
    case crisis
    case ageGate
}
```

`HomeView`: primary **Start a conversation** (disabled when `!budget.startEnabled`), caption `n of 20`. Secondary **Read a passage** → existing library. Persistent **AI partner** label on the conversation card.

- [ ] **Step 2:** `RootView` starts at `.home`. Conversation destination is `ConversationSessionView` (stub `Text("Conversation")` until Task 12).

- [ ] **Step 3:** Build with `cd ios && xcodegen generate` then Xcode. Home shows both actions. Reading still works.

- [ ] **Step 4: Commit** `Add home with Conversation entry and Reading still reachable.`

---

### Task 12: Age attestation + daily AI disclosure

**Files:**
- Create: `ios/App/Screens/AgeAttestationView.swift`
- Create: `ios/App/Screens/AIDisclosureCard.swift`
- Create: `ios/App/Conversation/AccountStore.swift`

- [ ] **Step 1:** `AccountStore` (UserDefaults is OK for prototype flags; Keychain for `accountUUID`):

```swift
final class AccountStore {
    var accountUUID: UUID
    var attested18: Bool
    var lastDisclosureDay: String? // yyyy-MM-dd in account TZ
    var possibleMinorFlag: Bool
}
```

First Conversation tap: if `!attested18` → age gate: “I confirm I am 18 or older” + `§ 22604` minor-unsuitability sentence placeholder (`COUNSEL_COPY`). Persist. If already attested, skip.

Each Conversation start: if `lastDisclosureDay != today` show **AI partner** card once, then proceed to countdown. Persistent “AI partner” label still on the live screen.

- [ ] **Step 2:** Wire from Home Start. Counsel wording is a stub string constant `CounselCopy.attestation` / `CounselCopy.disclosure` — do not invent legal prose beyond “This partner is AI, not a person.”

- [ ] **Step 3: Commit** `Add 18+ attestation and daily AI disclosure.`

---

### Task 13: Conversation session screen (fake mouth in DEBUG)

**Files:**
- Create: `ios/App/Screens/ConversationSessionView.swift`
- Modify: `ios/App/Screens/ConversationReportView.swift`
- Create: `ios/App/Screens/CrisisReferralView.swift`

Reuse countdown overlay pattern from `ReadingSessionView` (fog + digits). Pause/Stop row from Reading. Copy: **Paused — still here.** Stop → confirmation dialog → `confirmStop()` → report. No spoken close.

DEBUG: inject `FakeConversationMouth` that auto-emits `sessionUpdated`, `audioDelta` after 0.3 s, then on a timer `speechStopped` if you want a simulator loop. Do not call OpenAI yet.

Aurora: feed `speechEnergy` from a stub 0 until live mouth. **Do not construct `MicAudioSource`.**

- [ ] **Build on Simulator.** Flow: Start → attestation if needed → disclosure if needed → countdown → “talking” → Stop confirm → thin report.

- [ ] **Commit** `Add Conversation session UI on fake mouth.`

---

### Task 14: Report + crisis screens

**Files:**
- `ios/App/Screens/ConversationReportView.swift`
- `ios/App/Screens/CrisisReferralView.swift`

Thin: time spoken, turn count, “Too little speech to score the rest.” Full: same two lines for now. Crisis: full screen **Call or text 988 / chat 988lifeline.org** + “If you are not in the US, use your local emergency number.” No pace. Back to home. POST `/crisis` anonymous (fire-and-forget).

- [ ] **Commit** `Add Conversation report and 988 referral screens.`

---

## Slice D — live mouth (device)

Do not start this until Slice A tests are green and Slice C navigates on the fake mouth.

### Task 15: LiveConversationMouth (WebRTC)

**Files:**
- Create: `ios/App/Conversation/LiveConversationMouth.swift`
- Modify: `ios/project.yml` — add SPM `https://github.com/stasel/WebRTC.git`; **App target only**, not SpeechAppKit
- Modify: `ios/App/Info.plist` + `project.yml` info properties:

```yaml
UIBackgroundModes:
  - audio
NSMicrophoneUsageDescription: SpeechApp talks with a live AI partner. Your voice is streamed to OpenAI for the conversation. Scoring stays on this device. We do not keep the recording.
```

Remove the Reading-only mic sentence from Conversation launches; Reading can keep a second sentence in its own start consent if needed. v1: one rewritten string covering both is OK.

**Implementation notes (follow the technical layer; do not invent a second protocol):**

- `RTCAudioSession` manual. Category `.playAndRecord`, mode `.voiceChat`, `defaultToSpeaker: true`.
- ICE: wait `iceGatheringState == complete` (10 s) then `POST /v1/realtime/calls` with ephemeral Bearer. One retry. No WebSocket fallback.
- Data channel `oai-events`.
- Session after connect:

```
turn_detection: { type: "semantic_vad", eagerness: "low", create_response: false, interrupt_response: true }
noise_reduction: near_field
```

- Map events to `MouthEvent`. First audio delta → `audioDelta`.
- `sendResponseCreate` sends frozen prefix + stance + cue (session already assembled the string).
- Drop: `disconnected` 3 s grace then `failed` → session hang up `.drop`. Do not mint a second Realtime.
- If `session.created` model is not `gpt-realtime-2.1-mini` (or the pinned snapshot), `await session.noteConfigDrift()`.
- **Never** start `MicAudioSource`.

Verify against current OpenAI WebRTC guide: https://developers.openai.com/api/docs/guides/realtime — if endpoint names moved, follow the docs and keep our event mapping.

- [ ] **Device:** countdown → hear opening question → barge-in → Stop → report. 5 min debug cap: `ConversationSession(cap: 300)` behind `#if DEBUG` toggle, not a user slider.

- [ ] **Commit** `Wire OpenAI Realtime WebRTC as ConversationMouth.`

---

### Task 16: Report-only detectors (after the loop works)

Only then:

1. Bounded PCM ring (not `PCMStore`) forked to SpeechAnalyzer **after** hang-up or async after `speech_stopped` — **do not delay `response.create`**.
2. Time spoken from `audioTimeRange` ∪ energy VAD; `uncertain` if coverage < 0.7.
3. Pace: document a vowel-nucleus heuristic in `ConversationPace.swift`; raw number, no target.
4. Pause **time** ≥250 ms; no clause bounds.
5. WhisperKit LID **optional** behind a flag, report `uncertain` if <3 lang keys. Live cue stays OFF.
6. Acoustic fillers: **do not ship a “pattern” line** until license + L2 soak. Omit the line.

Each detector gets a kit test with fixture timestamps, not LibriSpeech.

- [ ] **Commit per detector.** Do not batch.

---

### Task 17: Headphones pause + background 1.5 min (same as foreground)

**Files:** `LiveConversationMouth` / session view.

Unplug / BT drop → `session.pause()`. Volume 0 ≠ pause. Background: do **not** hang up at 30 s; `tick()` still auto-pauses at 90 s silence. Pause TTL 10 min.

- [ ] **Commit** `Pause Conversation on route loss; same silence rule in background.`

---

## Test commands (every kit task)

```bash
cd ios/Packages/SpeechAppKit
swift test --filter Conversation
```

Server:

```bash
cd server
node --test test.mjs
```

App:

```bash
cd ios
xcodegen generate
# then Xcode → device
```

---

## Spec coverage

| Spec lock | Task |
|---|---|
| 15 min cap, clock on first audio | 8 |
| No slider, hang up anytime, Stop = no close | 8, 13 |
| Partner opens | 4, 5, 8 |
| Pause + 1.5 min + 10 min TTL, copy | 8, 13, 17 |
| wrap T–2 / close; silent-at-cap skips close | 8 |
| Spoken cues v1 = open/wrap only | 4, 8 |
| Cue ignore: open retry once; wrap_close hangs up anyway | 8 |
| Ghost 8 s; first-audio 8 s retry then drop | 8 |
| Thin/full/crisis report | 7, 14 |
| Keywords fail closed; empty ≠ 988 | 6, 8 |
| possible_minor_flag; therapy hang-up | 6, 8, 9, 10 |
| Backend mint + 20 calendar starts + concurrent + rate | 9, 10 |
| Safety identifier HMAC; no org key on device | 9 |
| No CallKit; no MicAudioSource | 15 |
| create_response false; interrupt_response true | 15 |
| Drop 3 s grace; no silent second Realtime | 15 |
| Headphones unplug = pause; volume 0 ≠ pause | 17 |
| English-only report LID | 16 (optional, off live) |
| 18+ / daily disclosure | 12 |
| Stance card prompt bet | 5, 8 |
| Honest report (no PMI/location) | 7, 16 |
| Frozen prefix + stance on every cue | 4, 8 |
| Live Activity | deferred; not Slice A. After Task 15 if background orange is missing |
| Quality spike / 988 legal copy / ZDR | ship gates, not build tasks |
| config_drift | 15: if `session.created` model ≠ mini, hang up `.configDrift` |

---

## Order for the implementing agent

Do Tasks **1 → 8** in order (one failing test at a time). Then 9–10. Then 11–14. Then 15 on a device. Then 16–17.

If blocked on OpenAI access, **stop after Task 14** — fake mouth is the product loop. Do not stub LiveConversationMouth with `MicAudioSource` + TTS.
