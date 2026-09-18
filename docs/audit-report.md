# Audit: Product Spec vs. Literature — Scoping Roundtable Report

**Names (2026-09-18):** this report still says Format 1/2/3. Canonical names are **Reading**, **Conversation**, **Monologue** — `docs/formats.md`. Historical quotes below were not rewritten.

**What this is:** A 7-persona research audit of `docs/product-spec.md` against `research/literature-review.md`, `research/accessibility-neurodivergence-review.md`, and fresh 2024–2026 literature not yet incorporated into either. Each persona independently read all three source documents, checked specific spec decisions against real sources, and hunted for new literature the project hasn't found yet. This report is the Moderator synthesis of all seven.

**Decision this informs:** whether the current spec is safe to carry into architecture/build as-is, or which specific decisions need revision first.

---

## TL;DR Verdict

- **Overall: YELLOW, but with one component that should be read as effectively RED.** No single persona called a hard RED, but three independent findings — App Store rejection risk, regulatory/legal exposure, and an ASR-bias-driven feature that actively harms the users most at risk — all land on the *same* format (Format 2) and the *same* MVP-first decision. Stacked together, "ship Format 2 as currently specced" is not safe; each individual piece is fixable.
- **Best-grounded parts of the spec:** intelligibility-over-nativeness framing, individualized (not fixed-curriculum) diagnosis, functional-load weighting, peer-feedback exclusion, Connected Speech Challenge. These were independently corroborated — often *strengthened* — by fresh 2025–2026 literature across multiple personas.
- **Most at-risk part of the spec:** Format 2 (the MVP-first ambient AI conversation partner). It is simultaneously: a platform-policy risk (CallKit), a legal/regulatory risk (companion-chatbot statute), an unmodeled cost/battery risk, a contested-anxiety-mechanism bet, and — ironically — the format with the *weakest* direct evidentiary grounding for the specific mechanism (negotiation-of-meaning) it's justified by.
- **Most over-claimed single item:** the "Gap 2" automaticity-via-variance metric is logged as **RESOLVED** in the spec. Two independent personas, researching separately, concluded it is an unvalidated, novel construct with no precedent for measuring on naturalistic speech, and that it further risks systematically misdiagnosing people who stutter.
- **Recommended immediate next step:** treat this report as a punch list against `docs/product-spec.md` before any architecture work starts on Format 2 specifically. Formats 1 and 3 are in comparatively good shape.

---

## Tier 1 — Must-resolve before building (high severity, compounding, or blocking)

### 1. Format 2's CallKit/PushKit architecture is a real App Store rejection risk
**Raised by:** [Speech-tech, ASR & platform feasibility audit](714f865a-f526-4c81-ac0f-65d2063f828b)

Apple's App Review Guideline **2.5.4** (not 5.2.5, which was the guideline originally assumed and does not apply) restricts background VoIP entitlements to apps that let "people call other people." Real, documented rejections exist for apps using CallKit/PushKit as a background-access workaround for non-telephony features, and a current Apple DTS engineer forum post states this policy explicitly and unambiguously. No shipped precedent was found of an AI-companion app passing review using this exact pattern.

**Fix exists and is cheap:** replace with the standard `UIBackgroundModes: audio` capability + `AVAudioSession.Category.playAndRecord`, paired independently with ActivityKit/Live Activities for the visualizer. This is the documented mechanism dictation/voice-memo/meditation apps already use, preserves every UX goal, and removes the rejection risk entirely.

### 2. Format 2 is, by regulatory definition, a "companion chatbot" — and the spec has never engaged with that category
**Raised by:** [Sociolinguistics, ethics & AI-companion risk audit](698b7ec0-9402-45cf-82f6-65c7e9211720)

California SB 243 (effective Jan 1, 2026) defines a "companion chatbot" as an AI that gives adaptive, human-like responses, exhibits anthropomorphic features, and sustains a relationship across interactions to meet social needs — which is close to a verbatim match for Format 2's design brief ("feel human," "hold genuine positions," ambient/frequent use). SB 243 mandates AI-disclosure, a suitability warning, a mandatory crisis-referral protocol, and minor-specific break reminders. Separately: an active **FTC Section 6(b) inquiry** (Sept 2025) is investigating exactly this product category, and the Character.AI/Google wrongful-death litigation (settled Jan 2026) targeted apps with this same design shape. None of this appears anywhere in the spec's Open Decisions Log.

