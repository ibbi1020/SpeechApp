# Conversation (Format 2) — product shape

**Date:** 2026-09-21  
**Status:** Locked for v1 product understanding. Not a build spec. Technical layer: `docs/superpowers/specs/2026-09-21-conversation-technical-layer-design.md`.  
**Canonical name:** Conversation. Alias: Format 2.

**Home (revised 2026-09-24, prototype):** no format is the hero. Three equal glass rows — Read a passage, Start a conversation, Talk about something. Conversation remains the product’s target behavior; the rows are equal so the prototype can be used. Monologue: `docs/superpowers/specs/2026-09-24-monologue-format-design.md`.

Reading is built. This is the next format: spontaneous talk with an AI partner. That is the app’s target behavior.

---

## v1 promise (one paragraph)

A **15-minute** private English rehearsal with an opinionated AI partner. They talk; the partner talks back. **What the partner speaks in v1:** the opening question, a two-minute warning, and an in-character close if they did not tap Stop. Code-switch repair and filler-permission asides are **report-only** until on-device precision gates pass — the partner does not ask them to retry in English on day one. After hang-up, a written report of what we can actually measure (time, turns, slips marked uncertain when language-id is weak, filled pauses if we heard them, pace as a raw number, pause time). Not a grammar quiz, not hesitation *location*, not progress chips. Crisis is a 988 screen, not a fluency report.

This is a repeatable 15-minute session, not an hours-long ambient companion. Free-talk is the v1 shape because it *is* the target behavior (rehearsed spontaneous speech). Information-gap tasks and Long-style negotiation-of-meaning as a *designed* mechanism wait; a stance card is a prompt bet, not a guarantee the model will disagree.

---

## What it is

A private rehearsal, not a lesson and not a replacement for humans. They talk. The partner talks back. English only. After it ends, a written report — same idea as Reading: readable, skimmable, details in order.

---

## Session

- **Length:** **15 minutes** hard cap. Dev/test may use 5 minutes (same wrap, shorter number). “10–15” is how we talk about it, not a second SKU.
- **No slider.** Hang up anytime. User Stop is a confirmation, then the report — **no** spoken wrap if they tapped Stop.
- **Start:** the partner opens with a real everyday preference/habit question (question-only; no opinion). Opens are taste and daily logistics — not news, politics, trauma, or identity fights. Wall clock starts when first partner audio plays.
- **Shape:** free-flowing, no assigned scene. No topic picker, no Change Topic, no visible stance card.
- **Pause:** pause button. **1.5 minutes of silence auto-pauses** (foreground or background — same rule) and freezes the clock. Resume is the same conversation. **Unplug headphones / drop Bluetooth → pause.** Volume 0 is not pause. Copy: **Paused — still here.** Never “you went quiet.” Abandoned pause: **10 minutes**, then hang up to report, no spoken close (not an idle scold — a forgotten-mic cap).
- **End:** ~2 minutes left, the partner says so. Then they close in character. Then the report. If they never speak after the cap, skip the spoken close and go to the report.
- **Crisis:** 988 referral screen. **Not** a fluency report.

---

## Partner

English-only rehearsal partner (not tutor/therapist). Short turns; disagree on the point when the stance fits; never a preference monologue. Mid-talk `continue` and `wrap_warn` hand the floor once; `open` is question-only; `wrap_close` never asks. Cue priority: wrap_close > wrap_warn > open > continue. Stance card samples **1–2** daily-life views.

v1 enforcement is a sampled **stance card** plus a quality spike (does mini still disagree when the user opposes). That is a ship gate for the mouth, not a runtime guarantee. Sycophancy is unsolved industry-wide; do not treat the prompt as Long’s Interaction Hypothesis.

---

## English only

No first-language on-ramp and no cross-session taper to track. The prompt is English-only. Slips land on the **report** (or `uncertain`).

**v1 does not** have the partner ask them to retry the last bit in English. That spoken repair is the `code_switch` cue, **off** until eval.

**Explain It Another Way** (say the idea three ways) is **not v1**. Live repair is also not the v1 stand-in while it is off.

---

## Live nudges

Not chips, banners, or a second voice. When spoken, they are partner lines, between turns, never mid-sentence. **At most 1–2 heard asides per session** (wrap and open do not count). A cue the model ignores does **not** consume that budget.

v1 **builds** the cue machinery. **Spoken `code_switch` / `filler_ok` stay off** until on-device precision gates pass (accented English). Until then, slips and fillers are report-only.

| Pattern | v1 spoken | Later, after eval |
|---|---|---|
| Opening question | Yes | — |
| Wrap warn / close | Yes (close skipped on user Stop) | — |
| Code-switch | No | Repair: try that in English; messy is ok |
| Repeated fillers (“uh”) | No | Permission: take your time; silence is fine; do **not** name or count “uh” |
| Stalls | Report only | Report only |

Details always wait for the report. Difficulty ramps (harder follow-ups, info-gap tasks) wait.

---

## Report (v1)

Same job as Reading’s report: text, skimmable, specifics in a stable order. Shown after a normal hang-up. **Exception:** crisis → 988 screen, not this report. **Thin report** if they spoke &lt; 45 s or fewer than 3 turns: time spoken + turn count only — no fake grades.

**Include (honest detectors only)**

- Time spoken (flag `uncertain` if coverage is weak)
- Turn count
- English slips — or `uncertain` when language-id is weak
- Filled pauses if they showed up, described as filled pauses, not a disorder or an “uh” count lecture
- Pace as a raw number, **no target**, no implied population norm
- Pause **time** (how much they paused), not pause *location*

**Do not include (v1)**

- Hesitation location (mid-clause vs between thoughts) — no clause segmenter
- Word choice / collocation / grammar / register — no shipped corpus, and Apple ASR will auto-correct many of the errors PMI would need
- Phoneme / accent scores (Reading’s job)
- Vocal variety, interactional competence, coherence
- **“New Best” / “Improved”** (and similar progress chips). Wanted later so trends are obvious without staring at raw numbers. Do not invent population “normal ranges” in the meantime.

---

## Later (not v1)

- Spoken `code_switch` / `filler_ok` asides (after precision gates)
- Explain It Another Way
- Progress labels (New Best, Improved) once a personal baseline exists
- Harder conversation (information-gap tasks) — the actual Long negotiation design
- First-language taper
- Connected-speech drills inside the chat; calibrated slang in the partner
- Collocation / effortful-grammar / register lines (need a named spoken-corpus table + a non-PMI grammar list)
- Hesitation *location* (needs a clause-boundary rule and labels)
- Vocal variety, IC, coherence as user-facing lines
- Daily pushes, AI-initiated sessions

---

## Why these limits

Open-ended talk is the right feeling. Unbounded time is not: cost, context, and a forgotten mic. Lab dialogues and AI-chat homework cluster around **6–20 minutes**; shipped voice tutors are often shorter. Time-per-session is not a proven “more minutes = more learning” lever. Repeatable, same-length sessions are.

English-only matches this user (English on paper, freeze in speech) and the immersion evidence. Live filler coaching must not become “don’t say uh.” Report copy must not claim detectors we have not built.
