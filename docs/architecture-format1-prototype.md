# Reading — Prototype Architecture

**Format name:** **Reading** (alias Format 1). See `docs/formats.md`.

**Status:** Revised twice after product steer (2026-09-05), then compute placement revised 2026-09-18, then live UI locked to karaoke + skip pills (2026-09-18 follow-along scoping), then **device-hardened** the same day (optimistic live fill + sticky heard trail; false skip-ahead closed). Pass 1–5 iterated caret / presence / skip honesty (see decision log). Pass 6 (**span highlight**, 2026-09-19): sentence/clause wash — still lagged on device. **Pass 7 (aurora presence, 2026-09-19):** drop all live text place-markers; trust = **top aurora** from mic `speechEnergy` + plain serif book passage; ASR + stall + report unchanged. Word occupancy still powers the report only. **Full decision log with reasoning:** `docs/scoping-reading-follow-along.md`. GOP still does **not** consume Apple's transcript. Live mic path stays on-device. Pronunciation scoring is backend-eligible; on-device-only is no longer a product lock.

**Overall verdict:** **GO-IF** — Slice A includes a real live layer (alignment, not pace). "Pronounced poorly" while Apple still heard the intended word waits for Slice B, one word behind, on CPU. Speaking rate stays a **measured, self-referential, never-forced** signal.

---

## Pace verdict (roundtable, 2026-09-05)

**Question:** should a forced pace caret (a second cursor pulling the reader toward a target rate, Monkeytype-style) be a first-class **live** mechanic in Format 1?

**Panel:** SLA/pronunciation pedagogy, clinical SLP (rate-control techniques), cognitive fluency/psycholinguistics (Segalowitz tradition), product/UX. Four independent research passes, different evidence trails, same landing zone.

**Verdict: NO — do not force pace. Measure rate only, and only self-referentially.**