**This is not a reason to kill Format 2** — but it is not currently safe to ship without: a stated minimum age policy, a crisis/self-harm detection-and-referral design, and a disclosure pattern, regardless of launch jurisdiction (regulatory contagion beyond California is a live risk — see Moderator notes).

### 3. "Understood?" is engineered in a way that systematically penalizes the users most at risk from a documented ASR bias
**Raised by:** [Accessibility & neurodivergence re-audit](f9d620a8-476e-49f1-8049-ff7117df4630), corroborated by [Speech-tech audit](714f865a-f526-4c81-ac0f-65d2063f828b)

The accessibility research already in this project's own docs establishes that ASR has a "consistent and statistically significant accuracy bias against disfluent speech" across six leading systems (~80M people who stutter affected). Normal ASR silently auto-corrects minor L2 mispronunciations — an *accidental* safety net for typical L2 speech. "Understood?" is specifically designed to defeat that safety net (context-free model, no correction) to get a clean intelligibility signal. For a user who stutters or has atypical speech, this design will manufacture false "I didn't understand you" verdicts that reflect ASR bias, not the user's actual English intelligibility. The spec's own Metrics Catalog *already lists* "ASR WER stratified by disfluency-type" as a required QA metric three lines away from this feature — the connection was never made. Separately, the speech-tech audit found no real-world precedent for "Understood?" exists anywhere (it's a genuinely novel, untested combination of back-translation pedagogy and 2025 CALL intelligibility-indicator research) — worth knowing before treating it as more validated than it is.

### 4. "Gap 2" (automaticity-via-variance) is marked RESOLVED but is unvalidated — and specifically risky for a real subpopulation
**Raised independently by:** [Cognitive fluency & psycholinguistics audit](d7303edb-01ee-4e0c-a6b2-c2e2ecd4118b) and [Accessibility & neurodivergence re-audit](f9d620a8-476e-49f1-8049-ff7117df4630); nuanced by [Fresh literature scout](5947c238-52e8-45ff-b96c-98cf93a49e97)

Two independent audits, researching separately, converged on the same conclusion from different angles:
- **No study has ever computed variance from naturalistic conversational delivery metrics** (pace, filler rate, hesitation) the way the spec proposes. Every real test of Segalowitz's coefficient-of-variation construct uses millisecond-precision lab reaction-time tasks (lexical decision, maze tasks), not live speech metrics. The construct itself is contested — one direct test found CV "has little practical value in predicting L2 oral proficiency." The closest real precedent (Hanzawa/Han 2024) used lab-task CV to predict speech outcomes, not variance-of-speech-metrics as the signal itself — a materially different, still-unvalidated move. (Fresh scout independently found and cited the same paper, reaching the same conclusion — this is genuine convergence, not noise.)
- **Stuttering variability is not noise around an L2-skill signal — it is the clinical presentation itself**, and it's documented to fluctuate day-to-day independent of any underlying skill (ASHA Fluency Disorders Practice Portal; Tichenor & Yaruss, *AJSLP*). A user who stutters could see their own "increasing variance" — the exact metric the spec says signals "not yet automatized" — for reasons entirely unrelated to L2 progress.

