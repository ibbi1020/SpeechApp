# Monologue (Format 3) — hybrid 4/3/2 regimen

**Date:** 2026-09-24  
**Status:** Locked for v1 product understanding. Not a build spec.  
**Canonical name:** Monologue. Alias: Format 3.

Conversation is the product’s target behavior (interactive speech). Reading is the only honest phoneme path. This format is a **repeated familiar-topic monologue under shrinking time ceilings**. It is not a 5–15 minute one-shot talk, and it is not Conversation without a partner.

Locked decisions from the 2026-09-24 requirements pass. This file is the source of truth.

---

## v1 promise (one paragraph)

They get a familiar topic, optional notes, then talk about it three times under 4, then 3, then 2 minute **ceilings**. The topic does not change. There is no named listener and no “tell it again.” Presence is aurora `listen`. After hang-up, a named-index **profile** of what we can actually extract (phonation-time ratio, pause time, pause count, take-to-take overlap, optional raw pace with a spelling-syllable caveat) — take 1 versus take 3 on this sitting. Not a letter grade, not GOP, not a grammar dump. Leftover clock is leftover. Crisis is a 988 screen, not this report.

---

## What it is

Classroom 4/3/2 (Maurice 1983; Nation 1989) ported to a phone: same talk, shrinking time, silent new ears. The phone analogue of De Jong & Perfetti (2011) is a local recorder — computer 4/3/2 still moved fluency without a live partner.

It trains **utterance fluency** (Segalowitz) on one familiar topic, this sitting. Lasting change in that paper needed **returning to the same topic on a later day**, not a new prompt every session.

It is not:

- Interactive speech (Conversation).
- Phonemes / GOP (Reading). A known script is required; open ASR auto-corrects ~82% (Park BEA 2026).
- A CEFR band, composite CAF score, or “Fluency 78 / Accuracy 61.” 4/3/2 is designed to raise fluency at accuracy’s expense (Skehan trade-off; Thai & Boers 2016).
- Discourse-coherence / PREP / narrative-arc scoring. Gap 6 extractors do not exist; shrinking time forces omission, so scoring “full arc” fights the drill. Storytelling-as-rubric stays later, not v1.

---

## Literature → phone (what we kept / changed)

| Classroom mechanic | Phone v1 | Why |
|---|---|---|
| Same talk, three times | Topic does not change. After take 1: “Three minutes.” After take 2: “Two minutes.” Never “same talk,” “repeat,” or “tell it again.” | The repetition is the topic still sitting there. Branding the drill teaches the test. |
| Shrinking time 4 → 3 → 2 | Digital countdown in chrome. **Done** always available; leftover unused. At 0:00, same as Done if they are still talking. | Ceiling, not a quota. Nation: leftover time stays unused, not stuffed with new content. Thai & Boers: shrinking time is load-bearing for the fluency gain. User overrode stepped remaining-time (“about a minute”) in favor of a digital countdown. |
| New silent listener each take | No named listener. No “hasn’t heard this.” Presence = aurora `listen`, same as Reading. | De Jong’s computer 4/3/2 had no partner. Nation’s audience copy would reintroduce “same talk.” |
| Familiar topic | App assigns a prompt from a familiar-topic bank. **Another topic** skips to the next. No composer. | Nation: known language and ideas. Conversation already has no topic picker. |
| Pre-task planning | Optional notes. **I’m ready** (same control as Start). No planning countdown. Empty notes OK. During the take: topic line only. Notes return between takes. | Yuan & Ellis (2003) is **10 min** planning → complexity/fluency, not accuracy. Mehnert (1998) is the 1-minute paper. A forced exam clock before take 1 is not those studies. Full notes on-mic would turn take 1 into Reading. |
| Accuracy enhancement | After take 1: optional **one-line reuse note they write**. App generates no form feedback in v1. | Tran & Saito (2024): delayed metalinguistic CF on one form, human-coded, between day-1 and day-2. Not an LLM grammar dump on Apple text. Regular past did not even move in that study. |
| Across sessions | Tapping Talk silently opens the last prompt if there is one. **Another topic** leaves it. No “same talk again” CTA. | De Jong & Perfetti: lasting fluency needed same-topic return. |

