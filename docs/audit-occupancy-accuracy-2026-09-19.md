# Audit: Occupancy skip/extra accuracy (session 2026-09-18T23-00-49Z)

**Date:** 2026-09-19  
**Log:** `logs/session-2026-09-18T23-00-49Z.jsonl`  
**Passage:** `ship-sheep-3` (~94 words, ~35s session)  
**Engine:** `speechTranscriber`  
**Scope:** Audit only — no code changes. For a follow-up agent to implement fixes.

---

## Verdict (one paragraph)

**Presence walk did not cause the false skips.** Skip/extra occupancy errors come from **TokenAligner + Apple finals**, mainly **unique-content skip-ahead when ASR omits words from the final stream**, plus a **soft-match hole that treats `ship`↔`sheep` as the same word** (Levenshtein 2 ≤ threshold 2). Equal skip and extra counts on the report are the classic symptom of that desync (missing finals → skip-script leaps; unmatched spoken tokens → insert-spoken extras) — not the presence cursor racing the UI.

---

## What the user saw

- Said words correctly and in order; app still marked misses.
- Skip count ≈ extra count on the session report.

---

## What the log proves

| Signal | Value | Meaning |
|---|---|---|
| `presence_advance` | 41 | Presence walk fired (UI stayed ahead of ASR) |
| `presence_snap` | 25 | ASR catch-up reconciled presence |
| `freezeCount` | 0 | Latency UX goal of presence walk worked |
| `skip` events | 13 word IDs | All tied to **final** ingest leaps, not presence |
| Final caret p50/p99 | ~6.1s / ~9.5s | ASR still batches; unchanged root latency |
| p95 chunk handle | ~10ms | Still not MainActor thrash |

Presence state is **never** passed into `TokenAligner.ingest` / `previewVolatile` ([`ReadingSession.swift`](../ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Session/ReadingSession.swift)). Scoring still uses ASR caret + aligner events only. Presence is paint/scroll only.

---

## Skip inventory (this session)

All 13 skips map to script indices that were **leapfrogged** when a later **exact content** final arrived within lookahead (~4):

| t (s) | Skipped (index → surface) | Next final that leapt | Mechanism |
|---|---|---|---|
| 12.886 | 25 `then`, 26 `at`, 27 `the` | `ship` → idx 28 | `findAhead` after `sheep` |
| 12.888 | 30 `laughs` | `because` → idx 31 | `findAhead` after `and` |
| 12.888 | 33 `two` | `words` → idx 34 | `findAhead` after `the` |
| 26.47 | 66 `a` | `wrong` → idx 67 | `findAhead` after `because` |
| 32.068 | 78 `Practice`, 79 `the` | `short` → idx 80 | `findAhead` |
| 32.073 | 81 `vowel`, 82 `in` | `ship` → idx 83 | `findAhead` |
| 32.077 | 85 `the` | `longer` → idx 86 | `findAhead` |
| 32.083 | 87 `vowel`, 88 `in` | `sheep` → idx 89 | `findAhead` |

**Reading of the user’s “I said it correctly” claim against this table:** between committed finals `sheep`(24) and `ship`(28), Apple never emitted finals for `then` / `at` / `the`. Same pattern for `laughs`, `two`, `Practice`, and the repeated `vowel` / `in` pairs. The aligner then did exactly what §4.5 specifies: treat the next unique content hit as “user moved on” and paint **skip-script**.

That is **not** soft-match at cursor failing on those words — several of the skipped tokens are function words (`the`, `a`, `in`, `at`) or content words that simply **never appeared in the final token stream**.

---

## Why skip count ≈ extra count

Diagnostics JSONL **does not log `insertSpoken` / extras** (only `skip` events). The report still counts both from `TokenAligner` events.

Expected pairing when finals are sparse or noisy:

1. Spoken token does not match cursor → if no unique-content ahead → **`insertSpoken` (extra)**.
2. Later spoken token matches a unique content word ahead → intermediates marked **`skipScript`**.
3. Result: extras and skips rise together even when the human read linearly.

So equal counts support **aligner↔ASR desync**, not “presence invented skips.”

---

## Soft match: separate, real accuracy hole

[`TokenAligner.isSoftMatch`](../ios/Packages/SpeechAppKit/Sources/SpeechAppKit/Alignment/TokenAligner.swift): content words, Levenshtein ≤ 2 for length 5–8.

| Pair | Lev | Soft? |
|---|---|---|
| `ship` / `sheep` | 2 | **Yes** |

This passage family exists to contrast those vowels. Soft occupancy at the **current** word will accept the wrong minimal pair as a match. That can:

- Lock the wrong script word as heard,
- Leave the true next token with nowhere honest to land → **extra**, or
- Later force a leap → **skip**.

**This session’s skip table is dominated by missing finals + findAhead**, not by a logged ship↔sheep soft swap — but soft match is still **unsafe for ship-sheep (and any minimal-pair) passages** and should be treated as a known fidelity gap for the next agent.

Skip-ahead itself remains **exact-only** for content words (by design). Soft is not the leap mechanism here; **omitted ASR finals** are.

---

## Presence walk: consequence check

| Question | Answer |
|---|---|
| Did presence change aligner / report occupancy? | **No** |
| Did presence make false skips? | **No** — skips coincide with final `findAhead` |
| Did presence help latency? | **Yes** — `freezeCount: 0`, 41 advances / 25 snaps |
| Side effect? | Presence can be **8 words ahead** while ASR is frozen, so the UI looks “with you” on words the report later marks skipped if ASR never emits them — **UX honesty gap** (presence ≠ occupancy truth), not a scorer bug |

---

## Root-cause ranking (for next agent)

1. **Primary (this log):** Apple final stream **drops** short / mid words; `findAhead` (lookahead 4, unique exact content) **legally** marks them skipped. Occupancy false-negatives under continuous clear speech.
2. **Secondary (product fidelity):** Soft match allows **`ship`↔`sheep`**, undermining this passage family’s purpose and can inflate skip/extra via desync.
3. **Not implicated:** Presence walk scoring path; MainActor chunk cost; soft match on the specific leap words in the skip table above.
4. **Instrumentation gap:** Log extras / spoken surfaces on `insertSpoken` and spoken surface on skip leaps so the next session can prove ASR omission vs soft confusion without inferring from caret indices alone.

---

## Suggested fix directions (do not implement in this audit)

- Stricter soft match for **minimal-pair / contrast tags** (exact only for `ship`/`sheep` and tagged pairs).
- On Stop (or delayed finalize): **re-align** with full hypothesis / n-best before counting skips, or demote skip pills that only appeared because of interim findAhead when a later full hypothesis recovers the words.
- Log `insertSpoken` + spoken token text next to skips in SessionDiagnostics.
- Optionally: do not promote live skip pills until final confirm, or require 2+ missing tokens before leap (product tradeoff vs recovery).

---

## Cross-links

- Align rules: [`docs/scoping-reading-follow-along.md`](scoping-reading-follow-along.md) §§4.4–4.5, device iteration §6, **§9 accuracy audit**
- Pipeline: [`docs/architecture-format1-prototype.md`](architecture-format1-prototype.md)
- Prior caret-lag diagnosis: session `2026-09-18T22-08-54Z` (latency); this session is occupancy accuracy after presence walk.