**Recommendation:** downgrade this from "RESOLVED" to "exploratory hypothesis, needs its own validation study," and add a real-world session-to-session noise floor to the design (a companion finding: within-subject CV on common acoustic/speech features regularly exceeds 48% even in controlled clinical conditions — this metric will be noisier in practice than the spec's plan currently assumes).

### 5. No cost or battery/thermal model exists for Format 2's "ambient, potentially hours-long" design
**Raised by:** [Speech-tech, ASR & platform feasibility audit](714f865a-f526-4c81-ac0f-65d2063f828b)

Back-of-envelope 2026 vendor pricing for cascaded or native speech-to-speech pipelines puts variable cost at **$0.02–$0.46/minute**. A "power user" talking 1–2 hrs/day would cost **$36–$550+/month** in API spend alone — before infrastructure, and potentially exceeding a typical consumer subscription price outright at the higher end. Separately, real-world continuous on-device inference shows measurable thermal throttling within 30–45 seconds to a few minutes on iPhone-class hardware, and third-party reports of 19–31% battery drain/hour for continuous on-device ASR — directly threatening the "hours-long ambient session" design goal regardless of the cost question.

---

## Tier 2 — Important gaps/contradictions to resolve before MVP scope is locked

### Format 2's own SLA-theory justification doesn't match its own design
**[SLA & applied linguistics audit](2f30f7ec-b0ac-49a5-8b54-9e3644adcd9e)**

The spec grounds Format 2 in Long's Interaction Hypothesis (negotiation-of-meaning drives acquisition), but the same cited source finds that **pushed, two-way information-gap tasks** generate significantly more negotiation-of-meaning than one-way/free-talk tasks — and ambient, no-fixed-scenario conversation is closer to the "produces less negotiation" condition than the "produces more" one. No format anywhere is a genuine structured info-gap task (e.g., "describe an image the AI can't see," a hidden-information negotiation task). Compounding this: the "genuinely opinionated, non-sycophantic AI" precondition that Format 2 calls load-bearing is, per 2026 ACL/AI&Society research, a live, only-partially-solved technical problem (sycophancy "persists across models... despite mitigation efforts"), not a settled prompting trick.

### Minimal-pair/HVPT drills — the single strongest-evidenced technique in this entire audit — are still just an "exploratory candidate"
**[Phonetics, prosody & clinical SLP audit](450a1272-fae7-4c47-952e-ee5a8c9e1b54)**

A 2024 meta-analysis puts HVPT's effect at *g* = 0.92 (pretest-posttest) with confirmed long-term retention — stronger than anything else evaluated in this audit — yet it sits in the spec's exploratory bucket (§4) while a weaker-precedented activity ("Say It Like You Mean It") is already committed (§3).

### "Say It Like You Mean It" ships ahead of the accessibility review that flags its exact risk pattern, and isn't grounded in the real linguistic framework for the thing it's trying to do
**[Phonetics audit](450a1272-fae7-4c47-952e-ee5a8c9e1b54)**

Scoring by "contour shape/function-class" instead of exact pitch is a real improvement, but the accessibility doc's own autism-prosody findings warn that even function-class-level "one correct answer per context" scoring can be "actively situationally wrong" for autistic speakers — the exact mechanism this activity uses, shipped without being checked against the review that already flagged it. Separately, the activity would be much better grounded in **Wells' (2006) 3Ts framework** (Tonality/Tonicity/Tone) — a decades-old, real, still-taught linguistic taxonomy for exactly "function, not exact pitch" — rather than an apparently ad hoc in-house rubric.

### The biofeedback feedback-fade design overclaims its clinical precedent
**[Phonetics audit](450a1272-fae7-4c47-952e-ee5a8c9e1b54)**

The immediate→delayed feedback fade is real in motor-speech learning, but every validating source is a **clinician-present, pediatric speech-sound-disorder population** — not unsupervised adult L2 learners. The actual clinical tool being referenced (`staRt`) lists "expand to L2 English learners" as *future* work, not something already validated. This is an untested extrapolation being presented as a transfer of a validated method.

### Cross-format transfer (drills → spontaneous Format 2/3 speech) is assumed, but is the literature's own flagged top risk, untested
**[Cognitive fluency audit](d7303edb-01ee-4e0c-a6b2-c2e2ecd4118b)**, echoed by [Phonetics audit](450a1272-fae7-4c47-952e-ee5a8c9e1b54) and [SLA audit](2f30f7ec-b0ac-49a5-8b54-9e3644adcd9e)

`literature-review.md` already names drill-to-spontaneous-speech transfer failure as "the single biggest risk for any drill-based app design." Three separate personas flagged that nothing in the spec measures or designs against this — Format 1 (closed-vocabulary, scripted) and Format 2 (open-ended, spontaneous) are about as dissimilar in task type as two speaking tasks can be, and transfer-appropriate-processing research shows even much more similar task pairs show only partial, condition-dependent transfer.

### "Spaced, not massed" is applied as a blanket rule when the actual evidence is a genuine trade-off
**[Cognitive fluency audit](d7303edb-01ee-4e0c-a6b2-c2e2ecd4118b)**

New research shows massed practice specifically wins for reducing breakdown-fluency (pauses) on a known target in the short term, while spacing wins for transfer/retention — the opposite of a context-free default. `literature-review.md` itself already calls this a "double-edged sword," but that nuance didn't make it into the actual scheduling rule.

### "Predict your own score" has a direct counter-example showing it can backfire
**[SLA audit](2f30f7ec-b0ac-49a5-8b54-9e3644adcd9e)** and **[Fresh literature scout](5947c238-52e8-45ff-b96c-98cf93a49e97)** (independently, converging)

A BYU RCT (N=409) found explicit calibration-training made learners **more** overconfident, not less. Separately, Dunning-Kruger-pattern research found low-performing learners remain overconfident even after repeated feedback exposure, while high performers calibrate more readily — meaning the mechanic may work asymmetrically well across skill levels, benefiting exactly the users who need it least. Existing positive precedent (Tsunemoto et al.) worked specifically because it included a *benchmarking* step (exposure to calibrated external examples) — something the current spec's bare "guess-then-reveal" design lacks entirely.

### Real, funded competitors already run close variants of Format 2 with published efficacy data
**[Fresh literature scout](5947c238-52e8-45ff-b96c-98cf93a49e97)**

TalkPal, Loora, and Praktika are live products matching the "ambient, frequent, human-feeling AI conversational partner" pattern almost exactly, each with independent 2024–2026 studies showing real (if early-stage) effect sizes on fluency/confidence. This doesn't invalidate Format 2, but it's a real differentiation question that hasn't been asked yet, and it means the format the spec treats as most novel is, from the outside, the most crowded.

### Format 2's "ambient/no fixed scenario" design sits directly on the axis the accessibility research says is hardest for dyslexic adults
**[Accessibility re-audit](f9d620a8-476e-49f1-8049-ff7117df4630)**

The accessibility doc's own "language spontaneity deficit" finding for dyslexic adults says real-time spontaneous speaking is disproportionately hard *because it's unplanned*, not because of stakes — meaning Format 2's "low-pressure" framing doesn't address this, since a low-pressure spontaneous task is still a spontaneous task. Format 2 is nonetheless the MVP-first format, meaning this mismatched design is exactly what ships first.

### Daily push notifications inherit a risk the spec's own mitigation doesn't touch
**[Accessibility re-audit](f9d620a8-476e-49f1-8049-ff7117df4630)**

The spec's fix for gamification risk (keep streaks visually separate from real-improvement metrics) solves metric-conflation, not the cadence-fragility problem the accessibility doc separately names: "one missed day frequently triggers permanent abandonment" for some ADHD users. A daily-cadence notification still establishes the daily obligation whose breakage is the named trigger, streak-badge or not. (To be fair to the spec: the accessibility doc itself flags this claim "partially unverified" and notes a countervailing RCT found gamification *helped* ADHD engagement — this is a real, open tension, not a slam-dunk.)

### No accuracy-focused feedback exists for Format 2, despite the identical structural risk being explicitly named for Format 3
**[SLA audit](2f30f7ec-b0ac-49a5-8b54-9e3644adcd9e)**

The spec names the 4/3/2 fluency-accuracy trade-off as a caveat for Format 3 and cites its fix (explicit corrective feedback). Format 2 — free-flowing, high-volume, MVP-first — has the identical risk and no equivalent fix; its Metrics Catalog output is 100% fluency/delivery/lexical-diversity, 0% grammatical/lexical accuracy.

### Willingness to Communicate (WTC) — a named theoretical construct and the primary outcome metric competitors already use — has no corresponding metric in the catalog
**[SLA audit](2f30f7ec-b0ac-49a5-8b54-9e3644adcd9e)**

Given the app's stated goal is confidence, not just accuracy, this is a conspicuous absence in an otherwise thorough 30+-metric catalog.

### The newest evidence conflicts on whether AI conversation actually reduces anxiety — a claim distinct from "AI beats human facilitation on anxiety," which is solid
**[Fresh literature scout](5947c238-52e8-45ff-b96c-98cf93a49e97)**, flagged as a genuine conflict in Moderator notes below

---

## Tier 3 — Worth tracking, not urgent

- No perception-check gate before Format 1's GOP scoring (can't distinguish "can't hear it" from "can't produce it") — clinical practice tests this; the app's pipeline doesn't. [Phonetics audit]
- No listener-training / co-constructed-intelligibility mechanic anywhere — every format is speaker-centric, but the literature treats intelligibility as co-constructed. [Phonetics audit]
- ASR bias against disfluent speech isn't one of the three "cheap flags kept now" in §4b, despite affecting every L2 speaker to some degree, not just clinical stuttering. [Phonetics audit]
- Connected-speech *production* training is conditional ("if scripts include connected-speech phrases"), not a requirement. [Phonetics audit]
- Segalowitz's third fluency construct (*perceived* fluency) is silently substituted with intelligibility rather than separately measured. [Cognitive fluency audit]
- Working-memory/dual-task cost is named as a barrier but two live mechanics ("predict your own score," mid-conversation drill triggers) add exactly this kind of concurrent cognitive load with no stated mitigation. [Cognitive fluency audit]
- No fossilization-risk detection layer beyond incidental spaced review, despite the adult target population being at elevated documented risk for this specific failure mode. [SLA audit]
- The "productive confusion" connected-speech mechanic (AI deliberately uses slang to create a comprehension breakdown) is in unaddressed tension with the spec's own stated rationale elsewhere for post-session-only feedback ("reduces mid-flow anxiety, the dominant barrier") — deliberately engineering a live breakdown moment on the mic axis is a different design axis than feedback timing, and the two aren't reconciled. [Accessibility re-audit]
- L1-taper is SLA-justified (which language is rehearsed) on a genuinely different axis from the nativeness-vs-intelligibility debate (which accent is targeted) — not a hard contradiction, but the spec doesn't apply its own usual scrutiny of native-norm framing to this specific mechanic. [Ethics audit]
- "AI pushback should be realistically assertive" is logged as resolved, but no study tested deliberate AI disagreement specifically on an anxious, insecure population — evidence supports the instinct in general, not this specific population. [Ethics audit]
- No dependency/attachment-displacement metric anywhere in an otherwise exhaustive 30+-metric catalog, despite "reduced real-world socialization" being the specific named outcome in the most relevant new study (MIT/OpenAI RCT). [Ethics audit]
- No plan for relationship-rupture/discontinuation if Format 2 succeeds at feeling human enough to matter to a user emotionally. [Ethics audit]