**Do not mash 4/3/2 and Yuan & Ellis into one 5–15 min talk.** That was the pre-lock one-liner. It is not either exercise.

---

## Home (prototype)

No hero. Three equal glass rows, same treatment as today’s Reading row (not a new card type):

1. **Read a passage**
2. **Start a conversation**
3. **Talk about something**

Drop “More to read.” Conversation’s monthly start budget, if shown, is tertiary copy on the Conversation row only.

This equal-row home is a **prototype lock**. It overrides Conversation-as-the-only-block. Conversation remains the product’s target behavior; the rows are equal so the prototype can be used, not so Monologue replaces Conversation.

---

## Session loop

```
home
  → planning (assigned or last prompt)
      ⇄ Another topic (next bank item; does not start a take)
      → I’m ready
          → take 1 live (4:00 ceiling)
          → between (notes + reuse line + “Three minutes.” + I’m ready)
          → take 2 live (3:00)
          → between (notes + reuse line + “Two minutes.” + I’m ready)
          → take 3 live (2:00)
          → report
```

- **I’m ready** starts take *n* with **no 3-2-1**. Aurora goes to `listen`, the take clock starts, they talk.
- **Done** (or 0:00) ends **this take** only.
- **Back** + confirm leaves the **whole regimen** and opens the report (one take is allowed; that report may be thin).
- Take 3 Done (or 0:00) goes **straight to the report**. No fourth interstitial.
- No metrics peek between takes.
- Crisis at any point on-mic → 988 screen, not the report.

---

## Screens

### Planning / between takes (same dark page)

Reading-idle, not a card: `SpeechScreenBackground`, serif prompt as the passage, notes field, chrome **I’m ready**.

- **Skip:** text **Another topic** on this page only. Cycles the bank. Does not live in the take chrome.
- After take 1, the optional reuse line sits with the notes. It stays visible (editable) on the take-2 interstitial so they can use it for takes 2 and 3.
- On-page duration copy is only **“Three minutes.”** / **“Two minutes.”** after the matching take. Do not explain the method.
- Notes are hidden during the take (topic line only) and restored here.

### Live take

- Topic line only (not the notes, not the reuse line).
- Digital countdown in chrome (4:00 / 3:00 / 2:00 remaining).
- Bottom chrome: **Pause**, aurora `listen`, **Done** (the filled primary). Same bar language as Reading / Conversation. No second Stop.
- Aurora does **not** use `connect` or `speak` — there is no agent mouth.
- Silence stays on the tape. Gaps are the measurement.

### Pause

- Manual **Pause**, or a **system interrupt** (phone call, app backgrounded, route loss such as unplug if we already treat that as interrupt in Conversation).
- Clock **freezes**. Recording pauses. A doorbell must not be scored as a silent gap.
- Copy: **Paused.** Never “you went quiet.”
- Resume is the same take. Done is still this take. Back + confirm still ends the regimen.

**Silence does not auto-pause.** Conversation’s 1.5 min silence auto-pause is **wrong** on this format: pause time and pause count *are* the grade.

### Report

Written, skimmable, stable order — same job as Reading / Conversation reports. Dark chrome. Shown after a normal end (take 3, or Back-confirm).

**Exception:** crisis → 988 screen, not this report.

### Crisis

Same as Conversation: halt the regimen, full-screen **Call or text 988 / chat 988lifeline.org**, plus “If you are not in the US, use your local emergency number.” No metrics. Back → home. Anonymous POST `/crisis` (`crisis_referral_events`, no user id, no transcript). Keywords fail closed; Foundation Model timeout fail-open; empty Apple text is not 988. Counsel still owns IASP/geo copy.

Monologue is not a companion chatbot (no partner). It still runs the keyword gate because it is nine minutes of unsupervised speech.

