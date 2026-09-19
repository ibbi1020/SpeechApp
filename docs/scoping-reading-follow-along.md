# Reading live follow-along — approach & decision log

**Format:** **Reading** (alias Format 1). See `docs/formats.md`.  
**Status:** Shipped Slice A path as of 2026-09-18, then iterated the same day on device feedback (optimistic UI → false-skip fix).  
**Canonical for:** how live passage reading works technically and in UI, and **why** each rule exists.  
**Related:** `docs/architecture-format1-prototype.md` (broader Slice A/B), `docs/product-spec.md` (product frame), this file’s earlier scoping roundtable (panel YELLOW / GO-IF).

---

## 1. What we are optimizing for

| Priority | Meaning |
|---|---|
| **1. Experience** | Quiet book reading + lag-free proof the mic hears you; never grades mid-flow; never teleports through unread lines. |
| **2. Trust** | Aurora energy means “I hear your voice,” never “you said this word correctly.” Park 2026: ASR overcorrects L2 ~82% — occupancy ≠ pronunciation. |
| **3. Latency** | Live presence follows mic RMS (`speechEnergy`) at chunk rate — not ASR word emission. Occupancy may lag; that is OK for the report. |
| **4. Occupancy accuracy** | Report marks land on the intended script word. Secondary to experience in the live path. |

GOP / phoneme scoring is **out of scope** for this path (Slice B, stubbed).

---

## 2. Technical approach (pipeline)

```
Mic PCM
  → SpeechTranscriber (preferred) or DictationTranscriber (+ atypicalSpeech)
       + prepareToAnalyze preheat
       + sliding contextualStrings ≤100 (Dictation only; SpeechTranscriber does not consume them)
       + alternativeTranscriptions → rerank vs upcoming script window
  → TokenAligner
       volatile: previewVolatile → provisional matches / unique-content skip-ahead
       final:   ingest → match | unique-content skip-ahead | insert-spoken (hold)
  → ReadingSession (Observable)
       word occupancy (report) + sticky heard IDs
       mic RMS → speechEnergy (aurora)
       stall detector
  → ReadingSessionView: top AuroraPresenceView + plain serif BookPassageText
```


**Engines (A/B, measure then lock):**

| Arm | Why it exists |
|---|---|
| `SpeechTranscriber` + `fastResults` / volatiles | Newer AM; better latency/accuracy claim (WWDC25-277). **No** `contextualStrings`. |
| `DictationTranscriber` + `.atypicalSpeech` + context | Vocab bias toward the passage; better for rare script words. Legacy AM. |
| SFSpeechRecognizer on-device | Floor for older / unsupported chips. |

**Reasoning:** Do not pick the engine in a meeting. Availability probe + `EnginePreference` from the Availability screen; device data decides the lock.

**Instrumentation:** `SpokenToken` carries `audioTimeRange`; session logs volatile vs final spoken→caret latency and prints p99 on Stop. Device p99 remains a human gate; file-replay harness gates occupancy via `ScriptedTranscriptEngine` + `ReadingSession.start`.

---

## 3. UI approach (what the user sees)

### Live presence (Pass 7 — aurora + book passage)

| Element | Look | Meaning |
|---|---|---|
| **Aurora band** | Soft teal/indigo ribbons under nav; idle shimmer when quiet; taller/brighter when loud | Mic is hearing volume/shape of speech (companionship, not a grade) |
| **Book passage** | Continuous New York–style serif on warm paper; no wash, chips, or highlight | Eyes only — user reads; app does not claim a place in the text |
| **Listening caption** | Optional “Listening” when mic energy is hot | Confirms live session without positional claim |
| **Stall nudge** | Bottom banner | Permission-giving pause — unchanged |

Word karaoke, span highlight, presence/span walk UI, keep-going hints, and live skip pills are **retired**. Skip / extra / swap stay on the **report** after Stop. `PassageSpan` / `SpanWalk` remain in the kit as unused-for-UI code this pass.

### Chrome rules

- **No live raw transcript** — it read as a live substitute grade.
- **No live text place-markers** — no span wash, word caret, or next-line hint paint.
- **No live extra / swap / skip paint** — report-only after Stop.
- **Aurora respects Reduce Motion** — static soft glow + opacity pulse only.
- **VoiceOver** — “Listening, voice level …” when live; passage is selectable plain text.
- **Stall nudge** — permission-giving (“Take your time”), never a countdown.
- **User scrolls** — no auto-scroll chasing a caret.

