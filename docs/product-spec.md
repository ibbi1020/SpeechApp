# Product Spec — Working Document

**Status:** Living document. This captures decisions made during the scoping conversation following `research/literature-review.md` and `research/accessibility-neurodivergence-review.md`. Every design decision below is either directly grounded in a cited finding from those documents, or explicitly flagged as an inference/assumption where the literature doesn't directly test the exact mechanic. Nothing here is final until noted otherwise — this is a running log to keep the back-and-forth conversation anchored, not a locked spec.

**Format names:** **Reading**, **Conversation**, **Monologue** (aliases Format 1/2/3). Glossary: `docs/formats.md`.

---

## 0. Positioning & Evidentiary Standard (non-negotiable)

This is being built and marketed as an evidence-backed product, not a hastily-coded app that bundles a plethora of generic speaking exercises and claims it "helps you speak better English." The pitch to users and the internal design discipline are the same claim: every activity, format, and metric in this document exists because a specific, cited finding in `research/literature-review.md` or `research/accessibility-neurodivergence-review.md` supports it — not because it's a common feature in adjacent apps, not because it sounds plausible, and not because it's easy to build. Where the literature doesn't directly test something, that gap is stated explicitly (see the Status line below) rather than papered over with a plausible-sounding feature.

Concretely, this means:
- **No feature ships without a real citation trail.** This has been the working rule since the first version of this document; this section makes it an explicit product-identity claim, not just an internal habit.
- **Marketing and in-app copy are held to the same evidentiary bar as the product decisions.** No claims the literature doesn't actually support — e.g., no "eliminate your accent," no invented percentage-improvement numbers, no borrowing an unverified vendor stat (`literature-review.md` §7 already flags several such claims — ELSA's 93.88% figure, various churn/retention benchmarks — as marketing claims, not peer-reviewed data, and this app should not add its own version of that pattern).
- **Fewer, better-evidenced activities beat a large activity catalog.** The goal is the shortest evidence-backed path from A (can't speak comfortably) to B (intelligible, confident speech) — not maximum feature surface area. This is the same reasoning already worked out in §5 (why the app stays at 3 formats rather than fragmenting into more, and why MVP sequencing was decided on "does this actually move someone toward the goal," not on ease-of-build alone).
- **This standard is falsifiable, deliberately.** If a proposed feature can't be tied to a citation, or if new evidence contradicts an existing "resolved" decision, the decision changes — see §4c Gaps 2 and 3, both of which were downgraded from a clean RESOLVED once the audit found the evidence didn't hold up. That correction mechanism *is* the product's integrity, not a failure of process.

## 1. Product Boundary

- **Not** a from-scratch English-learning app. Target user already has functional written/grammatical English competence (schooling-level), gained through traditional instruction.
- **Primary target persona:** someone who is fluent/competent on paper but freezes, hesitates, or lacks confidence speaking in real time — the "input-output asymmetry" / passive-vs-active-vocabulary gap, not a vocabulary/grammar deficit. (Supported by Section 1's finding that classroom-only instruction produces ~no oral-fluency gain — Freed, Segalowitz & Dewey 2004 — and independently corroborated by real-world learner self-reports gathered in this conversation, where "I understand English but can't speak it" was the single most repeated complaint found.)
- Goal framing: **intelligibility and confidence**, not accent elimination or native-likeness. (Section 6, Cross-Cutting Finding #2 — this is both the evidence-backed target and the ethically safer one, given the active scholarly critique of "accent-altering technology.")
- A from-scratch-English module is explicitly out of scope for now, but not ruled out as a future addition.

## 2. Core Activity Formats

Canonical names (use these; numbers are aliases only — full glossary in `docs/formats.md`):

| Name | Alias | One-liner |
|---|---|---|
| **Reading** | Format 1 | Known-passage read-aloud (connected sentences) for pronunciation / diagnosis |
| **Conversation** | Format 2 | 15 min AI rehearsal partner — the product MVP |
| **Monologue** | Format 3 | Familiar topic, optional notes, same talk 4 → 3 → 2 min |

Three formats were proposed by the user and evaluated against the literature. A fourth category — barrier-derived modifiers/mechanics — apply across formats rather than standing alone.

### Reading — Scripted read-aloud (diagnostic/pronunciation)
- **Status:** Concept confirmed as necessary; architecture not yet finalized (next up).
- **Why it matters more than "just diagnostic":** Section 7 documents that modern ASR auto-corrects learner mispronunciations to the intended word in 82% of cases on open speech — meaning **phoneme-level pronunciation feedback is only reliably possible against a known target script.** This makes Reading the sole technically credible path to the app's original pronunciation/enunciation goal, not an optional add-on.
- **Positioning decision:** soft-recommended onboarding/calibration step, not a hard gate in front of Conversation and Monologue.
- **What it produces:** phoneme-level GOP scores weighted by functional load (Munro & Derwing 2006); stress/rhythm placement accuracy (Field 2005); precise, comparable-over-time timing/pause data (only possible because content is fixed); a rough proficiency-band estimate.

#### Reading — Technical architecture (hybrid: live on-device, scoring backend-eligible)
- **Script source:** fixed, curated library (not AI-generated), deliberately designed to hit known high-functional-load contrasts. Coverage deliberately includes word-stress/rhythm patterns even though Jenkins' Lingua Franca Core excludes them — Field (2005) found stress misplacement measurably hurts intelligibility for both native and non-native listeners, a direct contradiction of that exclusion worth building around rather than following LFC verbatim.
- **Session shape:** short (1–2 min) passages, frequent — calibration/drilling feel, not a long-form task.
- **Two pipelines, not one:** (1) **Live presence + report occupancy** — on-device streaming ASR aligned against the known script for the **after-Stop report**; while speaking, trust comes from a **top aurora** driven by mic energy plus a plain serif book passage (no live text place-markers). Stall nudge stays. Extra / substitute / skip marks appear **after Stop**. Decision log: `docs/scoping-reading-follow-along.md`. (2) **Pronunciation scoring (GOP)** — alignment-free, CTC-based GOP on raw PCM vs the script's canonical phones (Section 7's remedy for "ASR silently auto-corrects mispronunciations"). Never score Apple's transcript. GOP may run on a dedicated backend; it must not block live presence.
- **Feedback fade design (explicit, time-based):** early sessions surface more live/immediate per-word feedback; later sessions deliberately shift toward end-of-passage-only summary. This mirrors the clinical ultrasound/visual-acoustic biofeedback protocols in Section 3, which fade from immediate to delayed feedback across sessions specifically to build the learner's own self-monitoring rather than creating feedback dependency — not a fixed behavior, a designed progression.
- **Why the live mic path stays on-device:** aurora presence is chunk-rate RMS (no network). Report occupancy still uses on-device ASR + script context (`TokenAligner`) — cloud streaming STT P90 *emission* ~535–597ms before cellular RTT ([AssemblyAI streaming benchmarks, May 2026](https://www.assemblyai.com/docs/streaming/benchmarks)) would not help text place-markers either; Pass 7 (2026-09-19) dropped live text tracking entirely.
- **Why pronunciation scoring may leave the phone:** on-device GOP cannot occupy Apple's Neural Engine while SpeechAnalyzer is live (`docs/architecture-format1-prototype.md`); CPU GOP is slow and will not hit the accuracy bar. A GPU backend scoring short finalized-word PCM slices, then deleting them, is the honest path. Privacy is **not** the veto — on-device-only was a publishing convenience, not a user demand (2026-09-18). Process-and-delete + updated consent still apply. App Store does not require on-device inference.
- **What we will not do:** route the live cursor through a backend. That trades a thermal/CPU problem for a p99-network problem and makes Reading feel dead.

### Conversation — 15-minute rehearsal with an AI partner
- **Status:** Shape defined below; MVP-first format, reaffirmed (see §5) after weighing and rejecting a reversal to Reading — Conversation is direct practice of the app's actual target behavior, where Reading carries an open, literature-flagged transfer-to-spontaneous-speech risk. Not hours-long ambient. v1 promise (one paragraph): `docs/superpowers/specs/2026-09-21-conversation-format-design.md`.
- **Framing:** explicitly a low-stakes rehearsal space, not a claimed replacement for human interaction (Cross-Cutting Finding #3 — no lens in the literature review found evidence AI substitutes for real human interaction).
- **Partner behavior:** the AI should hold genuine positions, disagree when it is real, and ask information-seeking questions. Agreeable is out. **v1 enforcement is a sampled stance card + a quality spike**, not a solved sycophancy system. Long's Interaction Hypothesis (negotiation-of-meaning, especially in **information-gap** tasks) is the reason this format exists; **v1 is free-talk rehearsal of the target behavior**, not a designed info-gap. Info-gap waits. Do not cite Long as a v1 control plane.
- **Session shape (revised 2026-09-21):** **15 min** hard cap (how we talk about it: 10–15; 5 min ok for dev/test — same wrap). No duration slider. User can hang up anytime. Partner opens with a real question. Free-flowing, no fixed scenario. Pause button; **1.5 min of silence auto-pauses** in foreground **or** background and freezes the clock (resume = same conversation). Unplug headphones = pause. Abandoned pause: 10 min → report, no spoken close. Copy never says “you went quiet.” ~2 min before the cap, the partner warns, then closes in character, then the report. Product write-up: `docs/superpowers/specs/2026-09-21-conversation-format-design.md`. Technical layer: `docs/superpowers/specs/2026-09-21-conversation-technical-layer-design.md`.
- **L1 mixing (revised 2026-09-21):** English only. No taper to track. **v1 does not** have the partner ask them to retry in English — slips are report-only (or `uncertain`) until live `code_switch` passes eval. Target-language-only matches Freed et al. on oral fluency; this persona already has English on paper. **Explain It Another Way is not Conversation v1.** Live repair is also not the v1 stand-in while it is off.
- **Feedback timing (revised 2026-09-21):** report after they stop (Reading-like: textual, skimmable, details in a stable order). **v1 partner-spoken lines:** opening question, wrap warn, wrap close. Cue machinery for code-switch and filler-ok is **built but spoken-off** until on-device precision gates. Stalls stay in the report. “New Best” / “Improved” progress chips are **wanted later, not v1**.

#### Conversation — Technical architecture (iOS-only)
- **Full write-up (locked 2026-09-21, v1 promise aligned same day):** `docs/superpowers/specs/2026-09-21-conversation-technical-layer-design.md`. Live path is OpenAI Realtime **`gpt-realtime-2.1-mini`** (flagship is a quality spike only). Session controller, scoring, fillers, language-id, and crisis sit on the phone. The model does not call tools in v1.
- **Our backend in v1:** ephemeral key mint **plus** server-enforced 20 starts / calendar month, 1 concurrent session, mint rate-limit, anonymous `crisis_referral_events`, `possible_minor_flag`. Audio does not go to our servers. **Not mint-only.**
- **Session model — CORRECTED per audit (`docs/audit-report.md` Tier 1 §1):** the original CallKit + PushKit VoIP-call model is a real App Store rejection risk (Guideline 2.5.4 — VoIP for “people call other people”). **Replacement:** `UIBackgroundModes: audio` + `AVAudioSession.Category.playAndRecord`. **Not identical UX:** the system “on a call” indicator is lost; Dynamic Island / Live Activity is the replacement. No 30 s forgotten-mic hang-up — background silence uses the same 1.5 min auto-pause as foreground.
- **Backgrounded visualizer:** ActivityKit / Live Activities + Dynamic Island, layered on the corrected background-audio session (no longer dependent on a CallKit call object).
- **Regulatory/compliance (revised 2026-09-21):** Conversation meets California SB 243's companion-chatbot definition. **Architecture locked; ship blocked** on website protocol + counsel 988/22604 copy. Engineering contracts: (a) **18+** attestation at account create plus `§ 22604` minor-unsuitability sentence, (b) on-device crisis gate — **keywords fail closed**, FM timeout **fail-open**; canned 988 + session abort + anonymous referral count — the persona never *speaks* crisis. The voice does not claim to be human. `omni-moderation` optional, default off. **Still open (not v1 engineering):** FTC 6(b), EU AI Act manipulative-design, relationship-rupture/discontinuation, instrumentation-privacy compounding. Detail: technical-layer spec.
- **Cost/battery model (revised 2026-09-21):** **15 min** cap plus pause / 1.5 min silence auto-pause (mic muted **and released**; new audio not billed while paused). Production SKU is **mini**: ballpark **$0.35–$0.75** / 15 min *if* prompt cache holds — not a worksheet. Flagship is **$1.00–$2.00** and does not fit unlimited $20/mo. **20 started conversations / calendar month**, gated **before Start**, never mid-talk. Quality spike before mini is the shipped mouth. **Battery/thermal of 15 min SpeechAnalyzer + WebRTC on iPhone 11 is not modeled** — soak is a ship gate. Detail: technical-layer spec.
- **Audio pipeline (revised 2026-09-21):** native speech-to-speech (OpenAI Realtime over WebRTC), not a live STT→LLM→TTS cascade. iOS voice-processing + Realtime near-field noise reduction. Scoring is **on-device** (SpeechAnalyzer family + energy VAD + acoustic fillers + per-turn language-id — **no SpeechDetector**). Live S2S transcript is not the report source. No second cloud STT.
- **Dialogue engine:** Realtime model with a stable persona + sampled stance card. English only. **v1 spoken cues we queue:** `open`, `wrap_warn`, `wrap_close` — folded into `response.create` instructions, never spliced mid-sentence, never a model tool call. `code_switch` / `filler_ok` machinery ships **off**.
- **Output:** native S2S audio with barge-in. Partner asides (when live) wait for the next user turn.
- **Feedback data captured (v1 UI):** time spoken, turn count, English slips or `uncertain`, filled pauses if present, pace as a raw number (no target), pause **time**. **Not v1 UI:** hesitation *location*, collocation/grammar/register (Gaps 4–5), vocal variety, IC, coherence (Gaps 6–7), “Understood?”, Gap 2 variance, progress chips. **Not** phoneme-level pronunciation (see Reading). Do not invent population-normed “normal ranges.”
- **Audio retention:** process-and-delete. **No milestone snippets in v1**, no speaker embeddings. Later: consent-based periodic snippets is an open product question (BIPA/WOPRA), not a v1 decision.
- **Engagement mechanics:** **daily pushes are later, not v1** (technical layer Explicitly later). Habit metric is conversations/week, not daily. AI-initiated sessions stay deferred.

### Monologue — hybrid 4/3/2 (familiar topic, 4 → 3 → 2 min ceilings)
- **Status:** Shape locked 2026-09-24. Full write-up: `docs/superpowers/specs/2026-09-24-monologue-format-design.md`. Not built.
- **What it is:** one familiar-topic monologue, three takes, shrinking **ceilings** (4, 3, 2 minutes). Optional notes, then **I’m ready** — same 3-2-1 as Reading / Conversation, then the take clock. Topic does not change. No named listener; presence is aurora `listen`. **Done** ends the take (leftover clock unused; 0:00 = Done). Copy never says “same talk,” “repeat,” or “tell it again” — after take 1 the page says “Three minutes.”; after take 2, “Two minutes.”
- **What it is not:** a 5–15 minute one-shot talk, Conversation without a partner, or a mash-up that pretends Yuan & Ellis (2003, **10 min** planning) and Maurice/Nation 4/3/2 are the same exercise. 1-minute planning is Mehnert (1998), not Yuan & Ellis.
- **Grounding:** 4/3/2 (Maurice 1983; Nation 1989) for utterance fluency under shrinking time (Thai & Boers 2016: shrinking time is load-bearing; 80–91% wording overlap is expected). Computer recording without a live listener still works (De Jong & Perfetti 2011); lasting fluency in that paper needed **same-topic return on a later day** — v1 reopens the last prompt silently, with **Change topic** to leave it. Pre-task notes are allowed but skippable; they are hidden during the take.
- **Accuracy caveat:** 4/3/2 alone trades fluency against accuracy. Tran & Saito (2024) delayed metalinguistic CF was human-coded, one form, between days — not an LLM dump on Apple ASR. v1 honesty bar: after take 1, optional **one-line reuse note they write**. App generates no form feedback. Do not report a grammar %.
- **Grading:** named-index **profile**, not a score. Per counting take (≥30 s wall, paused clock excluded): phonation-time ratio, pause time, pause count (gaps ≥250 ms), overlap % vs previous counting take, optional raw pace (`ConversationPace` is articulation rate — syllables / phonation — with a spelling-syllable caveat). Full profile if ≥2 counting takes (first vs last that count); else duration + take count only. Never a 0–100, letter, CEFR, GOP, or “Fluency 78.” Show per-take numbers, not an improvement badge.
- **Live chrome:** Pause, aurora `listen`, Done. Back + confirm ends the regimen and opens the report. **I’m ready** runs the same 3-2-1 as Reading / Conversation before the take. Silence does **not** auto-pause (unlike Conversation). Pause / system interrupt freezes the clock.
- **Crisis:** same 988 full-screen + anonymous POST `/crisis` as Conversation. No Realtime. Local SpeechAnalyzer + energy VAD; process-and-delete PCM per take; no speaker embeddings.
- **Home (prototype):** no hero. Three equal glass rows — Read a passage, Start a conversation, Talk about something.
- **Transfer limit:** 4/3/2 gains transfer to another monologue on the same topic, not to Conversation’s interactive job (`literature-review.md` §4). Do not let this format replace Conversation.

## 3. Barrier-derived mechanics (apply across formats, not standalone formats)

| Documented barrier | Candidate mechanic | Concrete activity spec |
|---|---|---|
| High-functional-load errors matter far more than low-FL ones (Munro & Derwing 2006) | Diagnostic scoring (Reading) prioritizes high-FL errors for follow-up drilling | Reading's error list is sorted/weighted by functional load, not raw error count |
| L1-mediated translation delay + active/passive vocabulary gap (Section 4; real-world research) | Formulaic-chunk/collocation drills | **"Explain It Another Way":** when Conversation logs a long hesitation followed by an L1 code-switch or stall, that word/concept is queued as a short drill — produce 3 different spoken explanations of it, no translation, under light time pressure. **Not Conversation v1** (2026-09-21). Live code-switch repair is also **not** the v1 stand-in while spoken cues are off. |
| Jenkins' "accommodation skills" (Section 2/6) | Communication repair training | Same activity as above — this is the concrete operationalization of accommodation-skills training |
| L2 speakers don't reliably use pitch to signal contrast/given-new/disagreement (Wennerstrom, Pickering — Section 2) | Pragmatic-prosody training | **"Say It Like You Mean It":** given a sentence + an intent (agree/disagree/surprised/sincere-vs-sarcastic), produce it with matching intonation; scored by contour *shape/class* matching the intended function, not exact pitch replication (sidesteps "no single correct contour" problem). Reuses Reading's pitch-visualization tech. |
| Narrative "transportation" effect (Green & Brock 1997, Section 5) | Storytelling as distinct from argument | **Not Monologue v1.** Later prompt-type variant: "tell about a time when..." with a narrative-arc rubric. v1 4/3/2 does not score beginning/tension/resolution — shrinking time forces omission. |
| Vocal variety/pitch range linked to perceived charisma (Section 5) | Track as a delivery metric | **Not Conversation v1 UI. Not Monologue v1 UI.** Later: one more line on a post-session report — no new activity needed. |
| Self-monitoring/metacognitive deficit (Section 3) | "Predict your own score" step before AI reveals feedback | Trains self-detection as a distinct, tracked skill (see Metrics Catalog §I) |
| Foreign Language Anxiety compounding general public-speaking anxiety (Section 5) | Graduated exposure structure | Borrows systematic desensitization's low-to-high-stakes escalation (exploratory — see §4) |
| AI/ASR is weak at scoring prosody/intonation (Cross-Cutting Finding #1) | Visual pitch-contour feedback instead of a single pass/fail score | Sidesteps a claim the tech can't reliably support |
| Prompts outperform recasts for corrective feedback (Ammar & Spada 2006) | AI nudges/asks ("did that sound right to you?") rather than silently auto-correcting | Applies to Conversation post-session feedback phrasing |
| Filler words/delivery affect perceived competence independent of content (Section 5) | Passive delivery-metric tracking, not live interruption | Shown as trend data across sessions |
| Massed practice is a "double-edged sword" vs. distributed practice (Section 4) | Spaced, not massed, scheduling | Not a user-facing activity — a scheduling rule: whatever surfaces a specific sound/chunk for drilling (Reading targets, formulaic chunks) can't be crammed repeatedly in one sitting; space repeat exposure across sessions via a lightweight spaced-repetition scheduler |

## 4. Additional format candidates (exploratory — not yet evaluated or committed)

Mined from barriers/mechanisms your three formats don't directly cover. None are committed.

- **Shadowing / listen-and-repeat.** Listen to native audio, repeat immediately, feedback fades immediate→delayed over repetitions. Real fluency/prosody evidence; a 2025 Oxford systematic review found effects on segmental accuracy "inconclusive"; one study found unsupervised shadowing improved perception without improving production — needs feedback attached, not run as pure unsupervised repetition.
- **Connected-speech listening training.** Trains the *listening* side specifically — Section 2 found L2 listeners' transcription accuracy drops 13–49 points from careful to natural fast speech (linking, reduction, elision). None of Reading, Conversation, and Monologue train perception; this would be a distinct receptive-skill format.
- **Minimal-pair / functional-load micro-drills.** Short discrimination-then-production drills targeting the *specific* high-FL confusions Reading diagnoses for that individual — operationalizes High-Variability Phonetic Training (durable, 3–6 month retained gains).
- **Taught impromptu-speaking frameworks (PREP, etc.).** A more scaffolded sibling to Monologue — explicitly teach a named structure before the timed monologue. Pick PREP (real controlled result, scores 39.50→66.00) over Monroe's Motivated Sequence (near-universally taught, but its one controlled test found no persuasion advantage).
- **Graduated exposure ladder for speaking anxiety.** Borrows systematic desensitization/VRET's low-to-high-stakes escalation structure — the strongest-evidenced anxiety treatment in the whole review (g ≈ 0.74–1.46), but almost all of that evidence is general/native-speaker population; L2-specific studies are small-N and not yet RCT-grade. A well-motivated bet, not a proven one for this population specifically.
- **Formulaic-chunk retrieval drills.** Given a common multi-word chunk, produce it aloud in a novel sentence under light time pressure — targets active retrieval specifically (not recognition), directly addressing the passive-vs-active-vocabulary gap that real-world learner research consistently names as the actual bottleneck.

## 4a. Human-in-the-loop — resolved

- **Peer/community feedback (Toastmasters-style, visible to other learners): ruled out.** Recent (2025–2026) head-to-head AI-vs-human/peer feedback studies consistently find learners report less anxiety and prefer AI specifically because it's private and non-judgmental; one controlled study found the anxiety-performance link that exists under human-facilitated assessment disappears entirely under AI facilitation. Peer visibility is evidence-contraindicated for this population, not just uncomfortable.
- **Private, opt-in, non-peer-visible expert review (Speechling model): kept as a future/optional layer, not MVP.** Speechling's live product model — user chooses which recordings to submit, a coach reviews privately within ~24h, feedback is never shown to other users — is the concrete precedent for a human-in-the-loop layer that doesn't carry the peer-visibility risk above. Every AI-vs-human study found still recommends *some* human layer for emotional nuance/authentic complexity — this is how that gets satisfied without contradicting the anxiety evidence.

## 4b. Accessibility/neurodivergence — deferred to post-MVP, three cheap flags kept now

Full accessibility work deferred. These three are cheap now, expensive to retrofit later:

1. Feedback pipeline outputs structured data (scores/transcripts/metrics), not audio-only-baked-in output — keeps future alternate-modality rendering (visual/text) possible without rebuilding the feedback layer.
2. Score relative to the individual's own baseline/trend, not fixed population-normed thresholds — already the direction chosen (individualized diagnosis); just don't walk it back when building delivery-metric "normal ranges."
3. Prosody/pitch scoring compares against a range/class of acceptable contours, not one hardcoded universal target — avoids a model-retraining problem later.

## 4c. Metrics Catalog — Every Dimension of "Good Speech" Named in the Literature

Purpose: a single engineering-facing reference of every measurable dimension the research identifies as mattering for intelligibility, fluency, and confident delivery — so nothing gets built without knowing what it should actually be tracking. Each entry notes its source and which format(s) currently produce it. **Bolded** entries marked "GAP" are named in the literature but not currently targeted by any format or activity above — proposed fixes follow the table.

### A. Segmental (individual sound) accuracy
| Metric | Source | Currently produced by |
|---|---|---|
| Phoneme-level accuracy (GOP score) | Section 7 — GOP scoring is the ASR-backbone standard | Reading |
| Functional-load-weighted error severity | Munro & Derwing 2006 | Reading |
| L1-transfer pattern flags (perceptual vs. motoric origin) | Section 2/3 | Reading (individualized diagnosis) |

### B. Suprasegmental / Prosody
| Metric | Source | Currently produced by |
|---|---|---|
| Word/sentence stress placement accuracy | Field 2005 | Reading (script library deliberately includes stress patterns beyond LFC) |
| Intonation contour shape at boundary tones (statement/question/etc.) | Section 2 | "Say It Like You Mean It" (§3) |
| Pitch range / intensity variation ("vocal variety") | Section 5 (charisma link) | **Not Conversation v1 UI. Not Monologue v1 UI.** Later delivery report |
| Pitch used to signal discourse function (contrast, given/new, disagreement) | Wennerstrom; Pickering — Section 2 | "Say It Like You Mean It" (§3) |
| Rhythm pattern (stress-timing) | Section 2 | Reading (partial, via stress coverage) |

### C. Connected speech
| Metric | Source | Currently produced by |
|---|---|---|
| Linking/reduction/assimilation/elision — production accuracy | Section 2 | Reading (if scripts include connected-speech-triggering phrases) |
| **Connected-speech perception/listening accuracy** (13–49 pt accuracy drop found, careful→fast native speech) | Section 2 | **GAP** — see proposal below |

### D. Fluency / Temporal (Segalowitz's utterance fluency construct)
| Metric | Source | Currently produced by |
|---|---|---|
| Speech rate (syllables/words per min) | Section 4 | Reading (timing). Conversation v1: raw pace, no target (`ConversationPace` is articulation rate). Monologue v1: optional raw pace on the profile, same extractor + spelling-syllable caveat — not a population WPM |
| Phonation-time ratio (speech time / wall time) | Towell; De Jong — Section 4 | **Monologue v1** — strongest scalar on the profile. Conversation could derive it; not Conversation v1 UI |
| Take-to-take wording overlap % | Thai & Boers 2016 (80–91% under shrinking time) | **Monologue v1** — descriptive, expected high, not an originality fail. Not Conversation |
| Pause frequency / duration | Section 4 | Conversation v1: pause **time** only. Monologue v1: pause **time and count** (gaps ≥250 ms). Location: not v1 |
| Pause *location* (mid-clause vs. between-clause — indicates *type* of processing breakdown) | Section 4 | **Not v1** — no clause segmenter. Not Monologue v1 either. |
| Filler-word rate | Section 5 | Conversation v1: filled-pause pattern if soak allows; described as filled pauses, not a lecture. Monologue: after L2 soak only — **not v1 UI** |
| Repetition / false-start / self-correction rate | Section 4 | **Not v1** |
| Perceived fluency (listener subjective judgment — distinct from the above objective measures) | Segalowitz 2010, Section 4 | Not directly measured — would require a listener-judgment proxy (see intelligibility gap below) |
| **Cognitive fluency / automaticity** — Segalowitz's finding that true automatization shows up as *reduced variability* across repeated similar-difficulty tasks, not just faster averages | Section 4 | **GAP** — see proposal below |

### E. Lexical / Retrieval
| Metric | Source | Currently produced by |
|---|---|---|
| Lexical diversity (vocabulary variety used) | Section 1/4 | Conversation: derivable, **not v1 UI**. Monologue v1: **do not** score as “better vocabulary” — 4/3/2 is designed to reuse wording (Thai & Boers overlap 80–91%). Overlap % on the profile is descriptive, not an originality grade. |
| Formulaic-chunk usage rate / retrieval latency | Section 1/4 | Formulaic-chunk drills candidate (§4, not yet committed) |
| Active-vs-passive vocabulary gap (needs a hint/translation vs. spontaneous production) | Real-world research pass | "Explain It Another Way" (§3) — **not Conversation v1** |
| Paraphrase/repair success rate | Jenkins' accommodation skills, Section 2/6 | "Explain It Another Way" (§3) — **not Conversation v1** |
| **Lemma/word-choice appropriateness** (conceptually right word, not rare-word usage — explains 63% of comprehensibility variance) | Saito, Webb, Trofimovich & Isaacs, *SSLA* 2016 ([doi:10.1017/s0272263115000297](https://doi.org/10.1017/s0272263115000297)) | **GAP — see §4c fix below** |
| **Collocation accuracy/association** (words that belong together — "make a decision," not "do a decision") | Crossley, Salsbury & McNamara, *Applied Linguistics* 2015 ([doi:10.1093/applin/amt056](https://doi.org/10.1093/applin/amt056)); Saito, *Language Learning* 2020 ([doi:10.1111/lang.12387](https://doi.org/10.1111/lang.12387)) | **GAP — see §4c fix below** |
| **Register match** (spoken-typical vs. essay-typical word choice for the audience/situation) | Bot, Durrant et al., *IJLCR* 2024 ([doi:10.1075/ijlcr.23029.bot](https://doi.org/10.1075/ijlcr.23029.bot)) | **GAP — see §4c fix below** |

### F. Organization / Discourse
| Metric | Source | Currently produced by |
|---|---|---|
| Structural adherence to a taught framework (PREP: point-reason-example-point) | Section 5 | Taught-frameworks candidate (§4, not yet committed) |
| Narrative-arc elements (clear beginning/tension/resolution) | Green & Brock 1997, Section 5 | **Not Monologue v1.** Storytelling variant later (§3). |
| **Spoken grammatical accuracy weighted by listener effort** (not raw error count — articles, tense, agreement, morphology; distinct from pronunciation) | Trofimovich & Isaacs 2012 ([doi:10.1017/s1366728912000168](https://doi.org/10.1017/s1366728912000168)); Isaacs & Trofimovich, *SSLA* 2012 ([doi:10.1017/s0272263112000150](https://doi.org/10.1017/s0272263112000150)) | **GAP — see §4c fix below** |
| **Discourse coherence / topic development** (cohesive devices, staying on a through-line — the "Coherence" half of IELTS's own Fluency & Coherence criterion) | Isaacs & Trofimovich 2012 (op. cit.); Iwashita et al., IELTS-commissioned research ([ielts.org PDF](https://ielts.org/cdn/Research/examination-of-discourse-competence-at-different-proficiency-levels-in-ielts-speaking-part-2-iwashita-et-al-2015.pdf)) | **GAP — see §4c fix below** |

### G. Delivery / Paralinguistic
| Metric | Source | Currently produced by |
|---|---|---|
| Vocal variety (pitch + intensity variation) | Section 5 | **Not Conversation v1 UI. Not Monologue v1 UI.** Later delivery report |

### H. Outcome / Ground-truth (what everything above is a proxy for)
| Metric | Source | Currently produced by |
|---|---|---|
| Comprehensibility (subjective ease-of-understanding) | Munro & Derwing 1995, Section 6 | Not directly measured — inferred from proxy metrics only |
| **Intelligibility (objective % of meaning actually understood by an independent listener)** | Munro & Derwing 1995, Section 6 — the single most load-bearing construct in the whole review | **GAP** — see proposal below |
| Accentedness | Section 6 | **Deliberately not scored/optimized** — per the ethics framing (Cross-Cutting Finding #2), this is a dimension we explicitly decline to target |

### I. Meta-cognitive
| Metric | Source | Currently produced by |
|---|---|---|
| Self-monitoring accuracy (gap between predicted and actual score) | Section 3 (self-monitoring named as its own trainable deficit) | "Predict your own score" mechanic (§3, not yet fully specced as a tracked metric — flagged for follow-up) |

### J. System-health / fairness (not user-facing — needed for model QA)
| Metric | Source | Currently produced by |
|---|---|---|
| ASR WER stratified by accent/L1/disfluency-type | Addendum A, Addendum C | Not yet specced — recommended as a standing QA metric, not a user-facing one |
| GOP-score reliability stratified by accent strength | Addendum A (bias-propagation risk into pronunciation scores) | Not yet specced — recommended as a standing QA metric |

### K. Interactional Competence (conversation as a distinct skill from delivery)
| Metric | Source | Currently produced by |
|---|---|---|
| **Turn-taking management** (holding a turn after pushback, not just talking) | Galaczi, *Applied Linguistics* 2014 ([doi:10.1093/applin/amt017](https://doi.org/10.1093/applin/amt017)) | **GAP — see §4c fix below** |
| **Listener-support / negotiation-of-meaning moves** (clarification requests, confirmation checks — the learner-side half of Long's Interaction Hypothesis) | Long 1980, Section 1; Galaczi & Taylor 2018 | **GAP — see §4c fix below** |
| **Topic management** (extending vs. merely answering) | Galaczi 2014 (op. cit.) | **GAP — see §4c fix below** |

### Gaps identified and proposed fixes — designed vs v1 UI

Catalog rows below are **what to measure eventually**, not Conversation v1 report copy. v1 Conversation UI: time, turns, slips/`uncertain`, filled pauses, pace (raw), pause time. See `docs/superpowers/specs/2026-09-21-conversation-format-design.md`.

1. **Connected-speech perception (C). Designed; not Conversation v1 partner behavior.** (a) *Later:* the AI partner occasionally uses genuine slang/connected speech, calibrated to level — a live instance of Long (breakdown → clarification). **v1 does not** ship this as a frequency-capped mechanic (casual register is fine; no slang program). (b) Separate **"Connected Speech Challenge"** drill stays a candidate — standalone, **not inside Conversation v1**.
2. **Cognitive fluency / automaticity via variance, not just averages (D). DOWNGRADED from RESOLVED to exploratory hypothesis — audit finding, `docs/audit-report.md` Tier 1 §4.** Original proposal: track variance/consistency of existing delivery metrics (pace, filler rate, hesitation) across similar-difficulty prompts over time, on the theory that shrinking variance at a stable-or-improving mean signals real fluency (Segalowitz). Two independent audit personas found (a) no study has ever computed this kind of variance from naturalistic conversational delivery metrics — every real test of the construct uses millisecond-precision lab reaction-time tasks, not live speech metrics, and one direct test found the construct "has little practical value in predicting L2 oral proficiency"; and (b) for a user who stutters, day-to-day variability *is* the clinical presentation itself (ASHA Fluency Disorders Practice Portal; Tichenor & Yaruss, *AJSLP*), independent of any L2 progress — meaning "rising variance" would misdiagnose exactly the population §4b already committed to not actively harming. **Status: exploratory. Do not log as if an extractor exists. Not user-facing until validated.** Also needs a real noise-floor baseline — within-subject CV on common acoustic/speech features regularly exceeds 48% even under controlled clinical conditions.
3. **Direct intelligibility measurement (H). Designed with a gating condition — "Understood?". Not Conversation v1 UI. Not Monologue v1 UI.** Applies later to Conversation and Monologue only (not Reading). Mechanism: 20–30s snippet of novel speech → separate model, no context → intended-vs-received gap. **Audit finding (Tier 1 §3):** this defeats ASR auto-correction and will manufacture false "didn't understand you" verdicts for disfluent speech. **Gate before shipping to any user:** (a) hold behind disfluency-aware ASR-WER QA, or (b) onboarding self-flag that suppresses it. Experiment with a kill-switch, not a launch-day certainty.
4. **Lexical/word-choice appropriateness (E). Designed — no new format. Not Conversation v1 UI. Not Monologue v1 UI.** Saito et al. 2016 / Crossley et al. 2015 / Saito 2020: collocation accuracy, not rarity. Fix when artifacts exist: (a) Reading scripts sample high-frequency collocations; (b) Conversation/Monologue post-session flags collocation + register via a **named shipped spoken-corpus table** (PMI/MI) — no LLM for detection, only phrasing. **v1 does not ship this line:** no corpus is packaged, and Apple ASR auto-corrects many of the errors detection needs. Explicitly **not** building a vocabulary-lesson module.
5. **Spoken grammatical accuracy weighted by listener effort (F). Designed — no grammar-lesson module. Not Conversation v1 UI.** Trofimovich & Isaacs (2012): score *effortful* errors, not a checker dump. Needs a **closed pattern list**, not PMI (PMI is collocation). Reading doesn't need it.
6. **Discourse coherence / topic development (F). Designed — fold into scoring later. Not Conversation v1 UI. Not Monologue v1 UI.** Structurally most diagnostic on a long monologue, but v1 4/3/2 does **not** score it: extractors do not exist, and shrinking time forces omission. Needs cohesive-device / topic-drift extractors that do not exist yet.
7. **Interactional competence (K). Designed — Conversation-only analysis layer later. Not Conversation v1 UI.** Galaczi (2014) / Galaczi & Taylor (2018). No new format. No extractors in v1.

**Net effect of gaps 4–7:** none require a fourth core format. They are later scoring dimensions on transcripts the app will already collect. They are **not** v1 Conversation report fields. Full sourcing: `research/literature-review.md` §§1/4/6 plus the lexical-choice and discourse research pass (2026-08-30).

### Standing engineering principle (for the later architecture pass)

Minimize AI/ML reliance in favor of deterministic/algorithmic methods wherever the task is actually signal processing or arithmetic, not language understanding — motivated by non-determinism and cost, not just preference. Some things are inherently ML/ASR/LLM-dependent by the nature of the task (the conversational AI partner, GOP-based phoneme scoring, any open-vocabulary transcription, "Understood?") — not a matter of implementation effort. Others are classical DSP/statistics with no ML needed at all (pitch/F0 tracking, VAD/pause detection, speech-rate calculation, functional-load weighting, spaced-repetition scheduling — Addendum A already flags pitch/pause detection specifically as "decades-old, cheap DSP"). **Gap 2 variance math is exploratory, not a v1 method to route.** The lever is routing each metric to the cheapest sufficient method, not avoiding AI universally. Conversation v1 routing: `docs/superpowers/specs/2026-09-21-conversation-technical-layer-design.md`.

## 5. Product Architecture: How Many Formats, and How Broad Should Each Be?

Question raised: given how much detail each format is being asked to extract, should metrics be spread across *more*, narrower activities for cleaner measurement — or kept concentrated in the current 3 formats? Relatedly, would users rather have many activities, or a handful they return to often — and should we cut down to a single, maximally-niche core loop? Four independent literatures converge on an answer, with one hard constraint pulling the other way.

### a. Splitting into more activity *types* does not fix the measurement problem — repetition does

The instinct that "a single interaction gives noisy/incomplete data" is correct, but the literature points to the opposite fix from "invent more activity types." Classical test theory's **Spearman-Brown prophecy formula** (Spearman 1910; Brown 1910) formalizes a basic fact of measurement: reliability of a score is a function of the number of *parallel* (same-type) observations, not the number of *different* instruments used once each — doubling a test's length (more items of the same kind) raises reliability predictably; splitting the same testing time across several different, non-comparable instruments does not, because none of them accumulates enough repeated trials to average out noise ([Spearman-Brown, Wikipedia summary of Spearman 1910/Brown 1910](https://en.wikipedia.org/wiki/Spearman%E2%80%93Brown_prediction_formula); [Assessment Systems Corp explainer](https://assess.com/spearman-brown-prediction-formula/)). Applied here: the fix for "one Format-3 talk isn't enough data" is *more short, repeated Format-3-shaped sessions* whose scores get aggregated/trended, not a 4th, 5th, 6th format each capturing one metric once. This is also exactly what Gap 2 in §4c (fluency-variance tracking) already assumes — variance/reliability only becomes measurable with repeated, comparable trials.

### b. Habit formation favors few, simple, repeatable loops — not many activity types

Lally, van Jaarsveld, Potts & Wardle (2010, *European Journal of Social Psychology*, [doi:10.1002/ejsp.674](https://doi.org/10.1002/ejsp.674)) found habits form through consistent repetition of the *same* behavior in a *stable context* (median 66 days to automaticity, range 18–254); missing an occasional rep barely mattered, but the mechanism is repetition-of-sameness, not variety. BJ Fogg's Behavior Model, B=MAP ([behaviormodel.org](https://www.behaviormodel.org/); [Stanford Behavior Design Lab](https://behaviordesign.stanford.edu/resources/fogg-behavior-model)), makes the mechanism explicit: behavior happens when Motivation, Ability, and a Prompt converge, and **Ability (simplicity) is the reliable lever** because motivation fluctuates — every additional decision point ("which of 3 different activities do I do today, and why") is a tax on Ability. This is a direct, literature-grounded answer to "would users want more activities or a few they return to": more heterogeneous options is a worse fit for habit formation, not a better one, independent of any user survey.

### c. Choice overload is a documented, causal effect, not a hunch

Iyengar & Lepper's jam study (2000, *J. Personality and Social Psychology*, [doi:10.1037/0022-3514.79.6.995](https://doi.org/10.1037/0022-3514.79.6.995)) is the canonical demonstration: a 6-option display outsold a 24-option display of the same product by ~10x in actual follow-through, and choosers from the smaller set were *more* satisfied with what they picked, not less. This has been replicated (with caveats on moderating factors — familiarity, structure, time pressure) across pens, chocolates, and 401(k) plan enrollment ([Scheibehenne, Greifeneder & Todd 2010 meta-analysis](https://scheibehenne.de/ScheibehenneGreifenederTodd2010.pdf)). Applied here: presenting 3 structurally different formats at the "what do I do today" decision point is itself a small choice-overload event, every single session — a cost that compounds daily even if each format is individually well-designed.

### d. This app's own market segment already votes for narrow depth over broad breadth

From `research/literature-review.md` §7's competitive scan: the single-mechanic speech apps in this exact niche (ELSA Speak — pronunciation only; BoldVoice — pronunciation only; Yoodli/Orai — delivery-metrics only; Speechling — record + human feedback only; Pimsleur — audio recall only; TalkPal/Loora/Praktika — ambient conversation only) each ship *one* core loop and go deep, not three. The broad, many-activity-type products in adjacent categories (Duolingo, Babbel) built that breadth *after* achieving retention with one dominant tiny daily loop, not before — general product/retention case-study literature independently converges on this same "narrow-then-broaden" sequencing (a strong core loop first, feature breadth only once that loop demonstrably retains users; feature-bloat is a repeatedly observed cause of retention loss, not a fix for it). None of our own literature attributes language-app churn (9–28% monthly, per §7) to *too little variety* — the documented #1 driver is loss of motivation/results, which the habit-formation and choice-overload evidence above says is better served by fewer, easier, more consistent loops.

### e. The hard constraint: a single format cannot cover every barrier already established in this spec

This is the one place the "go niche" instinct runs into a wall we already hit in the audit. The three formats were not chosen arbitrarily — they map onto structurally distinct SLA mechanisms that don't substitute for each other:

- **Reading (scripted read-aloud)** is the *only* format that can deliver reliable phoneme-level pronunciation feedback, because open-vocabulary ASR auto-corrects mispronunciations toward the statistically expected word ~82% of the time (Addendum A) — Conversation/Monologue structurally cannot produce this data no matter how many sessions are collected.
- **Conversation (15 min rehearsal)** is the *only* format with genuine turn-taking and the think→translate→speak pressure under interaction. v1 is free-talk, not a designed information-gap; negotiation-of-meaning as Long measured it waits. A script (Reading) or a monologue (Monologue) cannot produce this data by construction.
- **Monologue (hybrid 4/3/2)** is the format that can train **utterance fluency** on a repeated familiar-topic monologue under shrinking time — a construct Conversation (turns) and Reading (script) cannot produce by construction. v1 measures PTR / pauses / overlap, not Gap 6 coherence. Transfer is to another monologue on the same topic, not to interactive talk. Do not treat it as Conversation’s substitute.

So "cut to one format" is not neutral — it is a decision to permanently give up whichever construct the other two uniquely cover. Going to a single format is only safe as a *launch-sequencing* choice (build one loop first, add the others once it retains users), not as a permanent scope cut.

### Recommendation

1. **Don't fragment into more activity types to chase cleaner metrics.** Keep the 3 formats; get more/cleaner data from each via repetition and short session length, not via inventing a 4th/5th format per metric. Gaps 1–7 stay **scoring layers on existing sessions**, not new activities — and Conversation **v1 UI does not include** Gaps 1/4–7.
2. **Reconsidered and reversed — MVP order stays Conversation first.** The habit-formation argument (§5b) and the audit's "Unknown Unknown #1" (`docs/audit-report.md`) both favored flipping to Reading first, on the grounds that it's shorter, lower-friction, and carries less platform/regulatory/cost risk. But weighed against a more fundamental question — does the format actually get a user toward the app's stated goal — the two formats are not equivalent, and this is where the case for Reading breaks down: `literature-review.md` (Section 4) names drill-to-spontaneous-speech transfer as **"the single biggest risk for any drill-based app design"** — gains from scripted practice improve pronunciation *of that script*, but whether that transfers to real, spontaneous, confident speech (the actual goal) is an open, unresolved question in the field, not a settled fact (reinforced in Section 7: "the evidence for transfer to public-speaking-grade, real-time fluency is thinner than the evidence for isolated drill gains"). Conversation does not have this problem structurally — it is not a proxy/drill hoping to transfer to the target behavior, it **is** the target behavior (rehearsed spontaneous speech), so there's no analogous "does this even work toward the goal" risk to weigh against its real-but-fixable engineering/regulatory/cost risks (all addressed above). **Net: lower-risk-but-unproven-to-work loses to higher-effort-but-directly-on-target.** Reading keeps its existing role — soft-recommended onboarding/calibration step, not the sole or first core loop — because that's a role it's well-evidenced for (diagnostic pronunciation data) without requiring it to carry the app's entire behavior-change burden alone.
3. **Treat "how many activities do users want" as answered by convergent adjacent evidence (§5b–d above), not yet by direct evidence on this app.** No source in `research/literature-review.md` or the competitive scan gives this app's users a direct preference vote between "3 formats" and "1 format, deeper" — flag this as an assumption inherited from habit-formation/choice-overload/retention literature, worth validating with real usage data once there are users to observe, not just literature.

## 6. Open Decisions Log

| Decision | Status |
|---|---|
| User profile (fluent-on-paper vs. still-building) | **Resolved:** fluent-on-paper/anxious-in-speech is the primary design target |
| AI conversation framing | **Resolved:** rehearsal space, not human-replacement |
| Feedback timing (Conversation) | **Resolved (revised 2026-09-21):** report after stop. v1 partner speaks `open` / wrap warn / wrap close only. Code-switch + filler machinery built, **spoken-off** until eval. No live chips. Monologue: report after the regimen (or Back-confirm); no live chips; no generated form feedback. |
| Progression model | **Resolved:** individualized/assessment-driven, not a fixed universal ladder |
| Gamification stance | **Resolved (conditional):** track real delivery-improvement metrics as primary signal where feasible; keep any streak/consistency mechanic visually/conceptually separate; do not lead with streaks |
| Conversation report progress labels (“New Best”, “Improved”) | **Deferred:** not v1; add once a personal baseline exists. Do not show population norms in the meantime. |
| Reading as onboarding gate | **Resolved:** soft-recommended, not mandatory |
| Conversation structure | **Resolved:** free-flowing, no fixed scenario; partner opens. Info-gap later. |
| Conversation pause | **Resolved (2026-09-21):** pause button + 1.5 min silence auto-pause **foreground or background**; unplug headphones = pause; 10 min abandoned-pause TTL; clock frozen; same conversation on resume. Never “you went quiet.” No 30 s background hang-up. |
| AI pushback behavior | **Resolved as a prompt bet:** stance card + quality spike. Not a runtime guarantee. Sycophancy unsolved. |
| Session length (Conversation) | **Resolved (revised 2026-09-21):** **15 min** hard cap (5 min for dev/test). No slider. Hang up anytime. ~2 min in-character warning, then wrap, then report. |
| L1-mixing taper | **Resolved (revised 2026-09-21):** English only. Code-switch machinery on; **live spoken repair off** until eval. No taper tracking. |
| Explain It Another Way | **Deferred:** not Conversation v1 |
| Background session UI | **Resolved (corrected per audit):** `UIBackgroundModes: audio` + `AVAudioSession.playAndRecord` (not CallKit/PushKit — App Store rejection risk, see Conversation architecture above) + Dynamic Island visualizer |
| Conversation regulatory compliance (SB 243 companion-chatbot category) | **Architecture locked; ship blocked (2026-09-21):** 18+ attestation; keywords fail-closed + FM fail-open; canned 988 abort. Voice does not claim to be human. Website protocol + counsel copy are **ship blockers**. FTC / EU AI Act / rupture / telemetry disclosure **open**. See technical-layer spec. |
| Conversation cost/battery model | **Resolved as a ballpark (revised 2026-09-21):** mini **$0.35–$0.75** / 15 min *if cache holds*; **20 starts / calendar month** gated before Start; flagship not the $20/mo SKU. Mute+release on pause. Mini ship-gated on a quality spike **and** iPhone 11 thermal soak. Battery not modeled yet. See technical-layer spec. |
| Conversation backend | **Resolved (2026-09-21):** mint + server-enforced budget + crisis counter + minor flag. Not mint-only. |
| Conversation report (v1) | **Resolved (2026-09-21):** time, turns, slips/`uncertain`, filled pauses, pace (raw), pause time. **Not v1:** hesitation location, collocation/grammar, vocal variety, IC, coherence. |
| Daily push notifications | **Deferred:** not Conversation v1. Habit = conversations/week. |
| Noisy-environment handling | **Resolved:** best-effort on-device noise suppression, no behavior demands on user |
| Raw audio retention | **Resolved for v1 (2026-09-21):** process-and-delete. No milestone snippets, no embeddings. Later opt-in snippets remain an open product question. |
| AI-initiated sessions | **Deferred** to later product-decisions pass |
| Reading architecture detail | **Resolved (revised 2026-09-19 Pass 7):** fixed script library; **live presence** = top aurora from mic energy + plain serif book passage; **report occupancy** from on-device ASR; **GOP / phoneme scoring backend-eligible** (process-and-delete); short/frequent sessions. Live text place-markers retired. On-device-only as a product lock is reversed — it was a publishing convenience, not a user demand. |
| Reading live cursor vs backend | **Resolved (revised 2026-09-19 Pass 7):** do **not** put the live mic path on a server. Live UI: aurora + book passage + stall — no live text tracking, no live transcript, no live skip/extra/swap. Full approach + decision reasoning: `docs/scoping-reading-follow-along.md`. |
| Reading GOP compute | **Resolved in principle (2026-09-18):** dedicated scoring backend over on-phone GOP. Measure follow-along vs GOP separately before building infra — if the cursor is what's slow, a backend will not fix it. |
| Monologue architecture detail | **Resolved (2026-09-24):** hybrid 4/3/2 local recorder. Spec: `docs/superpowers/specs/2026-09-24-monologue-format-design.md`. No Realtime. SpeechAnalyzer + energy VAD. Process-and-delete per take. No embeddings. Crisis = Conversation 988 path. |
| Monologue report (v1) | **Resolved (2026-09-24):** counting take ≥30 s wall. Full profile if ≥2 counting takes: PTR, pause time, pause count, overlap %, optional raw pace + caveat. Else duration + take count. No composite / GOP / grammar %. |
| Additional format candidates | **Logged (Section 4)** — shadowing, connected-speech listening, minimal-pair/FL micro-drills, taught impromptu frameworks, graduated anxiety-exposure ladder, formulaic-chunk retrieval drills. Not yet evaluated/committed. |
| Human-in-the-loop (peer/community vs. private coach) | **Resolved:** peer/community ruled out (evidence-contraindicated for anxiety); private opt-in expert review kept as future/optional layer, not MVP |
| Accessibility/neurodivergence scope | **Deferred to post-MVP**, with 3 architecture flags locked in now (§4b) |
| Barrier-derived features → concrete activities | **Logged (§3):** EIAW **deferred**; vocal variety **not v1 UI**; Say It Like You Mean It unchanged; storytelling **not Monologue v1** |
| Full metrics catalog | **Logged (§4c)** — 30+ metrics across 11 categories. Conversation **v1 UI is a subset** (see report lock) |
| Metrics gaps found | **7 identified. v1 Conversation UI includes none of Gaps 1/4–7.** Gap 1 partner slang later. Gap 2 exploratory. Gap 3 Understood? gated, not v1. Gaps 4–5 need corpus + grammar list. Gaps 6–7 need extractors. |
| Format count (3 formats vs. more-granular activities vs. single-format) | **Resolved: keep 3 formats, do not fragment further** — new metrics get folded into existing sessions later (§5) |
| MVP format order | **Reaffirmed: Conversation first.** Reconsidered per habit-formation literature + the audit's Unknown Unknown #1 (both favored Reading first), then reversed back given `literature-review.md`'s own drill-to-spontaneous-speech transfer finding ("the single biggest risk for any drill-based app design") — Conversation is direct practice of the target behavior, not a proxy with an open transfer question, so it wins despite carrying more (fixable) engineering/regulatory/cost risk. Reading stays a soft-recommended onboarding/calibration step, not the sole core loop. See §5. |

---

*This document will be updated as the conversation progresses. Cross-reference `research/literature-review.md` and `research/accessibility-neurodivergence-review.md` for full citations behind every claim above.*