---

## New literature landscape (not previously in either research doc)

**AI-companion dependency (entirely new body of research, most consequential new find of the audit):**
- Fang, Liu, Danry et al. (2025), MIT Media Lab/OpenAI 4-week RCT (n=981) — high-intensity chatbot use correlates with loneliness, dependence, reduced real-world socialization. [media.mit.edu](https://www.media.mit.edu/publications/how-ai-and-human-behaviors-shape-psychosocial-effects-of-chatbot-use-a-longitudinal-controlled-study/)
- Neural-steering-vector RCT (N=3,532) — moderate relationship-seeking AI maximizes attachment/appeal; heavier use confers no added well-being benefit. [arxiv:2512.01991](https://www.arxiv.org/pdf/2512.01991)
- Skjuve et al., longitudinal Replika study — genuine attachment forms via Social Penetration Theory dynamics; relationship rupture causes real distress. [ScienceDirect](https://www.sciencedirect.com/science/article/pii/S1071581922001252)
- Tobbi (2026) — the single closest real-world precedent to Format 2: Algerian EFL students using Replika for English practice, documenting the exact mechanism (availability, repetition, judgment-free environment) that produces attachment. [JSSAL](https://www.jssal.com/index.php/jssal/article/view/247)
- California SB 243 (effective Jan 1, 2026) — first US companion-chatbot-specific statute. [Jones Walker LLP](https://www.joneswalker.com/en/insights/blogs/ai-law-blog/ai-regulatory-update-californias-sb-243-mandates-companion-ai-safety-and-accoun.html)
- FTC Section 6(b) inquiry into AI companion chatbots (Sept 2025). [FTC](https://www.ftc.gov/news-events/news/press-releases/2025/09/ftc-launches-inquiry-ai-chatbots-acting-companions)
- *Garcia v. Character Technologies* and related litigation, settled Jan 2026. [AP News](https://apnews.com/article/ai-chatbot-lawsuits-character-google-fbca4e105b0adc5f3e5ea096851437de)

**Platform/technical:**
- Apple App Review Guideline 2.5.4 + real developer-forum confirmation that CallKit/PushKit misuse for non-telephony features is a live rejection risk. [Apple Developer Forums](https://origin-devforums.apple.com/forums/thread/817976)
- Park (2026), ACL BEA — the primary source for the "82% ASR auto-correction" figure; its own proposed remedy still misses ~3/4 of severe mispronunciations. [ACL Anthology](https://aclanthology.org/2026.bea-1.23/)
- Apple SpeechAnalyzer (iOS 26) — major on-device WER improvement, but non-native/accent performance remains untested even by outside developers. [get-inscribe.com](https://get-inscribe.com/blog/apple-speech-api-benchmark.html)

**SLA / pedagogy:**
- Kang (2025) — AI conversation beat peer conversation on FLSA/WTC in a head-to-head RCT. [kasell.or.kr](http://journal.kasell.or.kr/xml/46430/46430.pdf)
- Tsunemoto/Trofimovich self-assessment-calibration research — the real, mixed evidence base behind "predict your own score." [cambridge.org](https://www.cambridge.org/core/journals/applied-psycholinguistics/article/selfassessment-of-second-language-comprehensibility-the-roles-of-peerassessment-and-metacognition/B8D33433CD7B2FD10E1B56257113E5B9)
- Combined formulaic-sequence + spaced-retrieval + oral-fluency study — the single most direct piece of evidence for the spec's combined drill+scheduling design. [elt.tabrizu.ac.ir](https://elt.tabrizu.ac.ir/article_9631.html)
- Journal of Pedagogical Research (2025) — first dedicated FLSA-specific meta-analysis (g=0.522, medium effect, weaker than general-population anxiety-treatment effects). [ijopr.com](https://www.ijopr.com/article/the-effect-of-intervention-studies-on-foreign-language-speaking-anxiety-a-meta-analysis-study-16361)

**Phonetics:**
- Wells (2006), *English Intonation* — the real linguistic framework ("3Ts") for function-based prosody scoring. [archive.org](https://archive.org/stream/EnglishIntonation/English-Intonation_djvu.txt)
- 2024 HVPT meta-analysis (g=0.92). [Cambridge Core](https://www.cambridge.org/core/journals/studies-in-second-language-acquisition/article/high-variability-phonetic-training-hvpt-a-metaanalysis-of-l2-perceptual-training-studies/6ABB8C1F32D88D53EA8D05A4565E76F6)
- 2025/2026 SpeechLLM prosody-scoring results (PCC ~0.8) — but only on scripted read-aloud (Format-1-shaped tasks), not open-ended speech. [arXiv:2509.16876](https://arxiv.org/pdf/2509.16876)

---

## Moderator Pass — Blind Spots, Conflicts, Over-Consensus

### Unknown unknowns (raised by no persona)

1. **The best-evidenced format is the least prioritized one.** Every persona independently found Format 1 (scripted read-aloud) to be the most literature-validated, lowest-risk format across every lens — SLA, phonetics, cognitive, and technical. Yet it is explicitly not the MVP; Format 2, which carries the platform-policy risk, the regulatory risk, the unmodeled-cost risk, and the weakest direct evidentiary match for its own justifying theory, is. No persona was asked "should the MVP prioritization itself be revisited," because each was scoped to audit decisions within their lens rather than across the format-prioritization decision itself. This is worth a deliberate, explicit re-litigation, not an assumption that the original MVP call still holds now that all of Tier 1 is known.
2. **Regulatory contagion beyond California.** The ethics audit found SB 243 (California-specific) and an FTC inquiry (federal, cross-jurisdiction). No persona checked whether other states have companion-chatbot bills pending, or whether the EU AI Act's "manipulative design" provisions could independently reach Format 2's "feel human, sustain engagement" design goals. This matters because "avoid California, ship everywhere else" — if that's an implicit plan — may not actually de-risk this.
3. **Instrumentation-privacy compounding.** The Metrics Catalog captures granular behavioral data (hesitation location, code-switch timing, filler-word rate, session-frequency patterns) at a level of detail that, combined with SB 243-style disclosure requirements and the new companion-chatbot regulatory attention, may itself need explicit consent/disclosure framing that goes beyond the "process-and-delete audio" privacy decision already made. No persona connected the (already-decided) audio-retention policy to the (newly-discovered) regulatory category Format 2 now falls into — these were researched by different personas and never cross-referenced.
4. **Build-vs-buy was never asked.** No persona examined whether the conversational-AI layer for Format 2 (ASR+LLM+TTS orchestration) should be built on an existing voice-AI platform vendor rather than custom-built — relevant given the cost/battery findings, and given TalkPal/Loora/Praktika are already-built competitors whose infrastructure choices might be informative.

### Conflicts between panelists

1. **Non-sycophancy: SLA-justified vs. ethics-flagged as untested for this population.** The SLA audit treats "genuine, non-sycophantic AI" as load-bearing for the Interaction Hypothesis (disagreement drives negotiation-of-meaning). The ethics audit independently found the *identical* design choice is evidence-supported in general (sycophancy promotes dependence) but has never been tested specifically on an anxious, insecure population, where AI pushback risks triggering frustration or feeling judged. Both personas are right from their own lens — the tension is real, not resolvable by picking a side. **Practical read: the SLA case is for disagreement-in-service-of-a-task; the ethics risk is for disagreement-in-a-relationship-simulating-context. If Format 2 shifts toward more structured, task-based interaction (per the SLA audit's own C1 finding), this may resolve both concerns at once** — a more task-oriented AI has natural grounds to disagree (task facts) without the same "my AI friend is judging me" framing risk.
2. **"AI beats human facilitation on anxiety" (solid) vs. "AI conversation reduces anxiety in absolute terms" (contested).** Multiple personas cite the same 2025 Frontiers study (fpsyg.2025.1745942) as support for excluding peer feedback — that comparison is solid. But the fresh-literature-scout found the newest 2025–2026 meta-analyses directly disagree on whether AI conversation reduces anxiety at all in absolute terms (one large pooled effect, one null result on anxiety specifically). **The spec currently conflates these two distinct claims.** "AI is less anxiety-inducing than a human evaluator" is well-supported and justifies the human-in-the-loop decision as-is. "Ambient AI conversation will make my anxious user's anxiety go away" is not yet supported and should not be an implicit assumption baked into Format 2's design without in-product anxiety instrumentation to check it empirically.
3. **Spacing nuance is under-resolved across three personas.** The SLA audit found spacing-interval optimization doesn't matter much (Kakitani & Kormos). The cognitive-fluency audit found massed practice specifically wins for short-term breakdown-fluency, contradicting a blanket spacing rule. The fresh-literature-scout found one small (N=8) study directly supporting spaced retrieval for oral fluency. None of these actually contradict each other once separated by outcome (any spacing beats massing generally; interval doesn't need fine-tuning; but for pure short-term pause-reduction on a known drill target, massed still wins) — but the current spec's single blanket rule doesn't reflect this nuance, and no persona was positioned to state the resolved, combined version. Stated here for the first time: **spacing should be the default for anything meant to transfer or retain; massed repetition is defensible specifically for a single drilling session targeting immediate pause-reduction on a just-diagnosed error, with a return to spaced scheduling for subsequent reinforcement.**

### Over-consensus / rabbit holes

1. **Every persona independently landed on YELLOW.** Given the severity of some individual findings (App Store rejection risk; active FTC inquiry; a mislabeled "RESOLVED" metric with a documented harm pathway), it's worth asking whether "YELLOW" undersells the actual risk when read across all seven reports together rather than one at a time. Each persona was scoped narrowly and reasonably called their own narrow lens YELLOW — this is not a flaw in any individual audit, but the Moderator's job is exactly to check whether independently-reasonable moderate verdicts compound into something worse in aggregate. **They do, specifically for Format 2 as currently specced** (see TL;DR).
2. **Genuine, non-suspicious convergence:** intelligibility-over-nativeness framing, individualized diagnosis, functional-load weighting, and the Connected Speech Challenge were independently praised by multiple personas using different fresh sources. This is not groupthink — each persona found separate corroborating evidence via independent research, which is exactly the signal that should increase confidence rather than raise suspicion.
3. **Possible rabbit hole:** the phonetics audit's deep dive into Wells' 3Ts framework and CTC-GOP computational-cost papers is unusually technical relative to how small a piece of the product "Say It Like You Mean It" currently is. The underlying finding (ground it in a real framework, don't ship ahead of the accessibility review) is worth acting on; the specific citation depth on this one activity is disproportionate to its product weight and shouldn't set the bar for how deeply every future feature needs to be sourced.

---

## Verdict by lens

| Lens | Verdict | One-line why |
|---|---|---|
| SLA & Applied Linguistics | 🟡 Yellow | Most decisions hold up or are now better-supported than before; but the MVP-first format's own justifying theory (Interaction Hypothesis) argues for a task structure it doesn't implement. |
| Phonetics, Prosody & Clinical SLP | 🟡 Yellow | Strong overall architecture; two decisions (biofeedback fade, prosody scoring) overclaim their clinical precedent, and the strongest-evidenced technique (HVPT) is underprioritized. |
| Cognitive Fluency & Psycholinguistics | 🟡 Yellow | Correct core framework; the spec's most novel metric ("Gap 2") is labeled more confidently than the evidence supports. |
| Speech-Tech, ASR & Platform Feasibility | 🟡 Yellow | Segmental-ASR claims check out against primary sources; the CallKit architecture is a real, fixable rejection risk, and Format 2 has no cost/battery model. |
| Sociolinguistics, Ethics & AI-Companion Risk | 🟡 Yellow | Accent-ethics framing is the strongest-grounded part of the whole spec; Format 2's companion-app design sits in an unresearched, fast-moving legal/psychological hazard category. |
| Accessibility & Neurodivergence (drift check) | 🟡 Yellow | Three cheap flags are well-designed; three later decisions (Understood?, Gap 2, Format 2 spontaneity) each land on a specific, already-documented risk without being checked against it. |
| Fresh Literature Scout | 🟡 Yellow | Nothing found invalidates the core approach; surfaces real competitors, a contested anxiety-mechanism claim, and a direct counter-example for one mechanic. |
| **Moderator (cross-cutting)** | **🟡→🔴 for Format 2 specifically; 🟢 for Formats 1 & 3** | Individually-reasonable YELLOWs compound into a real blocker when three of them land on the same MVP-first format. |

---

## Recommended next steps

1. Treat Tier 1 as a punch list to resolve before any Format 2 architecture work: CallKit→`audio` background mode swap, a minimum age + crisis-referral + disclosure design, a redesign or removal of "Understood?" pending a disfluency-aware variant, downgrading "Gap 2" from RESOLVED to exploratory, and a real cost/battery model.
2. Decide, explicitly, whether Format 1's stronger evidentiary grounding should change the MVP sequencing now that Format 2's risk profile is fully known (Unknown Unknown #1) — this wasn't examined by any single persona and is arguably the single highest-leverage open question from this whole audit.
3. Tier 2 items are best resolved opportunistically as each format gets detailed — none are blocking, but several (HVPT promotion, WTC metric, accuracy feedback for Format 2, the info-gap task gap) are cheap wins with strong evidence behind them.