### Copy stance

Live copy is presence-only (“Listening” / “Ready when you are”). Never “correct” / “wrong” / “on this line.”

---

## 4. Decision log (exact reasoning)

Every live-path decision below was made or hardened on 2026-09-18. **Do not reverse without re-checking the reasoning.**

### 4.1 On-device karaoke, never cloud caret

- **Decision:** Live follow-along stays on-device (SpeechAnalyzer family).
- **Reasoning:** Cloud streaming STT P90 *emission* is already ~535–597ms before cellular. A &lt;500ms p99 bar cannot survive a network hop. Experience is a latency problem, not a model-size problem.

### 4.2 Constrained optimism (not Monkeytype undo)

- **Decision:** Advance on volatile script match; **never rewind** the caret; no live backspace metaphor.
- **Reasoning:** Speaking has no undo. Finalize jump-back feels like a false-negative grade to anxious L2 users (PM + Designer). Staff Eng “expected rollback” was explicitly rejected. Google Read Along optimized against false “you’re wrong.”

### 4.3 Hold, don’t substitute

- **Decision:** Off-script final → `insert-spoken`; do **not** advance `scriptCursor` by stealing the current script word.
- **Reasoning:** Greedy substitute desynced the caret one bad 1-best at a time. Holding keeps occupancy honest; extras appear on the report.

### 4.4 Soft match — at cursor only, content words only

- **Decision:** Soft / stem near-miss matching applies to the **current** script word. Function words (`the`, `to`, `a`, …) require **exact** match. Soft is **not** used for skip-ahead.
- **Reasoning:** Apple near-misses (`tree`/`three`, clipped stems) are common and should advance the caret. Soft-matching *ahead* or soft-matching function words caused false locks and leaps. Experience wants forgiveness on the word you’re on, not fuzzy teleportation.

### 4.5 Skip-ahead only for unique content words (exact)

- **Decision:** Jump forward (and paint skip pills) only when the spoken token is an **exact** match for a **content** word that appears **exactly once** in the lookahead window (~4). Never on function words. Never when the token is ambiguous (e.g. two `light`s).
- **Reasoning (device bug, 2026-09-18):** ASR often re-emits common words (`the`, `to`) while the user is still on an earlier word. The old “first match in lookahead” rule treated that as a skip and jumped the caret through unread lines. That is a functional false-skip, not a UI nit. Unique content words (`fox`, `brown`) remain a safe recovery when the user truly moves on.

### 4.6 Restart only from script word 0 (exact)

- **Decision:** Restart only if the spoken token exactly equals the first script word and cursor has advanced.
- **Reasoning:** Soft “restart within first 3 words” leapt the caret to mid-passage near-matches (e.g. matching a later `light`). False leaps feel identical to false skips.

### 4.7 Volatile jump uses the same unique-content rule

- **Decision:** `previewVolatile` may provisional-skip only under the same unique-content exact rule as finals.
- **Reasoning:** Volatile is what the user *sees*. If volatile leapt on `the`, the UI teleported before finals even arrived. Prefix-stripping of cumulative hypotheses is **exact-only** so soft strip cannot eat real words and desync the stream.

### 4.8 Monotonic caret

- **Decision:** `monotonicWordID` never moves the live caret backward.
- **Reasoning:** Same as freeze-not-rewind. ASR hypothesis flicker must not yank the eye back.

### 4.9 Sticky heard trail (optimistic success)

- **Decision:** Once a word is provisionally or finally heard, it stays painted for the session (`heardWordIDs`).
- **Reasoning:** Clearing provisional tint when finals arrived made matched words “un-succeed.” Optimistic success patterns keep the trail; flicker must not erase progress.

### 4.10 Mic-driven progressive fill

- **Decision:** While RMS shows speech on the current word, fill the pill L→R on an estimated syllable duration **before** ASR returns (cap ~0.92 so ASR lock-in still feels like commit). **Superseded for continuous speech by §4.18 presence walk** (fill may reach 1.0 on the presence cursor and walk ahead).
- **Reasoning:** Apple first-volatile is often 300–500ms. Waiting for ASR to paint anything made the UI feel dead. Respond-on-input-onset (Apple HIG / WWDC fluid interfaces): feedback during the act, not after confirmation.