---

## Copy (locked)

| Do | Do not |
|---|---|
| “Three minutes.” / “Two minutes.” | “Same talk,” “repeat,” “tell it again,” “new listener” |
| “Talk about something” (home) | “4/3/2,” “Monologue,” “fluency drill” as a label they have to learn |
| “Another topic” | “Skip this story” / “new prompt” as a test-branded control |
| “I’m ready” / “Done” / “Paused.” | A second Stop next to Done |
| Named indices (PTR, pause time, pause count) | “Fluency 78,” “Accuracy 61,” “Grade B,” CEFR |

---

## Grading — profile, not a score

CAF dimensions trade off. “Better” = first vs last **counting** take on this talk, this sitting. Across weeks = silent same-topic return, not a new CEFR number.

Show **raw per-take numbers**, not a single improvement badge (sandbagging take 1 would otherwise win).

### A take counts

Wall time **≥ 30 s**, excluding paused-clock time. Leftover ceiling is valid: a 90 s take under a 4:00 ceiling **counts**. An 8 s stub does not.

- **Full profile** if at least **two** counting takes: compare the first counting take with the last counting take.
- **Thin report** otherwise: duration + take count only. Copy: too little speech to score the rest. No zeros for PTR / pauses / overlap / pace. No accuracy card they did not earn.

### Ship on the report (honest extractors)

| Metric | Literature operation | How we extract | v1 |
|---|---|---|---|
| Phonation-time ratio | Speech time / wall time (Towell; De Jong) | Union of SpeechAnalyzer `audioTimeRange` / take duration (paused clock excluded). Almost no ASR. | Yes — strongest scalar |
| Pause time | Sum of silences ≥250 ms (de Jong & Bosker 2013) | Existing `ConversationPauseTime`. Duration only, not location. | Yes — raw seconds |
| Pause count | Frequency of ≥250 ms gaps (Suzuki, Kormos & Uchihara 2021: stronger perceived-fluency correlate than duration) | Count the same gaps. Label “silent gaps ≥250 ms,” not “planning breakdowns.” | Yes — count |
| Take-to-take overlap % | Exact n-gram / token duplication (Thai & Boers: 80–91% under shrinking time) | Token overlap on transcripts retained in RAM until the report. High overlap is **expected**, not a fail. | Yes — descriptive, not originality |
| Pace (articulation rate) | Syllables / **phonation** time — not speech rate (syllables / total time) | Existing `ConversationPace` (grapheme vowel-nucleus heuristic). Today’s code is articulation rate, historically easy to mislabel as “speech rate.” | Optional raw number + spelling-syllable caveat |
| Filled pauses | Acoustic uh/um rate (de Jong 2013) | Core ML on waveform. Never Apple text. | After L2 soak only — not v1 UI |

Wall time for PTR and the 30 s floor is **take clock time**, not calendar time: Pause / system interrupt is excluded.

### Do not score on this format

| Metric | Why it is invalid here |
|---|---|
| Composite grade / CEFR / letter | Skehan trade-off. Sawaki composites used human ratings + G-theory, not noisy ASR proxies. |
| GOP / phonemes / accentedness | Open ASR auto-corrects ~82% (Park BEA 2026). GOP needs a known script — Reading only. |
| Grammar / regular past / obligatory-context accuracy | Tran & Saito used human coding of one form. Apple LM restores morphology. |
| Pause location (mid-clause vs boundary) | Needs an AS-unit segmenter. Conversation spec already forbids it. |
| Repairs / pruned speech rate | Need a verbatim transcript. Apple cleans repeats. “Zero repairs” would be an ASR artifact. |
| Discourse coherence / PREP / narrative arc | Gap 6 extractors do not exist. Shrinking time forces omission. |
| Population WPM norms | Spec §4b: individual baseline only. |
| Lexical diversity as “better vocabulary” | 4/3/2 is designed to reuse wording. Falling MTLD across takes is the mechanism, not a fail. |
| English slips / turn count | There are no turns. Language-id is Conversation’s partner-format job. |

