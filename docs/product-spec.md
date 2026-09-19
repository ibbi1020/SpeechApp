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
| **Conversation** | Format 2 | Ambient AI speaking partner — the product MVP |
| **Monologue** | Format 3 | Topic + short prep, then an extended talk |

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

### Conversation — Extended, ambient conversation with an AI partner
- **Status:** Shape defined below; MVP-first format, reaffirmed (see §5) after weighing and rejecting a reversal to Reading — Conversation is direct practice of the app's actual target behavior, where Reading carries an open, literature-flagged transfer-to-spontaneous-speech risk. Still carries real, fixable requirements before build (App Store, SB 243 compliance, cost/battery model — see architecture section below), which are independent of this sequencing decision.
- **Framing:** explicitly a low-stakes rehearsal space, not a claimed replacement for human interaction (Cross-Cutting Finding #3 — no lens in the literature review found evidence AI substitutes for real human interaction).
- **Core mechanic requirement:** the AI must hold genuine positions, disagree naturally, and ask real information-seeking questions — sycophantic/agreeable AI provides no negotiation-of-meaning, which Long's Interaction Hypothesis (Section 1) identifies as the actual mechanism driving acquisition in conversation. This is a load-bearing design requirement, not a persona nicety.
- **Session shape:** open-ended length, user-initiated per session (whether the AI can ever proactively nudge is deferred), ambient/no fixed scenario — free-flowing conversation about anything.
- **L1 mixing:** allowed initially as an anxiety-reduction on-ramp (consistent with lowering the affective filter — Krashen), with a **deliberate taper back toward English-only over time** as the user gets more comfortable (avoids the fossilization/permanent-crutch risk — Selinker's Interlanguage Hypothesis, Section 1; also consistent with Freed et al.'s finding that immersion/target-language-only produces the largest fluency gains).
- **Feedback timing:** post-session only, not live interruption (matches Duolingo's own product decision and the prompts-over-recasts literature; reduces mid-flow anxiety, which real-world research confirms is the dominant barrier).

#### Conversation — Technical architecture (iOS-only)
- **Session model — CORRECTED per audit (`docs/audit-report.md` Tier 1 §1):** the original CallKit + PushKit VoIP-call model is a real, documented App Store rejection risk — Apple App Review Guideline 2.5.4 restricts background VoIP entitlements to apps that let "people call other people," and CallKit/PushKit-as-background-access-workaround for non-telephony features has real rejection precedent, with no shipped counter-example found. **Replacement:** standard `UIBackgroundModes: audio` capability + `AVAudioSession.Category.playAndRecord` — the documented mechanism dictation/voice-memo/meditation apps already use for background mic access, with identical UX outcome and none of the policy risk. The "on a call" system indicator is lost (that was CallKit-specific); the in-app Dynamic Island visualizer below is the replacement transparency cue.
- **Backgrounded visualizer:** ActivityKit / Live Activities + Dynamic Island, layered on the corrected background-audio session (no longer dependent on a CallKit call object).
- **Regulatory/compliance requirements — new, from audit (`docs/audit-report.md` Tier 1 §2):** Conversation meets California SB 243's definition of a "companion chatbot" (adaptive, human-like, anthropomorphic, sustains a relationship across interactions) almost verbatim against its own design brief. This is not a reason to kill Conversation, but per SB 243 plus the active FTC Section 6(b) inquiry into this exact product category, it is not safe to ship without: (a) a stated minimum-age policy, (b) a self-harm/crisis-detection-and-referral protocol on the conversation pipeline, and (c) an explicit AI-disclosure pattern shown to the user — regardless of initial launch jurisdiction, given regulatory attention is not California-only. **Open — needs an explicit design pass before Conversation architecture work starts**, not before this doc update, but before build.
- **Cost/battery model — missing, flagged by audit (`docs/audit-report.md` Tier 1 §5):** no model currently exists for Conversation's "ambient, potentially hours-long" design. 2026 vendor pricing for cascaded/native speech-to-speech puts variable cost at $0.02–$0.46/minute — a 1–2hr/day power user could cost $36–$550+/month in API spend alone, before infra, and real-world continuous on-device inference shows thermal throttling within 30–45 seconds to a few minutes on iPhone-class hardware plus 19–31%/hour battery drain for continuous on-device ASR. **Open — required before Conversation's "open-ended session length" decision (already logged below) can be treated as build-ready; likely needs a session cap or hybrid on/off-device routing decision.**
- **Audio pipeline:** on-device VAD → on-device speech-enhancement/noise-suppression (Krisp/RNNoise/Denoiser-style) → streaming, open-vocabulary ASR (cloud or hybrid; on-device ASR alone currently carries a documented non-native accuracy penalty — Addendum A, the Whisper-Tiny 243.6% relative WER disparity finding).
- **Dialogue engine:** conversational LLM, explicitly prompted for non-sycophancy, genuine opinions, real follow-up questions, and gradual L1-taper behavior; bounded per-session context (no requirement for full long-term memory across sessions, though light continuity to avoid staleness is a reasonable enhancement).
- **Output:** low-latency, natural/expressive TTS with barge-in (interruption) support.
- **Feedback data captured:** delivery metrics only from this format — pace, filler-word rate, hesitation location (Section 4: disfluency location indicates *where* processing breaks down — mid-clause vs. between-clause). **Not** reliable phoneme-level pronunciation data (see Reading rationale above).
- **Audio retention:** default is process-and-delete, no raw audio retained. Open exploration: consent-based, periodic "milestone" snippets (e.g., every N days) for the user's own before/after progress review — modeled like opt-in progress photos in fitness apps, with explicit informed consent and a defined retention/deletion policy, to stay inside BIPA-style biometric-consent requirements rather than continuous silent retention. **Not yet finalized** — flagged as a real design question, not a decision.
- **Engagement mechanics:** daily push notifications as a retention lever, kept conceptually and visually separate from any "real improvement" metric (to avoid the "400-day streak, no improvement" failure mode surfaced in real-world learner research). Whether/how the AI itself ever proactively initiates a session is deferred to a later product-decisions pass.

### Monologue — Topic given, ~1 min prep, extended talk (5–15+ min)
- **Status:** Concept strongly evidence-backed; architecture not yet detailed.
- **Grounding:** near-exact match for two independently strong findings — pre-task planning time reliably increases fluency/lexical variety/grammatical complexity (Yuan & Ellis 2003, 771 citations), and the 4/3/2 technique's shrinking-time-limit structure (Maurice 1983).
- **Known caveat to design around:** 4/3/2-style practice alone produces a documented fluency-accuracy trade-off — speed improves, accuracy doesn't, unless explicit corrective feedback is layered in. Feedback mechanism for this format still needs to be designed with this in mind.

## 3. Barrier-derived mechanics (apply across formats, not standalone formats)

| Documented barrier | Candidate mechanic | Concrete activity spec |
|---|---|---|
| High-functional-load errors matter far more than low-FL ones (Munro & Derwing 2006) | Diagnostic scoring (Reading) prioritizes high-FL errors for follow-up drilling | Reading's error list is sorted/weighted by functional load, not raw error count |
| L1-mediated translation delay + active/passive vocabulary gap (Section 4; real-world research) | Formulaic-chunk/collocation drills | **"Explain It Another Way":** when Conversation logs a long hesitation followed by an L1 code-switch or stall, that word/concept is queued as a short drill — produce 3 different spoken explanations of it, no translation, under light time pressure. Drill-selection input comes directly from Conversation's own hesitation/code-switch logs. |
| Jenkins' "accommodation skills" (Section 2/6) | Communication repair training | Same activity as above — this is the concrete operationalization of accommodation-skills training |
| L2 speakers don't reliably use pitch to signal contrast/given-new/disagreement (Wennerstrom, Pickering — Section 2) | Pragmatic-prosody training | **"Say It Like You Mean It":** given a sentence + an intent (agree/disagree/surprised/sincere-vs-sarcastic), produce it with matching intonation; scored by contour *shape/class* matching the intended function, not exact pitch replication (sidesteps "no single correct contour" problem). Reuses Reading's pitch-visualization tech. |
| Narrative "transportation" effect (Green & Brock 1997, Section 5) | Storytelling as distinct from argument | Monologue prompt-type variant: "tell about a time when..." with a narrative-arc rubric (clear beginning/tension/resolution) instead of PREP's argument structure. Same mechanic, different prompt type + rubric. |
| Vocal variety/pitch range linked to perceived charisma (Section 5) | Track as a delivery metric | Added as one more line in the existing Conversation/Monologue post-session delivery report — no new activity needed |
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
| Pitch range / intensity variation ("vocal variety") | Section 5 (charisma link) | Conversation/Monologue delivery report |
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
| Speech rate (syllables/words per min) | Section 4 | Reading (timing), Conversation/Monologue (delivery report) |
| Pause frequency / duration | Section 4 | Conversation/Monologue delivery report |
| Pause *location* (mid-clause vs. between-clause — indicates *type* of processing breakdown) | Section 4 | Conversation/Monologue delivery report |
| Filler-word rate | Section 5 | Conversation/Monologue delivery report |
| Repetition / false-start / self-correction rate | Section 4 | Conversation/Monologue delivery report |
| Perceived fluency (listener subjective judgment — distinct from the above objective measures) | Segalowitz 2010, Section 4 | Not directly measured — would require a listener-judgment proxy (see intelligibility gap below) |
| **Cognitive fluency / automaticity** — Segalowitz's finding that true automatization shows up as *reduced variability* across repeated similar-difficulty tasks, not just faster averages | Section 4 | **GAP** — see proposal below |

### E. Lexical / Retrieval
| Metric | Source | Currently produced by |
|---|---|---|
| Lexical diversity (vocabulary variety used) | Section 1/4 | Conversation/Monologue (derivable from transcripts, not yet specced as a tracked metric) |
| Formulaic-chunk usage rate / retrieval latency | Section 1/4 | Formulaic-chunk drills candidate (§4, not yet committed) |
| Active-vs-passive vocabulary gap (needs a hint/translation vs. spontaneous production) | Real-world research pass | "Explain It Another Way" (§3) |
| Paraphrase/repair success rate | Jenkins' accommodation skills, Section 2/6 | "Explain It Another Way" (§3) |
| **Lemma/word-choice appropriateness** (conceptually right word, not rare-word usage — explains 63% of comprehensibility variance) | Saito, Webb, Trofimovich & Isaacs, *SSLA* 2016 ([doi:10.1017/s0272263115000297](https://doi.org/10.1017/s0272263115000297)) | **GAP — see §4c fix below** |
| **Collocation accuracy/association** (words that belong together — "make a decision," not "do a decision") | Crossley, Salsbury & McNamara, *Applied Linguistics* 2015 ([doi:10.1093/applin/amt056](https://doi.org/10.1093/applin/amt056)); Saito, *Language Learning* 2020 ([doi:10.1111/lang.12387](https://doi.org/10.1111/lang.12387)) | **GAP — see §4c fix below** |
| **Register match** (spoken-typical vs. essay-typical word choice for the audience/situation) | Bot, Durrant et al., *IJLCR* 2024 ([doi:10.1075/ijlcr.23029.bot](https://doi.org/10.1075/ijlcr.23029.bot)) | **GAP — see §4c fix below** |

### F. Organization / Discourse
| Metric | Source | Currently produced by |
|---|---|---|
| Structural adherence to a taught framework (PREP: point-reason-example-point) | Section 5 | Taught-frameworks candidate (§4, not yet committed) |
| Narrative-arc elements (clear beginning/tension/resolution) | Green & Brock 1997, Section 5 | Monologue storytelling variant (§3) |
| **Spoken grammatical accuracy weighted by listener effort** (not raw error count — articles, tense, agreement, morphology; distinct from pronunciation) | Trofimovich & Isaacs 2012 ([doi:10.1017/s1366728912000168](https://doi.org/10.1017/s1366728912000168)); Isaacs & Trofimovich, *SSLA* 2012 ([doi:10.1017/s0272263112000150](https://doi.org/10.1017/s0272263112000150)) | **GAP — see §4c fix below** |
| **Discourse coherence / topic development** (cohesive devices, staying on a through-line — the "Coherence" half of IELTS's own Fluency & Coherence criterion) | Isaacs & Trofimovich 2012 (op. cit.); Iwashita et al., IELTS-commissioned research ([ielts.org PDF](https://ielts.org/cdn/Research/examination-of-discourse-competence-at-different-proficiency-levels-in-ielts-speaking-part-2-iwashita-et-al-2015.pdf)) | **GAP — see §4c fix below** |

### G. Delivery / Paralinguistic
| Metric | Source | Currently produced by |
|---|---|---|
| Vocal variety (pitch + intensity variation) | Section 5 | Conversation/Monologue delivery report |

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

### Gaps identified and proposed fixes — all seven resolved

1. **Connected-speech perception (C). RESOLVED: both.** (a) Folded into Conversation — the AI partner occasionally uses genuine slang/connected speech, and the user must navigate it (request clarification, or infer from context) rather than being shielded from it. This is a live instance of Long's Interaction Hypothesis (real communication breakdown → clarification request) and the receptive mirror of "Explain It Another Way" (same accommodation-skills construct, opposite direction — requesting a repair vs. producing one). Must be calibrated to the individual's level/comfort — frequent-enough-to-be-realistic, not so frequent it undermines Conversation's low-pressure design goal. (b) *Also* kept as a separate, deliberate **"Connected Speech Challenge"** — fast native clip → transcribe/identify what was said → reveal reduced-vs-citation form — because organic conversation can't guarantee systematic coverage or clean ground-truth scoring the way a deliberate drill can (same relationship as Reading vs. Conversation for pronunciation: one clean/diagnostic, one ecologically valid/noisy).
2. **Cognitive fluency / automaticity via variance, not just averages (D). DOWNGRADED from RESOLVED to exploratory hypothesis — audit finding, `docs/audit-report.md` Tier 1 §4.** Original proposal: track variance/consistency of existing delivery metrics (pace, filler rate, hesitation) across similar-difficulty prompts over time, on the theory that shrinking variance at a stable-or-improving mean signals real fluency (Segalowitz). Two independent audit personas found (a) no study has ever computed this kind of variance from naturalistic conversational delivery metrics — every real test of the construct uses millisecond-precision lab reaction-time tasks, not live speech metrics, and one direct test found the construct "has little practical value in predicting L2 oral proficiency"; and (b) for a user who stutters, day-to-day variability *is* the clinical presentation itself (ASHA Fluency Disorders Practice Portal; Tichenor & Yaruss, *AJSLP*), independent of any L2 progress — meaning "rising variance" would misdiagnose exactly the population §4b already committed to not actively harming. **Status: needs its own small validation pass (does this variance signal correlate with anything real, on this app's own data) before being trusted as a scored metric; ship as an internal/QA-only signal, not user-facing, until validated.** Also needs a real noise-floor baseline — within-subject CV on comparable acoustic/speech features regularly exceeds 48% even under controlled clinical conditions, so the metric will be noisier in practice than originally assumed.
3. **Direct intelligibility measurement (H). RESOLVED WITH A GATING CONDITION — "Understood?".** Applies to Conversation and Monologue only (not Reading, which already has a known-ground-truth script, making the check meaningless there). Mechanism: take a 20–30s snippet of novel, unscripted speech → feed to a separate model with no context → ask it to (a) transcribe as best it can and (b) explicitly report whether it understood what was said → show the user the intended-vs-received gap. Directly operationalizes Munro & Derwing's actual intelligibility construct rather than inferring it from proxies. **Audit finding (Tier 1 §3, `docs/audit-report.md`):** this design deliberately defeats the accidental safety net that normal ASR's auto-correction provides typical L2 speech — which is the entire point for a typical speaker, but for a user with atypical/disfluent speech this manufactures false "didn't understand you" verdicts that reflect the project's own already-documented ASR-bias-against-disfluent-speech finding (§4b), not the user's actual intelligibility. **Gate before shipping to any user:** either (a) hold "Understood?" behind the same disfluency-aware ASR-WER QA metric already logged in §4c Category J, only surfacing the feature once that stratified WER gap is measured and small enough, or (b) pair the feature with a disfluency/atypical-speech self-flag at onboarding that suppresses "Understood?" for those users until a disfluency-aware variant exists. No real-world precedent exists for this mechanic elsewhere — it is genuinely novel, not a transfer of a validated method, which argues for treating it as an experiment with a kill-switch, not a launch-day certainty.
4. **Lexical/word-choice appropriateness (E). RESOLVED — no new format, fold into existing scoring.** Saito et al. 2016 found lemma/word-choice appropriateness explains the largest share of comprehensibility variance among lexical measures (larger than raw vocabulary size), and multiple corpus studies (Crossley et al. 2015; Saito 2020, Language Learning; Bailey & Meara/Siyanova-Chanturia lines) converge on **collocation accuracy** — not lexical rarity — as the strongest lexical predictor of both comprehensibility and human-rated oral proficiency. Fix: (a) in Reading, script selection deliberately samples high-frequency collocations (already implicit in "natural" scripts, now made an explicit selection criterion); (b) in Conversation and Monologue, post-session analysis flags collocation errors ("do a decision" → "make a decision") and register mismatches (essay-register words in casual delivery) as a distinct feedback category, scored algorithmically via corpus/embedding association strength (e.g., mutual information or PMI against a reference corpus) — no LLM call required for detection, only for the explanatory phrasing shown to the user. Explicitly **not** building: a vocabulary-lesson module, a "learn N new words" mechanic, or any feature that rewards rare/sophisticated words — Bott et al. 2024 found *lower* lexical sophistication in higher-proficiency spontaneous speech (speakers default to frequent, safe words under real-time pressure), so optimizing for "bigger vocabulary" would reward exactly the wrong thing.
5. **Spoken grammatical accuracy weighted by listener effort (F). RESOLVED — fold into existing scoring, do not build a grammar-lesson module.** Trofimovich & Isaacs (2012) and Isaacs & Trofimovich (2012) show grammatical accuracy affects listener-rated comprehensibility only insofar as errors raise processing effort (article/tense/agreement errors that don't obscure meaning matter far less than those that do) — this is the same "effort, not correctness" framing already used for pronunciation (§ per Munro & Derwing) and should govern this metric identically: score and surface *effortful* errors, not a raw grammar-checker error count. Applies as a post-session analysis layer on Conversation/Monologue transcripts; Reading doesn't need it (scripted text has no grammar to score).
6. **Discourse coherence / topic development (F). RESOLVED — fold into Conversation/Monologue scoring.** Isaacs & Trofimovich (2012) and IELTS-commissioned research on their own Speaking Part 2 "Fluency and Coherence" criterion (Iwashita et al.) both treat coherence — logical idea progression, cohesive-device use (linking words, referencing), staying on a through-line — as a distinct, ratable construct from fluency (pace/pausing) or grammar. Applies to Monologue (extended monologue — this is *the* format where coherence is most diagnostic) and Conversation (multi-turn coherence across a conversation). Detection is largely algorithmic (cohesive-device tagging, topic-drift measures on the transcript) with an LLM only for the human-readable explanation.
7. **Interactional competence (K). RESOLVED — fold into Conversation, do not build a separate format.** Galaczi (2014) and Galaczi & Taylor (2018) establish interactional competence — turn-taking management, listener-support moves (clarification/confirmation checks), topic management — as empirically separable from delivery-level fluency in paired/interactive speaking assessment, and directly operationalizes the learner-side half of Long's Interaction Hypothesis already used for Gap 1 (Connected Speech). Since Conversation is the only format with genuine turn-taking, this is purely a new analysis layer on Conversation transcripts (did the user hold their turn under pushback? did they ask for clarification when confused, versus going silent or bluffing? did they extend a topic or just answer and stop?) — no new activity needed.

**Net effect of gaps 4–7:** none of them require a fourth core format or a dedicated lesson module. They are additional scoring dimensions applied to transcripts/audio the app is already collecting from Reading, Conversation, and Monologue, consistent with the "comprehensibility is multi-domain, not single-construct" finding running through the whole literature review (Section 8). Full sourcing: `research/literature-review.md` §§1/4/6 plus the lexical-choice and discourse research pass (2026-08-30).

### Standing engineering principle (for the later architecture pass)

Minimize AI/ML reliance in favor of deterministic/algorithmic methods wherever the task is actually signal processing or arithmetic, not language understanding — motivated by non-determinism and cost, not just preference. Some things are inherently ML/ASR/LLM-dependent by the nature of the task (the conversational AI partner, GOP-based phoneme scoring, any open-vocabulary transcription, "Understood?") — not a matter of implementation effort. Others are classical DSP/statistics with no ML needed at all (pitch/F0 tracking, VAD/pause detection, speech-rate calculation, the Gap 2 variance math, functional-load weighting, spaced-repetition scheduling — Addendum A already flags pitch/pause detection specifically as "decades-old, cheap DSP"). The lever is routing each metric to the cheapest sufficient method, not avoiding AI universally. Full technical routing deferred to the architecture pass.

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
- **Conversation (extended conversation)** is the *only* format with genuine turn-taking, negotiation of meaning, and the think→translate→speak pressure under real interactional stakes — a script (Reading) or a monologue (Monologue) cannot produce this data by construction.
- **Monologue (planned monologue)** is the best fit for discourse coherence/organization metrics (Gap 6, above) and rehearsed-delivery confidence, distinct from both.

So "cut to one format" is not neutral — it is a decision to permanently give up whichever construct the other two uniquely cover. Going to a single format is only safe as a *launch-sequencing* choice (build one loop first, add the others once it retains users), not as a permanent scope cut.

### Recommendation

1. **Don't fragment into more activity types to chase cleaner metrics.** Keep the 3 formats; get more/cleaner data from each via repetition and short session length, not via inventing a 4th/5th format per metric — consistent with how Gaps 1–7 in §4c were resolved (new scoring dimensions on existing sessions, not new activities).
2. **Reconsidered and reversed — MVP order stays Conversation first.** The habit-formation argument (§5b) and the audit's "Unknown Unknown #1" (`docs/audit-report.md`) both favored flipping to Reading first, on the grounds that it's shorter, lower-friction, and carries less platform/regulatory/cost risk. But weighed against a more fundamental question — does the format actually get a user toward the app's stated goal — the two formats are not equivalent, and this is where the case for Reading breaks down: `literature-review.md` (Section 4) names drill-to-spontaneous-speech transfer as **"the single biggest risk for any drill-based app design"** — gains from scripted practice improve pronunciation *of that script*, but whether that transfers to real, spontaneous, confident speech (the actual goal) is an open, unresolved question in the field, not a settled fact (reinforced in Section 7: "the evidence for transfer to public-speaking-grade, real-time fluency is thinner than the evidence for isolated drill gains"). Conversation does not have this problem structurally — it is not a proxy/drill hoping to transfer to the target behavior, it **is** the target behavior (rehearsed spontaneous speech), so there's no analogous "does this even work toward the goal" risk to weigh against its real-but-fixable engineering/regulatory/cost risks (all addressed above). **Net: lower-risk-but-unproven-to-work loses to higher-effort-but-directly-on-target.** Reading keeps its existing role — soft-recommended onboarding/calibration step, not the sole or first core loop — because that's a role it's well-evidenced for (diagnostic pronunciation data) without requiring it to carry the app's entire behavior-change burden alone.
3. **Treat "how many activities do users want" as answered by convergent adjacent evidence (§5b–d above), not yet by direct evidence on this app.** No source in `research/literature-review.md` or the competitive scan gives this app's users a direct preference vote between "3 formats" and "1 format, deeper" — flag this as an assumption inherited from habit-formation/choice-overload/retention literature, worth validating with real usage data once there are users to observe, not just literature.

## 6. Open Decisions Log

| Decision | Status |
|---|---|
| User profile (fluent-on-paper vs. still-building) | **Resolved:** fluent-on-paper/anxious-in-speech is the primary design target |
| AI conversation framing | **Resolved:** rehearsal space, not human-replacement |
| Feedback timing (Conversation and Monologue) | **Resolved:** post-session only |
| Progression model | **Resolved:** individualized/assessment-driven, not a fixed universal ladder |
| Gamification stance | **Resolved (conditional):** track real delivery-improvement metrics as primary signal where feasible; keep any streak/consistency mechanic visually/conceptually separate; do not lead with streaks |
| Reading as onboarding gate | **Resolved:** soft-recommended, not mandatory |
| Conversation structure | **Resolved:** free-flowing, no fixed scenario |
| AI pushback behavior | **Resolved:** realistically assertive |
| Session length (Conversation) | **Resolved:** open-ended |
| L1-mixing taper | **Resolved:** allow initially, taper over time |
| Background session UI | **Resolved (corrected per audit):** `UIBackgroundModes: audio` + `AVAudioSession.playAndRecord` (not CallKit/PushKit — App Store rejection risk, see Conversation architecture above) + Dynamic Island visualizer |
| Conversation regulatory compliance (SB 243 companion-chatbot category) | **Open — required before build:** minimum-age policy, crisis/self-harm referral protocol, AI-disclosure pattern (§ Conversation architecture) |
| Conversation cost/battery model | **Open — required before build:** no model exists yet for ambient/hours-long sessions; likely needs a session cap or on/off-device routing decision (§ Conversation architecture) |
| Noisy-environment handling | **Resolved:** best-effort on-device noise suppression, no behavior demands on user |
| Raw audio retention | **Open:** leaning toward no default retention; exploring consent-based, opt-in periodic milestone snippets with defined retention/deletion policy (progress-photo model) |
| AI-initiated sessions | **Deferred** to later product-decisions pass |
| Reading architecture detail | **Resolved (revised 2026-09-19 Pass 7):** fixed script library; **live presence** = top aurora from mic energy + plain serif book passage; **report occupancy** from on-device ASR; **GOP / phoneme scoring backend-eligible** (process-and-delete); short/frequent sessions. Live text place-markers retired. On-device-only as a product lock is reversed — it was a publishing convenience, not a user demand. |
| Reading live cursor vs backend | **Resolved (revised 2026-09-19 Pass 7):** do **not** put the live mic path on a server. Live UI: aurora + book passage + stall — no live text tracking, no live transcript, no live skip/extra/swap. Full approach + decision reasoning: `docs/scoping-reading-follow-along.md`. |
| Reading GOP compute | **Resolved in principle (2026-09-18):** dedicated scoring backend over on-phone GOP. Measure follow-along vs GOP separately before building infra — if the cursor is what's slow, a backend will not fix it. |
| Monologue architecture detail | **Not yet started** (deferred — architecture can be interpolated once feature scope settles) |
| Additional format candidates | **Logged (Section 4)** — shadowing, connected-speech listening, minimal-pair/FL micro-drills, taught impromptu frameworks, graduated anxiety-exposure ladder, formulaic-chunk retrieval drills. Not yet evaluated/committed. |
| Human-in-the-loop (peer/community vs. private coach) | **Resolved:** peer/community ruled out (evidence-contraindicated for anxiety); private opt-in expert review kept as future/optional layer, not MVP |
| Accessibility/neurodivergence scope | **Deferred to post-MVP**, with 3 architecture flags locked in now (§4b) |
| Barrier-derived features → concrete activities | **Resolved:** "Explain It Another Way" (repair/paraphrase), "Say It Like You Mean It" (pragmatic prosody), storytelling prompt variant, vocal-variety metric, spaced-scheduling rule — see §3 |
| Full metrics catalog | **Logged (§4c)** — 30+ metrics across 11 categories, cross-referenced against every format |
| Metrics gaps found | **7 identified, 5 resolved, 2 conditional (§4c):** connected-speech perception (resolved), cognitive-fluency/automaticity-via-variance (**downgraded to exploratory — audit finding**), direct intelligibility measurement ("Understood?" — **resolved with a gating condition on disfluency bias — audit finding**), lexical/word-choice appropriateness & collocation (resolved), spoken grammatical accuracy (resolved), discourse coherence (resolved), interactional competence (resolved) |
| Format count (3 formats vs. more-granular activities vs. single-format) | **Resolved: keep 3 formats, do not fragment further** — new metrics get folded into existing sessions (§5) |
| MVP format order | **Reaffirmed: Conversation first.** Reconsidered per habit-formation literature + the audit's Unknown Unknown #1 (both favored Reading first), then reversed back given `literature-review.md`'s own drill-to-spontaneous-speech transfer finding ("the single biggest risk for any drill-based app design") — Conversation is direct practice of the target behavior, not a proxy with an open transfer question, so it wins despite carrying more (fixable) engineering/regulatory/cost risk. Reading stays a soft-recommended onboarding/calibration step, not the sole core loop. See §5. |

---

*This document will be updated as the conversation progresses. Cross-reference `research/literature-review.md` and `research/accessibility-neurodivergence-review.md` for full citations behind every claim above.*