### 4.18 Presence walk (UI only, 2026-09-19)

- **Decision:** A **presence cursor** may walk ahead of ASR on sustained speech (syllable clock, max 8 words ahead). Trail paint is lighter than heard. ASR `currentWordID` + `TokenAligner` remain occupancy truth for sticky heard, skips, extras, and the report. Presence never commits heard.
- **Reasoning:** Session logs showed multi-second ASR final batches; fill capped on one word left the UI frozen. Presence keeps “with you” without lying in the score.
- **Accuracy note:** See [`docs/audit-occupancy-accuracy-2026-09-19.md`](audit-occupancy-accuracy-2026-09-19.md) — presence did **not** cause false skips in `session-2026-09-18T23-00-49Z`.

### 4.11 Keep-going is a hint, not a caret move

- **Decision:** If speech continues ~1.2s / fill ≥0.85 without lock-in, show copy + dashed outline on the **next** word. Caret stays on the stuck word. Scroll follows caret only.
- **Reasoning:** First iteration *moved* the caret to the next word to make “say the next word” explicit. That felt like another false skip. Experience needs an escape hatch without lying about position. Hint = affordance; caret = truth.

### 4.12 Live skip pills only; extra/swap after Stop

- **Decision:** Live evaluative paint is skip pills only. Extra / substitute on the report.
- **Reasoning:** Live extra/swap reads as a cop mid-sentence. Skip pills are occupancy guidance when a *real* unique-content ahead match fires. Spec tables that still say “live skip/extra/swap” are stale — this lock wins.

### 4.13 No live transcript

- **Decision:** Hide `volatileHint` from the reading surface.
- **Reasoning:** Raw ASR under the passage is a live substitute mark by another name.

### 4.14 Drop underdamped spring; rebuild as chips not one AttributedString

- **Decision:** `SpeechMotion.follow` = 80ms easeOut; passage rendered as per-word chips in a flow layout.
- **Reasoning:** 0.28s underdamped spring + full `AttributedString` rebuild impersonated engine lag and amplified flicker. Instant/near-instant paint matches optimistic UI.

### 4.15 Sliding context ≤100, not n-gram dump

- **Decision:** Upcoming ~40 unigrams + a few content bigrams; cap 100; refresh as cursor moves.
- **Reasoning:** Apple prefers short phrases; dumping all bigrams/trigrams then truncating wasted the bias budget on junk.

### 4.16 N-best rerank vs script

- **Decision:** Prefer the alternative surface list with best occupancy on the upcoming window.
- **Reasoning:** 1-best is often wrong for L2; script is known — use it.

### 4.17 Preheat `prepareToAnalyze`

- **Decision:** Warm analyzer on Availability / before Start.
- **Reasoning:** Cold start burns the 500ms budget before the first volatile.

---

## 5. Explicitly rejected

| Idea | Why rejected |
|---|---|
| Cloud STT for caret | Misses p99 bar before RTT |
| Train a custom AM | Out of scope; Apple knobs unused first |
| Live extra/swap / transcript | Shame / false grade mid-flow |
| Forced pace caret | Literature + persona (see architecture pace verdict) |
| Soft skip-ahead / function-word skip | Caused multi-line false skips on device |
| Keep-going caret steal | Felt like teleportation |
| Monkeytype-style rewind | Speaking has no backspace |

---

## 6. Device iteration log (2026-09-18)