### Smallest honest report copy

Per counting take: time spoken, phonation-time ratio, pause time, pause count, overlap % vs the previous counting take if any, optional raw pace with the spelling-syllable caveat.

Phrase as “Take 3 vs take 1: more talking time, fewer long gaps” — never a composite.

---

## Architecture

**Local 4/3/2 recorder. No OpenAI Realtime.** Silent listeners do not need S2S (~$0.35–$0.75 / 15 min mini). The model is not in this loop.

| Piece | Contract |
|---|---|
| Capture | On-device mic. User-only; no partner playback except canned 988. Do **not** start Conversation’s WebRTC / `RTCAudioSession`. Do **not** attach a live model. |
| Scoring | Apple SpeechAnalyzer family + energy VAD, same family as Conversation / Reading. **No SpeechDetector.** Reuse `ConversationPauseTime`, a gap **count** on the same ≥250 ms gaps, `ConversationPace`, phonation union. |
| Transcripts | Keep in RAM until the report is built, then drop. Needed for overlap %. |
| PCM | Sequential **process-and-delete per take**. Do not hold three PCM buffers until the end (milestone-snippet risk). |
| Identity | **No speaker embeddings.** Take comparison is token overlap on text, not a voiceprint (BIPA). |
| Crisis | Same on-device keyword list as Conversation, on volatile ∪ final, every take. |
| Backend | Anonymous `crisis_referral_events` only. No Realtime mint. Monologue does not consume the 20 Conversation starts / month. |
| Prompt bank | Familiar-topic strings, bundled. Conversation’s `OpenPromptBank` / `opens.json` is an acceptable starting bank (already screened). No user composer. Persist **last prompt id** locally for silent return. Notes are session-ephemeral. |

`idle (planning) → take ⇄ paused → between → take → … → report | crisis`

ANE: at most one live SpeechAnalyzer. No S2S contention.

SB 243 companion-chatbot duties (per-start AI disclosure, stance card) **do not apply** — there is no chatbot. Account-level 18+ attestation still does.

---

## Later (not v1)

- Generated form feedback / Tran-style delayed CF on a coded form
- Filled-pause line (after L2 soak)
- Storytelling / PREP / narrative-arc rubric (fights shrinking time if scored)
- Gap 6 discourse-coherence extractors
- “Understood?”, collocation/register, GOP, vocal variety
- Constant-time 3/3/3 A/B (VUB N=40 sometimes wins overall; do not brand-confuse v1)
- Named listener / face
- Forced planning countdown
- Daily second loop next to Conversation (cadence: prefer 1–3 regimens/week, same-topic return)

---

## Why these limits

4/3/2 is a specific exercise. A long one-shot talk is Yuan-shaped time-on-task without the shrinking-time mechanism Thai & Boers found to be load-bearing. A racing fill-to-zero quota fights Nation’s leftover-time instruction. An LLM accuracy card scores Apple’s language model. A composite grade hides the trade-off this regimen exists to produce. Transfer from 4/3/2 is to **another monologue on the same topic**, not to Conversation’s interactive job (`literature-review.md` §4: drill-to-spontaneous-speech transfer is the single biggest risk for drill-based design).

---

## Sources

Nation 1989; Maurice 1983; Yuan & Ellis 2003 (10 min planning); Mehnert 1998 (1 min — do not cite as Yuan & Ellis); Thai & Boers 2016; De Jong & Perfetti 2011; Tran & Saito 2024; Skehan 2009; Suzuki, Kormos & Uchihara 2021; Park BEA 2026; de Jong & Bosker 2013; Segalowitz 2010.

In-repo: `docs/product-spec.md` §2/§4c/§5; `docs/formats.md`; `docs/aurora-pill.md`; Conversation product shape `2026-09-21-conversation-format-design.md`; Conversation technical layer `2026-09-21-conversation-technical-layer-design.md`; `research/literature-review.md` §4.