1. **Forcing rate works against the app's own comprehensibility goal.** Munro & Derwing — the same authors already anchoring Format 1's functional-load scoring — directly tested imposed rate on L2 speech twice: slowed passages were rated *more* accented with *no* comprehensibility gain (Munro & Derwing 1998, [doi:10.1111/1467-9922.00038](https://doi.org/10.1111/1467-9922.00038)), and the comprehensibility-optimal rate is curvilinear and *individual* — slightly faster than a speaker's own natural rate, not a fixed population median (Munro & Derwing 2001, [doi:10.1017/s0272263101004016](https://doi.org/10.1017/s0272263101004016)).
2. **Natural rate is a stable individual trait, not a bad habit to correct.** Rate is "a personality constant of remarkable invariance" per speaker (Goldman-Eisler 1961, [doi:10.1177/002383096100400305](https://doi.org/10.1177/002383096100400305)), correlates with temperament (Feldstein 1984, [doi:10.1111/j.1467-6494.1984.tb00352.x](https://doi.org/10.1111/j.1467-6494.1984.tb00352.x)), and a bilingual's L1 rate predicts their L2 rate ([doi:10.1121/1.4793645](https://doi.org/10.1121/1.4793645)) — this is exactly the user's own stated concern, independently confirmed.
3. **Forced rate change plausibly corrupts the GOP signal Format 1 exists to produce.** Forcing faster speech produces measured articulatory undershoot ([doi:10.21437/speechprosody.2010-252](https://doi.org/10.21437/speechprosody.2010-252)); rate/duration mismatch is a known GOP confound serious enough that "Context-aware GOP" was built specifically to correct for it (Shi et al. 2020, [isca-archive.org](https://www.isca-archive.org/interspeech_2020/shi20g_interspeech.pdf)); and one ASR rate-of-speech study found non-natural rates distort the acoustic spectrum in ways that measurably hurt recognition ([ar5iv.org/1506.00799](https://ar5iv.labs.arxiv.org/html/1506.00799)). A pace caret would fight the pipeline it sits on top of.
4. **Forcing pace re-triggers the exact failure mode the primary persona has.** Time pressure has a *direct* accuracy-degrading pathway on fine-motor/precision tasks, separate from the stress it also causes ([doi:10.1037/xhp0001386](https://doi.org/10.1037/xhp0001386)); explicit self-monitoring under pressure ("choking," Baumeister 1984, [doi:10.1037//0022-3514.46.3.610](https://doi.org/10.1037/0022-3514.46.3.610)) de-automatizes normally fluent skills — and dual-task studies found *reducing* self-monitoring reduces disfluency in both fluent and stuttering speakers ([Eichorn et al. 2016](https://www.memphis.edu/clas/pdfs/eichorn_etal_2016_jslhr.pdf)). A live caret is a machine for forcing continuous self-monitoring onto an already-anxious reader.
5. **Where forced pacing genuinely helps articulation, it's a different population and a supervised, individualized technique.** Metrical pacing improves segmental accuracy in apraxia of speech and reduces articulatory-variability in stuttering ([Brendel & Ziegler 2006, doi:10.1080/02687030600965464](https://doi.org/10.1080/02687030600965464); [Zhao et al. 2024, doi:10.1371/journal.pone.0309612](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0309612)) — but only when clinician-set, individualized, and consented to, and unprompted "just slow down" pressure is documented across stuttering-advocacy sources as patronizing and counterproductive ([stutteringhelp.org](https://www.stutteringhelp.org/blog/slow-down-just-take-deep-breath)). Even in dysarthria, where pacing is indicated, one fixed target underperforms individualized ones (Van Nuffelen et al. 2010, [doi:10.1159/000287209](https://doi.org/10.1159/000287209)) — and this app has no clinician in the loop.
6. **The analogy motivating this feature doesn't actually support it.** Monkeytype's own pace caret defaults **off** and every mode is self-referential (your own PB, your own average, or a number you typed yourself) — verified directly from source ([default-config.ts](https://github.com/monkeytypegame/monkeytype/blob/9799c386/frontend/src/ts/constants/default-config.ts), [pace-caret.ts](https://github.com/monkeytypegame/monkeytype/blob/9799c386/frontend/src/ts/test/pace-caret.ts)). It never imposes a platform-defined target. Borrowing the *mechanic* while dropping the *opt-in, self-referential* design is where this idea went wrong.

**What survives:** speech rate stays exactly what `docs/product-spec.md` §4c already scoped it as — a **measured, end-of-passage delivery metric** (Segalowitz's utterance-fluency construct), never a live-forcing mechanic. If it is ever surfaced live, it must be passive (no pulling), self-referential (compared to the user's own recent sessions, never a fixed population target), and opt-in — matching what Monkeytype actually ships, not the forced version this app almost built. That is a post-MVP exploration, not part of this prototype.

**Genuine gap surfaced by the panel, not resolved by "don't force pace":** the primary persona's core symptom is *freezing* — going silent, not just reading slowly. Removing pace-forcing removes a (bad) fix for that but doesn't replace it. See **Stall safety net** below for the mechanism that actually targets freezing without reintroducing rate-forcing.

---

## Correction (the mix-up)

The tuner is **not** “Apple’s transcript in, scores out.”

| Stream | What it sees | What it is for |
|---|---|---|
| **SpeechAnalyzer** | Audio → words + timestamps | Word occupancy for the **report** only. Live UI trust is **mic aurora**, not text tracking |
| **Mic RMS** | PCM energy each chunk | Drives `speechEnergy` → top aurora band (lag-free presence) |
| **GOP (tuner)** | Raw PCM + the **script’s** canonical phones | “You said *ship* according to Apple, but the mouth was closer to *sheep*” |

If GOP were given Apple’s transcript, it would score the already-corrected sentence and miss the product bet (Park 2026: ASR overcorrects most learner errors). Live skip/add does **not** need GOP. Live “said the right word, but badly” **does**.

---

## Three live signals (Monkeytype mapping)

| You do | Monkeytype analogue | How we detect it | When the UI updates | Slice |
|---|---|---|---|---|
| Skip a script word | Missed characters | `TokenAligner` `skip-script` — **only** when a later **unique exact content** word matches (never on `the`/`to`/ambiguous repeats) | **After Stop** on the report | **A** |
| Add a word that isn’t there | Extra characters | `insert-spoken` (hold-not-substitute) | **After Stop** only | **A** |
| Say a different word (`cat` for `dog`) | Incorrect | occupancy hold; report may show swap | **After Stop** only | **A** |
| Say the intended word, but the sound is wrong | No typing analogue | GOP on that word’s PCM slice | ~0.5–1 s after the word (one behind the mouth) | **B** |
| Go silent for too long | No typing analogue | `StallDetector` (VAD timeout) | Live, non-blocking nudge only | **A** |
| Mic hears speech | — | `speechEnergy` from RMS | Top aurora swells immediately | **A** |

Pace is deliberately **not** in this table — see *Pace verdict* above. It is a report-only metric, not a live signal.

**Visual language (locked — Pass 7 aurora presence, 2026-09-19):**
- Live during reading: **top aurora band** reacts to mic loudness (idle shimmer → taller/brighter when loud) + **plain serif book passage** (warm paper, New York–style). No word karaoke, span wash, next-line hint, live skip pills, live extra/substitute, live raw transcript, or live % / rate.
- End report: evaluative marks (skip / extra / substitute) + metrics. Users keep moving forward; they do **not** re-read to “fix” like Monkeytype typing.
- Rationale: any speech-synced place-marker (word or clause) inherits ASR emission lag (~seconds). Trust while speaking must come from lag-free mic energy, not text tracking. See Pass 7 in `docs/scoping-reading-follow-along.md`.

- **Aurora:** Gemini Live–inspired soft ribbons; our teal/indigo palette; Reduce Motion → opacity pulse only.
- **Passage:** continuous serif body; user scrolls; no auto-scroll.
- **Report-only Extra / Substitute / Skip / poor sound (Slice B):** after Stop (or lagged GOP). Shape + weight, not color-only (WCAG 1.4.1).
- Do **not** invite mid-passage re-reads. Evaluative marks appear after Stop.

Apple `transcriptionConfidence` is still **never** a pronunciation mark. A high-confidence `ship` can be a mispronounced `sheep`.

**Every live-path decision and its reasoning** lives in `docs/scoping-reading-follow-along.md`. Do not reintroduce live text place-markers (word karaoke, span wash, dual cursors) without reopening that log.

---

## Pace (measured only, not forced) + stall safety net

No pace caret. No live pulling toward a target rate. Reasoning is in *Pace verdict* above.

**What ships instead:**

- **Speech rate is computed and shown only in the end-of-passage report** — syllables/min for the take, alongside the same take's own skip/extra/substitute counts. It is descriptive, not evaluative: no green/red band, no "you should be faster/slower" copy.
- **If it is ever surfaced live in a later pass, it must be:** passive (never pulls or blocks), self-referential (vs. *this user's* recent-session average, never a fixed population target — Monkeytype's actual default-off, self-referential design, not the forced version this app almost built), and opt-in. Not built for this prototype.
- **`StallDetector` — a narrower, different mechanism for the actual problem pace-forcing was mis-aimed at.** The primary persona's symptom is *freezing* (going silent), not "reading too slowly." A VAD-based silence timeout (e.g. ~4–5s with no speech onset mid-passage) triggers a gentle, dismissible affordance ("Take your time — tap to continue when ready"), never an auto-skip and never a countdown. This targets freezing directly without imposing a rate on speech that *is* happening. Threshold is a v0 guess, not a citation — flagged in Open Questions.
- **Rhythm/stress timing (Field 2005, already in `docs/product-spec.md` line 35) stays a Slice B, post-session metric**, same as before this revision — it is a within-utterance relative-timing measure (which syllables get stressed), not an overall-rate mechanic, and the same signal-corruption logic argues against making it live either.

---

## Struggle-led next passages (Slice A schema, Slice B fuel)

This is Monkeytype **Practice missed / slow words** and the “weak spot” letter boost — not an LLM writing new text. The spec already forbids AI-generated scripts (`docs/product-spec.md` Format 1: fixed curated library).

```
StruggleLedger (on device, scalars only)
  phones[]:     { phone, flBand, missCount, lastSession }
  skipWords[]:  { wordId, count }
  extras[]:     { surface, count }          // optional; extras are less useful to drill
  collocations[]: { id, missCount }          // when GOP/stress flags a chunk
```

**Next passage** = pick from the bundled tagged catalog the item that **covers the most high-FL misses**, then remaining misses, then a new contrast you have not seen. Same scheduler the spec already wanted for spaced drilling (`docs/product-spec.md` §3 spaced-repetition rule) — just with a visible “this reading leans on the sounds you just missed.”

Prototype catalog: **8–12 original short passages**, each tagged with the FL contrasts and phone ids it contains. No model generates prose. If the ledger is empty (session one), pick a balanced default.

---

## Two slices (revised)

| Slice | What ships | Live | After Stop |
|---|---|---|---|
| **A — Shell** | Consent, assets, 3 screens, TokenAligner (hold-not-substitute, unique-content skip-ahead, monotonic caret, n-best vs script), mic `speechEnergy` → aurora, **StallDetector**, FileReplay harness, StruggleLedger over **alignment** events, next-passage picker | Top aurora + plain serif book passage + stall nudge (no live text tracking / karaoke / skip / transcript) | Skip/extra/swap counts; measured speech rate (report-only, self-referential) |
| **B — GOP** | Per-**finalized-word** GOP on **CPU** (SpeechAnalyzer keeps running on system ANE), plus a full-pass report | Previous-word “poor sound” underline | FL-ranked **Easy to catch**; ledger updated with phones |

Slice A without B is already a Monkeytype-shaped reader. It still cannot catch *ship*→*sheep* if Apple wrote `ship`. That remains the honesty test for B.

---

## Locked decisions (updated)

1. **Occupancy.** SpeechAnalyzer (system ANE) **may** run at the same time as **CPU-only** GOP on a **short, already-finalized** PCM slice. Never run GOP on the Neural Engine while SpeechAnalyzer is live. Full-pass GOP after Stop still happens after `finalizeAndFinish` + analyzer release.
2. **A19 is not required.** Target floor after reliability: **iPhone 11 (A13) / iOS 26**, with DictationTranscriber when available and **SFSpeechRecognizer on-device** (`requiresOnDeviceRecognition`) as the broad path. **iPhone X is not this floor** (max iOS 16 — no SpeechAnalyzer). See `docs/scoping-on-device-compatibility.md`. Do not market A18-class as required.
3. **Live UI is top aurora + plain serif book passage.** No live text place-markers. Skip / extra / substitute are report-only. Poor-sound GOP is live-but-lagged in B. No ASR-confidence paint. No live raw transcript. Decision log: `docs/scoping-reading-follow-along.md`.
4. **DictationTranscriber** with `progressiveShortDictation` + `.audioTimeRange` + `.atypicalSpeech` **or** `SpeechTranscriber` + `fastResults` (A/B). Sliding rare-token `contextualStrings` (≤100). N-best `.alternativeTranscriptions` reranked against the script window.
5. **No SpeechDetector in v0.**
6. **TokenAligner** operators: match, substitute, skip-script, insert-spoken, repeat, restart, unmatched. Skip-ahead = exact + unique + content word only. Soft match = current word only (not function words, not ahead). Vanilla global NW forbidden.
7. **GOP joins to words via authored phone lists**, never by trusting Apple’s string. Apple timestamps **may** slice PCM for the per-word GOP window; if that window is garbage, the word is `not-assessed`, not a red chip.
8. **Passages:** original connected prose, ~45–90s, tagged for the scheduler. Hand-authored phones.
9. **Process-and-delete PCM.** Persist word-level scalars + StruggleLedger counts. No embeddings. If GOP runs on a backend, the same rule applies there: score, then delete audio.
10. **Conversation remains product MVP.** This prototype is the diagnostic + drill loop, not a reversal of §5.
11. **No forced pace, ever, in this format.** Rate is measured (report-only, self-referential if surfaced live in a later pass). No caret pulls or blocks the reader. Freezing is handled by `StallDetector`, a silence-timeout nudge, not a rate mechanic — see *Pace verdict*.
12. **Live mic path stays on-device. GOP may leave the phone.** Do not stream the live path through a cloud STT. On-device-only was a publishing convenience, not a user demand (2026-09-18). Word-accurate ASR caret &lt;500ms p99 is **not** the UX bar after Pass 7.
13. **Aurora presence** from mic RMS (`speechEnergy`); word occupancy still powers the report only (2026-09-19 Pass 7). SpanWalk/PassageSpan remain in kit but are not driven for UI. Reasoning in `docs/scoping-reading-follow-along.md` §3, §6 item 8.

---

## Pipeline

```
Live:
  AudioSource → PCMStore
       ├─► SpeechTranscriber or DictationTranscriber (volatile + n-best + time ranges)
       │         └─► TokenAligner (soft@cursor, hold-not-substitute, unique-content skip-ahead, monotonic caret)
       │                        → currentWordID / sticky heardWordIDs (report occupancy only)
       ├─► speechEnergy (RMS) → AuroraPresenceView (live trust; lag-free)
       ├─► StallDetector (VAD silence timeout → gentle nudge, never blocks)
       └─► [Slice B] when a word becomes finalized:
                 GOPScorer.cpuOnly(pcmSlice, canonicalPhones)
                 → lagged “poor sound” mark on that word

Stop:
  finalizeAndFinish → release analyzer
  full-pass GOP (B) + DSP
  report marks (skip / extra / substitute)
  compute speech rate (report-only, vs this user's own recent-session average)
  update StruggleLedger
  pick next Passage by tags
  secureDelete PCM
```

**Accuracy note (2026-09-19):** When Apple finals omit words, unique-content skip-ahead marks them skipped even if the user spoke them. Soft match also equates `ship`/`sheep`. Presence walk does not feed the aligner. Evidence: `docs/audit-occupancy-accuracy-2026-09-19.md`.

Full reasoning for each live rule: `docs/scoping-reading-follow-along.md`.

---

## Metrics

| Metric | Slice | Live? | User-facing |
|---|---|---|---|
| Skip / extra / substitute | A | Yes | Passage paint + report counts |
| Went silent too long | A | Yes (nudge only, non-blocking) | Not scored — a dismissible affordance, never a report metric |
| Speech rate (syll/min) | A | **No — report only, self-referential** | End-of-passage number vs. this user's own recent average; no green/red band |
| Phoneme GOP | B | Lagged, previous word | Easy to catch (not a percent) |
| FL ranking | B | No | Sorts the report and the **next** passage |
| Word stress / rhythm timing | B | No | Report only — never a live rhythm-forcing mechanic (same corruption logic as pace) |
| Accentedness | Never | — | Never |
| ASR confidence | Never | — | Never |

---

## What this does *not* change

- GOP still never scores the ASR string.
- No Azure / ELSA AccuracyScore.
- No LLM-generated passages.
- No live IPA, spectrograms, or 0–100 accent meter.
- Anxiety: live marks are **span wash + mic pulse** (guidance, not a grade), not a native-likeness cop. Keep-going is a next-span hint only. Skip/extra/swap wait until Stop. Poor-sound marks wait one word and stay non-red.
- **No forced pace caret, ever, in this format** (this revision) — rate is measured and self-referential only; freezing is handled by a non-blocking stall nudge, not a rate mechanic.

---

## Open questions

1. `StallDetector` silence-timeout threshold: v0 guess is ~4–5s with no speech onset; needs in-house testing against real hesitation pauses (Section 4's disfluency-location research uses 200–250ms pause thresholds for a different purpose — mid-utterance pausing, not a multi-second stall — so it isn't directly reusable here). Also: should the threshold adapt to the user's own recent pause behavior rather than being fixed?
2. Per-word GOP window: Apple `audioTimeRange` vs a padded PCM slice around it — measure false “poor” on word-boundary errors.
3. Catalog size for a convincing scheduler demo: 8 vs 12 tagged passages.
4. Whether extras (filled pauses, “uhm”) should feed the ledger or be ignored as disfluency (`not-assessed`).
5. **Deferred, not answered by this pass:** does the on-device GOP/alignment pipeline actually degrade at rate extremes the way the general ASR-rate literature suggests (`ar5iv.org/1506.00799`)? If a future pace *indicator* (passive, self-referential) is ever built, this needs direct in-house measurement first — no external source can answer it for this specific pipeline.
6. **Deferred:** is a passive, opt-in, self-referential rate indicator (Monkeytype's actual design) worth building post-MVP, or does surfacing rate at all — even non-forcing — reproduce some of the self-monitoring risk the roundtable flagged? Untested by any source found; would need its own small pilot, not a literature answer.