1. **Scoping GO-IF** — instrument, preheat, context, hold-not-substitute, chrome, n-best, engine A/B, harness, skip pills.
2. **“Feels better functionally but not instant”** — added mic fill, sticky heard trail, stronger success paint (optimistic UI).
3. **“Stuck on words”** — loosened soft match; added keep-going (initially moved caret).
4. **“Skips lines I didn’t skip; caret unnatural”** — root-caused false skip-ahead on common/ambiguous ASR tokens + caret steal; **fixed** with unique-content exact skip rule, safer restart, hint-only keep-going.
5. **(2026-09-19) Presence walk** — UI cursor walks ahead of ASR on sustained speech; occupancy truth unchanged. Latency freezes cleared in follow-up log (`freezeCount: 0`).
6. **(2026-09-19) Occupancy accuracy regression report** — user still saw false skips/extras with equal counts after presence walk. **Audit:** not caused by presence; caused by ASR finals omitting words + `findAhead` skip-script, plus soft `ship`↔`sheep`. Full write-up: [`docs/audit-occupancy-accuracy-2026-09-19.md`](audit-occupancy-accuracy-2026-09-19.md).
7. **(2026-09-19) Pass 6 — span highlight** — Retire word karaoke + word presence walk as the live metaphor. Live place-marker is **sentence/clause** (`PassageSpan` / `SpanWalk`): mic pulse on the current span, max **one** span ahead of occupancy, next-span hint, stall nudge unchanged. Skip/extra/swap report-only. Reason: measured ASR spoken→caret lag (~3–9s) made a mouth-adjacent word carrot feel broken; coarser grain keeps “with you” without fighting emission physics. Dual cursors rejected (one live index only).
8. **(2026-09-19) Pass 7 — aurora presence** — Device showed Pass 6 still lags (ASR emission physics unchanged at coarser grain). Drop **all** live text place-markers. Trust while speaking = **top aurora** driven by `speechEnergy` (mic RMS, chunk-rate). Passage = plain serif book text. ASR + stall + report unchanged; SpanWalk not driven for UI. Inspired by Gemini Live–style energy bands (adapt teal/indigo aurora, not a brand clone).
9. **(2026-09-19) Pass 8 — stop drain + registration health** — Stop means **mic off**, not “cut the pipeline”: finalize ASR while the results task still drains late finals (was cancelling results *before* finalize). On Stop also commit provisional + sticky-heard trail before remainder skips. Live caption: **Keeping up** / **falling behind** from occupancy advance vs speech (not aurora). Soft match blocks ship↔sheep; ɪ-i contrast passages use exact occupancy.

---

## 7. Success metrics (internal)

- Felt liveness: mic → aurora amplitude (not ASR word/span caret p99 as the UX bar).
- Occupancy accuracy for the **report** (match / skip / extra).
- False-skip rate on the report (target → ~0 for linear reads of unique-content skips).
- Session completion.

---

## 8. Code map

| Concern | Primary files |
|---|---|
| Engine / timestamps / n-best / preheat | `LiveTranscriptionEngine.swift`, `TranscriptionEngine.swift` |
| Align / soft / skip / hold / volatile | `TokenAligner.swift` |
| Session / speechEnergy / stall / report | `ReadingSession.swift` |
| Span split (kit only; UI unused Pass 7) | `PassageSpan.swift`, `Passage.swift` |
| Span walk (kit only; UI unused Pass 7) | `SpanWalk.swift` |
| Live UI (aurora + book) | `ReadingSessionView.swift`, `AuroraPresenceView.swift`, `SpeechChrome.swift` |
| Occupancy harness | `ReadingSessionIntegrationTests.swift`, `ScriptedTranscriptEngine` |
| Occupancy accuracy audit (2026-09-19) | `docs/audit-occupancy-accuracy-2026-09-19.md` |

---

## 9. Occupancy accuracy audit (2026-09-19)

**Question:** After presence walk, are false skips a consequence of the racing UI, or soft match / aligner?

**Answer:** **Aligner + ASR finals — not presence.** Soft match is a secondary fidelity gap (`ship`/`sheep`). Details and skip table: [`audit-occupancy-accuracy-2026-09-19.md`](audit-occupancy-accuracy-2026-09-19.md).

## 10. Sources

- Panel scoping 2026-09-18 (Staff Eng, PM, Designer, Data/ML, QA) — freeze not rewind; no cloud caret.
- Apple SpeechAnalyzer / AnalysisContext / SpeechTranscriber (WWDC25-277).
- CHI 2023 interim caption flicker; Google Read Along on-device ML design insights; Park 2026 ASR overcorrection.
- Device QA same day: false skip-ahead on function words; caret steal from keep-going.
- Occupancy accuracy audit 2026-09-19: `docs/audit-occupancy-accuracy-2026-09-19.md` (presence not implicated; ASR omission + findAhead; soft ship/sheep).
