# Literature Review: The Science of Speaking Better English as a Non-Native Speaker

**Purpose of this document:** This is a pure research audit — a survey of academic, clinical, and applied literature on how people learn to speak a second language (with a focus on English) more clearly, fluently, and confidently, what problems they run into, and how professionals remedy those problems. It contains **no product or feature decisions**. It exists so that a future design phase can point to a specific, cited finding for every feature it proposes, rather than guessing.

**Method:** This review was built as a "scoping roundtable" — seven independent research lenses did grounded web research in parallel (each required to cite a real source for every claim, or explicitly flag it as an unverified assumption), followed by a moderator pass to surface blind spots, conflicts, and over-consensus across all seven. The seven lenses:

1. Second Language Acquisition (SLA) & Applied Linguistics Theory
2. Phonetics & Prosody (pronunciation/intonation specifically)
3. Clinical Speech-Language Pathology / Accent Modification
4. Cognitive & Psycholinguistics of Real-Time Fluency
5. Public Speaking, Rhetoric & Communication Coaching
6. Sociolinguistics & Accent Bias / Intelligibility Ethics
7. Speech-Tech & Existing App Landscape (what's technically possible today)

Confidence ratings (STRONG / MODERATE / WEAK) reflect each lens's own assessment of its evidence base, not a marketing claim. Where sources disagree, both sides are shown — conflicts are not smoothed over.

---

## TL;DR — What the Literature Says, in Ten Points

1. **Pronunciation/speaking instruction genuinely works** — this isn't in doubt. The field's benchmark meta-analysis found a large effect (*d* = 0.89) for pronunciation instruction generally (Lee, Jang & Plonsky, 2015). The open question is *which* techniques and *which* features to prioritize.
2. **"Sounding native" is the wrong target; "being understood" is the right one.** Decades of research (Munro & Derwing) show accentedness, comprehensibility, and intelligibility are only partially correlated — a heavy accent can be perfectly intelligible, and a light accent can still be hard to understand. The academic consensus (Levis's "Intelligibility Principle") has moved decisively away from accent-elimination.
3. **Not all pronunciation errors are equal — some matter far more than others.** The Functional Load Principle (Munro & Derwing, 2006) shows that a single high-functional-load error (e.g., /l/-/n/) hurts comprehension more than three low-functional-load errors (e.g., "th" sounds) combined. Word/sentence stress placement causally damages intelligibility for *both* native and non-native listeners (Field, 2005).
4. **Real-time fluency is a distinct cognitive bottleneck from pronunciation.** Levelt's speech-production model (adapted for bilinguals by de Bot and Kormos) explains why non-native speakers hesitate, retrieve words slowly, and "translate in their head" — it's a working-memory and automaticity problem, not (only) a knowledge problem. Specific techniques (4/3/2, task repetition, pre-task planning, formulaic-chunk training) have documented, if narrow, effects.
5. **Clinical/professional accent-modification methodology is more rigorous than consumer apps assume — but its evidence base is thin.** ASHA-credentialed practice uses individualized diagnosis (segmental, suprasegmental, language-level) and instrumented biofeedback (visual-acoustic, ultrasound). But the field's own systematic review found **zero randomized controlled trials** across 26 studies, and whether clinician-delivered techniques transfer to unsupervised app use is largely untested.
6. **Public-speaking-specific anxiety treatments (CBT, systematic desensitization, VR exposure) are strongly evidenced** (large effects, replicated meta-analyses) — but almost none of that evidence was generated on *non-native speakers specifically*, whose anxiety is measurably compounded by language-competence fears on top of ordinary stage fright.
7. **Current AI/ASR speech technology is good at scoring individual sounds and weak at scoring intonation/prosody.** Multiple independent lenses converged on this same technical limitation from different angles — it's one of the most solidly cross-validated findings in this review (see Cross-Cutting Finding #1 below).
8. **ASR itself is measurably less accurate for non-native and tonal-L1 speakers — and the gap appears to be widening, not closing, as models get bigger.** This is a foundational technical risk for any product whose core mechanic is "AI listens to you and scores you."
9. **The ethics of this entire product category are actively, currently contested in the scholarly literature** — not a settled matter. Recent work (2024) explicitly criticizes "AI accent-altering technology" as risking cultural homogenization and reinforcing the idea that the burden of fixing accent-based discrimination belongs to the speaker rather than the biased listener.
10. **No study found tested whether AI/app-based practice can substitute for real human interaction** in developing spoken fluency — every source that touched this question described AI tools as a supplement or low-stakes rehearsal space, never a replacement.

---

## 1. How Adults Acquire Spoken Proficiency (SLA & Applied Linguistics Theory)

**Confidence: MODERATE.** Core mechanisms are well-replicated; the newest, most product-relevant question (can AI substitute for human interaction?) is unresolved.

### Key findings
- **Comprehensible input is necessary but not sufficient.** Krashen's Input Hypothesis (*i+1*) explains how exposure drives acquisition, but Swain's research on Canadian French-immersion students — who got years of rich input yet stayed clearly non-native in production — proved input alone doesn't build spoken competence (Krashen, *Principles and Practice in SLA*; Swain, 1985, in Gass & Madden).
- **Producing output is a distinct, necessary mechanism.** Swain's Output Hypothesis identifies four functions of speaking practice: noticing your own gaps, testing hypotheses via trial-and-feedback, metalinguistic reflection, and fluency-building through repetition (Swain & Lapkin, 1995, *Applied Linguistics*, [doi:10.1093/applin/16.3.371](https://doi.org/10.1093/applin/16.3.371)).
- **Negotiating meaning in real conversation drives acquisition beyond input/output alone.** Long's Interaction Hypothesis: when communication breaks down, clarification requests and confirmation checks direct a learner's attention to form in a way that solo practice cannot ([Wikipedia overview](https://en.wikipedia.org/wiki/Interaction_hypothesis)).
- **Corrective feedback has a large, durable effect** — and *how* you correct matters. Meta-analyses converge on effect sizes around 0.6–1.16 (Russell & Spada 2006; Li 2010; Lyster & Saito 2010, [doi:10.1017/s0272263109990520](https://doi.org/10.1017/s0272263109990520)). **Prompts (pushing the learner to self-correct) outperform recasts (silently modeling the correct form)**, especially for lower-proficiency learners (Ammar & Spada, 2006, [doi:10.1017/s0272263106060268](https://doi.org/10.1017/s0272263106060268)) — likely because recasts are often not even perceived as corrective (Lyster, 1998).
- **Fluency develops through skill-acquisition stages** — declarative → procedural → automatic (DeKeyser's Skill Acquisition Theory) — and is heavily supported by **formulaic chunks** retrievable as whole units rather than built word-by-word ([Frontiers in Psychology, 2022](https://doi.org/10.3389/fpsyg.2022.1012225)).
- **Immersion beats classroom instruction specifically for oral fluency.** Freed, Segalowitz & Dewey (2004) found intensive immersion produced the largest fluency gains, study abroad smaller-but-real gains, and classroom-only instruction essentially none ([doi:10.1017/s0272263104262064](https://doi.org/10.1017/s0272263104262064)).

### Documented problems/barriers
- **Fossilization.** Selinker's Interlanguage Hypothesis (1972): adult learners develop an autonomous linguistic system that typically stalls short of native-like competence — Selinker estimated only ~5% of adult learners avoid this.
- **Insufficient output opportunity in instructed settings.** Classroom-discourse research repeatedly finds Teacher Talk Time eating 60–90% of class time, leaving minimal room for learners to actually speak (e.g., one Pakistani ESL classroom study found 77% teacher talk vs. 23% student talk, averaging ~23 seconds of speaking time per student per lesson).
- **Affective filter / speaking anxiety.** Krashen's Affective Filter Hypothesis, operationalized in MacIntyre et al.'s Willingness to Communicate model: anxiety and low self-confidence can suppress speech production even in learners with strong linguistic competence ([doi:10.1111/j.1540-4781.1998.tb05543.x](https://doi.org/10.1111/j.1540-4781.1998.tb05543.x)).
- **L1 phonological transfer** funnels L2 sounds into existing L1 categories when the L1 lacks the distinguishing feature (classic case: Japanese /r/-/l/, which is a *perceptual* category problem before it's a production one).

### How professionals remedy this
- **Pushed, communicative (two-way/information-gap) output tasks** generate significantly more negotiation-of-meaning than one-way tasks (Long, 1980).
- **Explicit corrective feedback via prompts**, using Lyster & Ranta's (1997) taxonomy (clarification requests, repetition, metalinguistic feedback, elicitation).
- **Time-pressured, deliberate practice** (e.g., the "4/3/2" technique) plus explicit teaching of high-frequency formulaic sequences.
- **Prioritizing intelligibility features (functional load, suprasegmentals) over blanket "accent reduction."**

### Open questions / contested
- **The Critical Period Hypothesis is statistically contested.** A 2013 PLOS ONE reanalysis found CPH-predicted age discontinuities were "not cross-linguistically robust" under proper regression methods ([doi:10.1371/journal.pone.0069172](https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0069172)) — age is a strong probabilistic risk factor, not a hard ceiling.
- **The dominant modern L2 motivation framework (L2 Motivational Self System) is undergoing a "validation crisis"** — critics argue its "ought-to L2 self" component shows near-zero correlation with actual achievement (*r* = –.048) and call for halting its use until better validated ([Studies in SLA](https://www.cambridge.org/core/journals/studies-in-second-language-acquisition/article/validation-crisis-in-the-l2-motivational-self-system-tradition/B3C44AE6CCAB93C1C68605A5BFBBF34C)). **Relevant if any future feature leans on "future self" motivational framing.**
- **Can AI/chatbot practice substitute for human interaction?** Every study found is short-duration (6–10 weeks), reduces *situational* anxiety but often not *trait* anxiety, and explicitly frames AI as a rehearsal supplement, not a replacement for the negotiation-of-meaning mechanism central to Long's Interaction Hypothesis. **Unresolved.**
- **Do apps actually build speaking skill, or mainly receptive/vocabulary skill?** Meta-analyses directly conflict here — some find large positive effects of mobile-assisted learning on speaking specifically; a head-to-head Duolingo-vs-classroom study found no clear speaking advantage for the app group, while classroom was *better* for listening.

---

## 2. Pronunciation & Intonation: What Actually Matters for Being Understood (Phonetics & Prosody)

**Confidence: MODERATE-TO-STRONG**, unevenly distributed — the foundational constructs are very well replicated; specific technique-vs-technology comparisons are not.

### Key findings
- **Pronunciation instruction has a large aggregate effect** (*d* = 0.89 within-group; Lee, Jang & Plonsky, 2015 meta-analysis of 86 studies, [doi:10.1093/applin/amu040](https://doi.org/10.1093/applin/amu040)) — larger for longer interventions and treatments that include feedback.
- **The Functional Load Principle predicts which errors matter.** Munro & Derwing (2006) empirically confirmed that high-functional-load consonant substitutions (e.g., /l/-/n/) significantly hurt comprehensibility, while low-functional-load ones (e.g., θ→t/f/s, the "th" sounds many learners fixate on) barely register — **and a single high-FL error is rated worse than three low-FL errors combined** ([doi:10.1016/j.system.2006.09.004](https://doi.org/10.1016/j.system.2006.09.004)). Replicated under ELF (non-native-to-non-native) conditions in 2023 ([doi:10.1515/CJAL-2023-0101](https://www.degruyterbrill.com/document/doi/10.1515/CJAL-2023-0101/html)).
- **Word/sentence stress placement causally damages intelligibility for *everyone*, not just non-native listeners.** Field (2005) experimentally manipulated stress in disyllabic words and found misplaced stress significantly impaired transcription accuracy for both native and non-native listeners — because listeners use stress to predict upcoming words ([doi:10.2307/3588487](https://doi.org/10.2307/3588487)).
- **High-Variability Phonetic Training (HVPT)** — training perception with multiple talkers across multiple phonetic contexts — produces durable (3–6 month retained), generalizable perceptual gains that transfer to production, though the perception→production correlation is only modest at the individual level (Logan, Lively & Pisoni's classic Japanese /r/-/l/ series; meta-analysis found 10.5% production gains on trained items).
- **Connected speech (linking, reduction, assimilation, elision) is primarily a *listening* problem for L2 speakers**, not just a production one. A 2026 study found L2 listeners' transcription accuracy dropped 13–49 percentage points from citation-form to connected speech — far more than native listeners.
- **Visual/acoustic feedback (spectrograms, pitch-tracking) reliably improves intonation and often segmental production too** (Hardison 2004; extended to Praat visualization and 3D spectrograms in recent EuroCALL work).
- **ASR-based pronunciation training has a real, medium effect (*g* = 0.69) — but is currently much better at segmentals (*g* = 0.82) than suprasegmentals (*g* = 0.37)** ([doi:10.1017/s0958344023000113](https://doi.org/10.1017/s0958344023000113)). *(See Cross-Cutting Finding #1 — this is independently corroborated by two other lenses.)*

### Documented problems/barriers
- L1-specific segmental transfer patterns are well-documented for several L1 groups: Japanese /r/-/l/ (perceptual, not just motoric), Mandarin/Cantonese coda deletion & cluster simplification, Spanish tense/lax vowel confusion (Spanish speakers default to duration cues rather than the spectral cues English relies on).
- Intonation misuse causes real miscommunication beyond "sounding foreign" — Wennerstrom (1994) found L2 speakers don't reliably use pitch to signal discourse relationships (contrast, given/new information) the way native speakers do; Pickering found Chinese L2 speakers don't reliably use pitch-mismatch to signal disagreement, a genuine pragmatic/social gap.

### How professionals remedy this
- Minimal-pair training (perception and/or production, ideally combined); High-Variability Phonetic Training for hard categorical contrasts; visual/acoustic feedback tools; explicit connected-speech instruction (large effects in classroom RCTs, *d* = 1.14–1.19); contrastive-analysis-by-L1 curriculum design; Celce-Murcia's 5-phase communicative framework (description → discrimination → controlled practice → guided practice → communicative practice).
- **Shadowing is popular but contested** — a 2025 Oxford systematic review of 44 studies found shadowing reliably helps fluency/prosody but its effect on segmental accuracy is "inconclusive," and one study found *perception* improved with daily shadowing even without instruction, while *production* did not improve in a self-learning condition — a direct caution against assuming unsupervised shadowing loops are sufficient.

### Open questions / contested
- **Does prosody or segmental accuracy matter more for comprehensibility?** Direct disagreement in the literature itself (Derwing & Munro say prosody is more potent; Koster & Koet and Fayer & Krasinski found the opposite) — likely depends on L1, task, and listener familiarity.
- **The Lingua Franca Core's exclusions are contested** — Jenkins excludes word stress from her "core" features, directly in tension with Field's (2005) finding that stress errors demonstrably hurt intelligibility.
- Most pronunciation research relies on **controlled, read-aloud tasks**, not spontaneous speech — a field-wide acknowledged gap directly relevant to an app targeting "everyday, real-time speaking."

---

## 3. How Speech Professionals Diagnose and Remediate Accent (Clinical / Speech-Language Pathology)

**Confidence: MODERATE, dropping to WEAK for the app-transfer question specifically.**

### Key findings
- **Accent modification is explicitly not disorder treatment.** ASHA's own guidance states accents are "not a communication disorder," and that this is an *elective* service ([ASHA Practice Portal](https://www.asha.org/practice-portal/professional-issues/accent-modification/)).
- **Clinical assessment covers three separate domains**: segmentals, suprasegmentals, and language-level factors (syntax/morphology/pragmatics) that can masquerade as pronunciation errors (e.g., a missing plural morpheme misread as "final consonant deletion").
- **Segmental accuracy and prosody drive *accentedness* judgments; comprehensibility is additionally shaped by speech rate, vocabulary, grammar, and discourse structure** (Trofimovich & Isaacs, [doi:10.1017/s0142716414000502](https://doi.org/10.1017/s0142716414000502)).
- **The field's own efficacy evidence is explicitly rated low quality.** A systematic review of 26 healthcare-sector accent interventions (n=964) found 24/26 reported benefit — but **zero randomized controlled trials**, every study used a *different* outcome measure, and cross-study comparison was rated "infeasible" (Gu & Shah, 2019, [doi:10.31486/toj.19.0028](https://doi.org/10.31486/toj.19.0028)).

### Documented problems/barriers (diagnostic categories professionals actually use)
- Segmental substitution/omission driven by gaps in the learner's L1 phonemic inventory.
- Contrastive-analysis-predictable interference patterns (the "moderate" Contrastive Analysis Hypothesis — a diagnostic heuristic, not a deterministic forecast).
- Suprasegmental/prosodic deficits, assessed as their own category because they independently affect intelligibility.
- **Perceptual deficits underlying production errors** — clinicians test whether a learner can even *hear* a contrast before assuming the problem is purely motor (e.g., Bradlow et al.'s work on Japanese listeners and /r/-/l/).
- **Self-monitoring/metacognitive deficits** — a learner's real-time ability to detect their own errors is treated as a distinct weak point requiring explicit training.
- **Pragmatic errors that present as phonological ones** — e.g., an L1 that permits indirect requests can cause miscommunication misdiagnosed as an "accent problem."

### How professionals remedy this
- **Individualized, assessment-driven planning** (never a generic curriculum) using formal instruments like the Comprehensive Assessment of Accentedness and Intelligibility (CAAI) or the older Compton P-ESL method.
- **Named drill techniques**: listen-and-imitate, explicit articulatory-placement diagrams, auditory discrimination/minimal pairs, mirrors and vowel charts, tongue twisters, developmental sequencing, self-recording review.
- **Instrumented biofeedback**: visual-acoustic feedback (real-time formant display vs. a target template — e.g., the free **staRt** app), ultrasound tongue imaging (with a documented protocol that deliberately fades from immediate to delayed feedback across sessions to build learner self-evaluation), and electropalatography — all validated in small-N studies for specific target sounds (chiefly /r/, /l/, French vowels), **explicitly designed and studied with a clinician present** to select targets and interpret the display.
- **Motor-learning-informed practice structuring**, borrowed from the motor-speech-disorder literature: blocked practice for faster short-term gains, random/interleaved practice for better next-day retention; immediate feedback speeds acquisition but can create dependency, delayed/faded feedback promotes internal error-detection.
- **Explicit prosody protocols** — e.g., bilingual metacognitive instruction bridging L1 and L2 stress awareness was the *only* tested condition that produced gains in **spontaneous, extemporaneous speech** rather than just scripted read-aloud — directly relevant to an "everyday speaking" goal.
- **Listener training** — some programs explicitly coach the learner's conversation partners on effective-listening strategies, reflecting that intelligibility is co-constructed, not a purely speaker-side deficit.

### Open questions / contested
- **Is accent modification itself ethically legitimate?** ASHA's own Practice Portal states the service "has been criticized for perpetuating stigma... and encouraging assimilation... rather than embracing diversity of language." *(See Cross-Cutting Finding #2 — independently raised by the sociolinguistics lens too.)*
- **The field has no regulatory gatekeeping.** Unlike disorder treatment, accent modification has "no specialized license or accreditation requirements and no guiding ethical code of conduct," per Gu & Shah (2019) — a genuine, citable structural weakness in the whole professional category this app is adjacent to.
- **Does clinician-delivered biofeedback transfer to unsupervised app use?** This is the single most consequential open question for a mobile-app concept, and the evidence is thin/mixed: a systematic review of mobile-assisted pronunciation apps found only *half* of studies showed significant production gains; an AI-feedback (ChatGPT) study showed durable gains over static content; but a review of clinically-marketed speech-therapy apps found only 2 of the top 10 had *any* published clinical-effectiveness data.

---

## 4. The Real-Time Bottleneck: Why Thoughts Don't Come Out Fluently (Cognitive & Psycholinguistics)

**Confidence: MODERATE.** The architecture is solid; specific-technique evidence is small-sample and the transfer-to-new-context question is a major, acknowledged gap.

### Key findings
- **Levelt's (1989) modular speech-production model** (Conceptualizer → Formulator → Articulator → Monitor) is the dominant architecture. **De Bot (1992)** adapted it for bilinguals: macro-planning is language-independent, but each language has its own Formulator, drawing on a single shared mental lexicon ([doi:10.1093/applin/13.1.1](https://doi.org/10.1093/applin/13.1.1)). **Kormos (2006)** extended this into a full bilingual model with declarative/procedural knowledge stores.
- **Segalowitz (2010)** split "fluency" into three distinct constructs — **cognitive fluency** (underlying mental efficiency), **utterance fluency** (measurable temporal properties: speed, pausing), and **perceived fluency** (listener judgment) — now the field standard.
- **Automaticity is qualitative, not just "faster."** True automatization shows up as reduced variability in reaction times ("ballistic" execution), distinguishable from mere speed-up under continued conscious effort (Segalowitz & Segalowitz, 1993).
- **Bilinguals show slower lexical retrieval in *both* languages** than monolinguals — explained by a frequency-lag hypothesis (each language used less, weakening links) and/or a competition hypothesis (the non-target language interferes during selection) — a robust, replicated finding ([PMC5999048](https://pmc.ncbi.nlm.nih.gov/articles/PMC5999048/)).
- **Working memory constrains real-time L2 encoding** because L2 skills are only partially automatized and compete for the same limited attentional pool needed for conceptualization and self-monitoring.
- **Disfluency location reveals *where* processing breaks down**: mid-clause disfluencies link to lexical-retrieval difficulty, between-clause disfluencies to conceptual/macro-planning difficulty — different pause types index different points in the pipeline ([doi:10.1111/ijal.12472](https://doi.org/10.1111/ijal.12472)).

### Documented problems/barriers
- Lexical retrieval lag (robust, replicated across many studies).
- Cross-language lexical competition — even in one's dominant language, the untargeted language's translation-equivalent gets phonologically activated and must be actively suppressed.
- **Overuse of L1-mediated mental translation** — think-aloud studies find lower-proficiency learners routinely translate ideas from L1 before speaking, an extra processing step that decreases (but doesn't disappear) with proficiency.
- Language anxiety's link to fluency breakdown is **inconsistent across studies** — some find strong correlations, others find none, on near-identical designs, suggesting unmeasured moderating variables.

### How professionals remedy this
- **The 4/3/2 technique** (Maurice, 1983): same monologue, three listeners, shrinking time limits (4→3→2 min). Reliably increases speech rate, but produces a **consistent fluency-accuracy trade-off** — accuracy often stagnates unless explicit corrective feedback is added during the exercise (a 2024 study found adding accuracy-focused feedback to 4/3/2 improved both simultaneously, where 4/3/2 alone improved fluency only).
- **Task repetition** frees attentional resources for form rather than content — but **gains largely don't transfer to a new, unpracticed task** (a dedicated transfer study found no statistically significant transfer).
- **Strategic pre-task planning time** reliably increases fluency, lexical variety, and grammatical complexity — one of the most replicated task-condition findings in the field (Yuan & Ellis, 2003, [doi:10.1093/applin/24.1.1](https://doi.org/10.1093/applin/24.1.1), 771 citations).
- **Massed vs. distributed practice is a "double-edged sword"** — massed repetition boosts short-term fluency but produces more rote, verbatim repetition and worse transfer than spaced repetition.
- **Formulaic-chunk training** — deliberately teaching and drilling multiword sequences reduces real-time processing load because chunks are retrieved holistically rather than built word-by-word.

### Open questions / contested
- **No consensus on how to even measure fluency** — pause-length thresholds vary by study (200ms vs. 250ms vs. task-dependent), and different temporal measures don't consistently correlate with proficiency across different L2s.
- **Whether fluency-training gains transfer beyond the practiced task is a major, largely unresolved debate** — this is the single biggest risk for any drill-based app design: gains in the drill may not generalize to real spontaneous conversation.
- Whether "formulaic sequence" is even a coherent single psycholinguistic construct is actively disputed in recent scholarship.

---

## 5. Organizing Your Thoughts & Speaking with Confidence (Public Speaking, Rhetoric & Anxiety)

**Confidence: MODERATE overall — STRONG for anxiety treatment, WEAK-TO-MODERATE for organizational frameworks, WEAKEST for L2-specific anxiety interventions.**

### Key findings
- **Structured-argument frameworks (PREP: Point–Reason–Example–Point) measurably improve organized speaking** — a controlled study found mean scores rising from 39.50 to 66.00 (p<0.001) after training, grounded in cognitive-load theory and the primacy/recency effect.
- **Delivery mechanics causally shape perceived competence, independent of content.** Filler words reduce perceived competence, confidence, and trust ratings, scaling with disfluency count. Vocal variety (pitch range, intensity) is empirically linked to perceived charisma in acoustic analyses of business/political speech.
- **Narrative "transportation"** (Green & Brock, 1997) — audience absorption in a story reduces critical resistance and increases story-consistent belief change, validated across four experiments.
- **Communication apprehension is a broad, trait-like construct** (McCroskey), not just situational stage fright, measurable via the PRCA-24 instrument.
- **CBT for social/performance anxiety has strong, replicated efficacy**: a meta-analysis of 30 RCTs (N=1,355) found a large effect (Hedges' *g* = 0.74, rising to 1.11 at follow-up — a "sleeper effect") specifically for fear of public speaking, with technology-delivered interventions equally effective as face-to-face ([PMC6428748](https://pmc.ncbi.nlm.nih.gov/articles/PMC6428748/)).
- **Virtual Reality Exposure Therapy (VRET) is comparable to in-vivo exposure**, with a large effect (*g* ≈ −1.39 to −1.46) sustained up to 6 years post-treatment across multiple meta-analyses.
- **Non-native speech contains objectively more/different disfluencies than native speech** — more frequent, longer, and differently-placed pauses — a documented linguistic phenomenon, not just a perceptual one. Non-native speakers even partially retain L1-language disfluency patterns when speaking a third language.

### Documented problems/barriers
- **The commonly repeated "75-85% of people fear public speaking" statistic is not well-sourced.** The most rigorous epidemiological estimate (National Comorbidity Survey Replication) found 21.2% lifetime prevalence — a substantially lower, better-evidenced figure that should be preferred over the ubiquitous but undocumented "75%" claim.
- **Non-native speakers face a *compounded*, distinct anxiety burden** — Foreign Language Anxiety (fear of linguistic error/accent) stacks on top of general communication apprehension, producing an amplified fear response beyond native speakers' ordinary stage fright (systematic review of 36 studies). A meta-analysis of 99 effect sizes (N=14,128) found a moderate negative correlation between foreign-language-classroom anxiety and speaking-specific achievement.
- Rambling/disorganized impromptu speech and monotone delivery are both named, well-documented failure modes.

### How professionals remedy this
- **Impromptu-speaking frameworks** — Toastmasters teaches 8 named structures (PREP, Pendulum, Balance, Timeline, etc.) explicitly for organizing unplanned speech in real time.
- **Toastmasters' structured-practice + peer-evaluation model** shows consistent (though mostly small-N, uncontrolled) gains in confidence and filler-word reduction for both native and non-native speakers across multiple case studies.
- **Systematic desensitization** (Wolpe, 1958) was the first empirically validated treatment specifically for public-speaking performance anxiety (Paul's landmark 1966 RCT), with effects still superior at 2-year follow-up.
- **VRET applied specifically to L2 speaking anxiety** shows promise in early, small studies (13 East Asian ESL learners using a customizable VR public-speaking app showed significant Foreign Language Anxiety reduction after six sessions) but is not yet meta-analyzed at that scale.
- **AI conversation practice reduced both anxiety and improved speaking scores** in a small controlled study (N=60, 6 weeks, using Mondly) — but see the open questions below.

### Open questions / contested
- **Monroe's Motivated Sequence — despite being taught almost universally — has only one controlled experimental test, and it found *no* significant persuasion advantage** over disorganized alternatives (Micciche, Pryor & Butler, 2000). A canonical framework with weak evidence behind it.
- **Do general public-speaking-anxiety interventions (CBT, VRET) transfer their efficacy to L2-specific anxiety, or does the added linguistic-competence dimension need distinct treatment?** Almost all the strong RCT evidence is on native-speaker or general clinical populations; L2-specific studies are recent, small-N, and not yet RCT-grade. **This is the single largest evidence gap for an app targeting non-native speakers specifically.**
- The "PREP works" evidence is partly drawn from **written** argument-organization studies, not live spontaneous speech under time pressure — a meaningful construct gap for a real-time speaking app.

---

## 6. Whose "Better English"? The Nativeness-vs-Intelligibility Debate (Sociolinguistics & Ethics)

**Confidence: STRONG for the core empirical claims; MODERATE-TO-WEAK for the normative/ethical conclusions, which are an active scholarly disagreement, not settled fact.**

### Key findings
- **English is now a majority-L2 language.** ~1.5 billion speakers globally, only ~390 million of them L1 — meaning most real-world English communication is already non-native-to-non-native (English as a Lingua Franca).
- **Accentedness, comprehensibility, and intelligibility are empirically distinct, partially independent dimensions** (Munro & Derwing, 1995 and replications across four L1 groups in 1997, reaffirmed in a 2020 retrospective) — this is the single most load-bearing finding across this entire literature review.
- **The field's pedagogical consensus has explicitly shifted from "nativeness" to "intelligibility"** as the appropriate target (Levis, 2005). Jenkins' Lingua Franca Core operationalizes this by identifying only the features that actually matter for non-native-to-non-native intelligibility, explicitly *excluding* features long over-emphasized in "accent reduction" (e.g., "th" sounds, word stress, weak forms) — though her exclusions are themselves contested (see Section 2).

### Documented problems/barriers
- **Accent triggers measurable hiring discrimination independent of actual comprehensibility.** A meta-analysis of 139 effect sizes (N=4,576) found standard-accented candidates rated more hireable (*d* = 0.47) — and critically, **the bias was not significantly explained by how comprehensible the candidate actually was.** Bias was stronger for women and for foreign (vs. regional) accents.
- **Non-native-accented speech is judged less credible/truthful even when merely relaying someone else's words** — a "processing fluency" effect (harder-to-process speech gets misattributed to lower speaker credibility) that forewarning reduces but does not eliminate (Lev-Ari & Keysar, 2010).
- **U.S. courts have historically upheld accent-based employment decisions as "customer preference," functioning as discriminatory pretext** that would be illegal if applied to national origin or race directly (Lippi-Green's court-case analysis).
- **Accent anxiety/shame is a measurable psychological phenomenon tracking "native-like" aspiration specifically, not comprehensibility** — one EFL survey found 71.7% of learners worried about how others judge their accent, 63.0% had felt embarrassed because of it, and 56.5% believed native-like pronunciation was "essential."

### How professionals remedy this
- **The Lingua Franca Core** — teach only the features empirically shown to affect non-native-to-non-native intelligibility, paired with explicit "accommodation skills" training (adjusting speech in real time based on the listener), rather than fixing pronunciation to one fixed native target.
- **Functional-load-based prioritization** (Levis) — direct teaching time toward errors that actually cause misunderstanding.
- **ASHA has moved away from "accent reduction/elimination" terminology entirely**, explicitly citing the accentedness/intelligibility distinction, and frames the clinician's role as respecting learner autonomy while educating clients that a non-standard accent doesn't need "fixing" to be effective communication.
- **Anti-racist pronunciation pedagogy** (Ramjattan) goes further still, treating intelligibility as a *joint* speaker-listener responsibility and targeting institutional accent bias for advocacy rather than asking learners to individually accommodate discrimination.

### Open questions / contested — and this section matters disproportionately for product framing
- **A direct, current critique targets exactly this product category.** Cavazos et al. (2024, *Applied Linguistics*, [doi:10.1093/applin/amae002](https://doi.org/10.1093/applin/amae002)) explicitly criticizes AI-based "accent-altering technology" as reproducing "racial commodification and linguistic dominance" and promoting "global homogeneity through the elimination of linguistic diversity."
- **Client autonomy vs. structural critique is a genuine, unresolved tension**, not a terminology dispute: individuals have legitimate reasons to want an accent that doesn't cost them jobs or social ease, but critics argue that any individualized "fix the accent" product still leaves the discriminatory structure unaddressed and may legitimize the idea that the burden of change belongs to the speaker.
- **Whether "confident, clear spoken prose" can be defined independent of native-speaker prosodic norms is, as far as this research found, empirically untested** — most intelligibility research targets everyday conversational clarity, not the perceived-confidence dimension of public speaking specifically.

---

## 7. What Existing Apps & AI Can (and Can't) Do Today (Speech-Tech Landscape)

**Confidence: MODERATE.** Academic/technical findings are well cross-corroborated; specific vendor claims (ELSA's exact accuracy %, etc.) are marketing claims, not independently audited, and are flagged as such below.

### Key findings — how research has already become product
- **Goodness of Pronunciation (GOP) scoring** — an ASR posterior-probability confidence measure — is the backbone of most commercial phoneme-level feedback today (open-source in Kaldi; productized explicitly in **Microsoft Azure's Pronunciation Assessment API**, which separately scores Accuracy, Fluency, and an *optional, English-only* Prosody score).
- **ELSA Speak** runs its own Kaldi-based DNN models with dedicated pronunciation, intonation, and fluency scoring, claims 93.88% agreement with expert human raters within ±1 CEFR band *(vendor claim, not independently verified)*.
- **BoldVoice** pairs Hollywood dialect-coach video content with proprietary phoneme-level AI feedback, explicitly built because its founders said generic ASR "often fail[s] to capture the nuances required."
- **Duolingo has published peer-reviewed research** on a pronunciation scoring model explicitly built around **intelligibility rather than native-accent imitation** — a direct, disclosed product response to the Munro & Derwing/Levis academic consensus described in Section 6. Separately, its "Video Call" AI roleplay deliberately does *not* interrupt with real-time correction, prioritizing confidence-building.
- **Yoodli, Orai, Poised** operationalize *fluency/delivery* research (filler words, pace, energy) rather than phoneme-level pronunciation, mostly with an option for human coaches to layer feedback on top.
- **Speechling and Pimsleur represent the non-ASR end** — Speechling is explicitly hybrid (spaced-repetition drilling + mandatory human-coach feedback within 24h, because the founders don't consider automated scoring sufficient on its own); Pimsleur's entire method predates ASR, based purely on 1967 "graduated interval recall" spaced-repetition research.

### Documented problems/barriers
- **ASR is measurably worse for non-native and tonal-L1 speakers, and the gap is widening as models scale.** A 2025 study across ten modern ASR families (Whisper, Canary, Phi-4) found a "conformation bias": as models get larger and more accurate on L1 English, the *relative* gap for L2 speakers systematically **worsens**, disproportionately for tonal-L1 speakers. A root-cause paper argues part of this is a signal-processing artifact — standard mel-filterbank front-ends under-resolve the pitch band critical for tone discrimination by roughly 22x.
- **Modern ASR actively "corrects" learner mispronunciations before they can even be scored.** A 2026 study found that in 82.0% of a standard learner-speech corpus, a modern ASR system auto-corrected a mispronunciation to the *intended* word rather than transcribing what was actually said — because the ASR's language model optimizes for plausible language, not faithful acoustic transcription. **This is a structural limitation for any app trying to give phoneme-accurate real-time feedback with off-the-shelf ASR.**
- **Prosody/intonation scoring is far less mature than segmental scoring** — a PRISMA systematic review found most commercial CAPT systems provide "little or no prosodic information," and even recent multi-reference research approaches only achieve modest correlation with human judgment (*r* = 0.310). *(See Cross-Cutting Finding #1.)*
- **Real-time latency is a hard engineering constraint**, not just UX polish — streaming ASR systems face an inherent accuracy/latency trade-off (more lookahead context = more accurate but slower).
- **Native-norm-only scoring is a documented fairness/validity risk**, not just an accuracy gap: models trained only on native speech showed "very low recall" against human-labeled L2 mispronunciation judgments — meaning a native-norm scorer both misses errors humans actually flag *and* can wrongly flag non-standard-but-intelligible speech as "wrong."
- **Language-learning apps suffer from very high churn** — 9-12% monthly, among the highest of any educational-app category, with "loss of motivation" cited as the top cancellation driver (~40%). Even Duolingo, the industry's best-executed retention product, had ~28-47% monthly churn depending on market/year.

### How professionals/products remedy this
- Alignment-free, CTC-based GOP scoring (more robust to disfluent/mispronounced input than classic forced-alignment GOP).
- Surface-faithful reranking against an independent phoneme recognizer to counter ASR's "intent bias" (reduced false-acceptance on severe mispronunciations from 80.8% to 74.8% in one study).
- **L1-aware modeling** — conditioning mispronunciation detection on the learner's native language rather than treating all learners identically against one native reference (ELSA's disclosed roadmap explicitly follows this pattern).
- **Intelligibility-first scoring construct** (Duolingo) — training on human-rated responses against CEFR-aligned intelligibility criteria rather than "distance from one native accent."
- **Hybrid human+AI feedback** — the most consistent remedy across products. Controlled research supports a specific division of labor: one 12-week EFL RCT found human feedback significantly better for *pronunciation* gains while AI was comparably effective (and more scalable) for *grammar*; a qualitative study found learners specifically preferred AI for *fluency* feedback but preferred humans for *pronunciation/prosody* feedback.
- **Gamification/behavioral design** against the high churn baseline (streaks, XP) — Duolingo's own data shows users with 30+ day streaks churn at a fraction of the rate of new users.
- **On-device processing** for both latency and privacy (Google's Read Along/Bolo processes children's speech entirely on-device, never touching a server).

### Open questions / contested
- **Can AI fully replace human coaching for prosody feedback?** Mixed evidence: some studies find AI-based tools statistically comparable to native-speaker-led instruction for beginners; others find humans significantly outperform AI specifically on pronunciation gains. The most defensible synthesis across every source in this review: **complementary, not substitutive** — no source claims full AI replacement of human coaching for nuanced prosody feedback.
- **Does drill-based improvement transfer to real spontaneous speech?** CAPT meta-analyses show real medium-to-large effects, but a 2025 scientometric review found the field's research emphasis is still overwhelmingly on read-aloud/drill tasks rather than spontaneous, communicative speech — the evidence for transfer to public-speaking-grade, real-time fluency is thinner than the evidence for isolated drill gains.

---

## 8. Cross-Cutting Findings (Moderator Pass)

This section exists specifically to surface what individual lenses missed, where they disagreed, and where they over-agreed — the whole point of running this as a multi-perspective roundtable rather than a single research pass.

### Finding #1 — Independently triangulated: AI/ASR is good at scoring sounds, bad at scoring intonation
**Three separate lenses (phonetics, cognitive fluency, speech-tech), researching independently, converged on the exact same technical limitation from different angles** — this is the single most robustly cross-validated finding in this entire review:
- The **phonetics lens** found the ASR meta-analysis shows *g* = 0.82 for segmental vs. *g* = 0.37 for suprasegmental features.
- The **speech-tech lens** independently found a PRISMA systematic review confirming commercial CAPT tools provide "little or no prosodic information," and that the underlying reason is structural (many different acoustic contours can validly express the same prosodic function, making single-reference comparison fundamentally under-constrained).
- The **SLA lens** flagged a directly *conflicting* single study (a Japanese-learner intervention found the opposite pattern — suprasegmental gains, no segmental gains) — worth noting as a genuine outlier, not dismissed, but outweighed by the two independent meta-analytic/systematic-review sources.

**Implication:** any feature promising real-time intonation coaching is on much thinner technical ice than one promising phoneme-level pronunciation feedback. This should be treated as a load-bearing constraint, not a minor caveat.

### Finding #2 — Independently triangulated: the entire product category has an active, unresolved ethics debate
**Two lenses (sociolinguistics and clinical SLP), researching completely independently, both surfaced the same core tension without prompting**, which is a strong signal it's real rather than one researcher's idiosyncratic finding:
- The **sociolinguistics lens** found a 2024 paper explicitly critiquing "AI accent-altering technology" as reproducing "racial commodification" and promoting "global homogeneity through the elimination of linguistic diversity" — a direct, current critique of this exact product category.
- The **clinical SLP lens** independently found that ASHA's own practice guidance acknowledges accent modification services have been "criticized for perpetuating stigma and discrimination... rather than embracing diversity of language," and that a parallel sociolinguistic critique argues accent-neutralization is "a distraction from structural discrimination."

**Implication:** this is not a fringe objection. It should inform how the eventual app frames its own goals (e.g., "intelligibility and confidence" vs. "sound more native/professional"), and is worth revisiting explicitly when features are designed, not filed away as a one-time caveat.

### Finding #3 — Cross-cutting conflict: no persona resolved whether AI can substitute for human interaction
**Four lenses (SLA, public speaking, clinical SLP, speech-tech) each independently touched this question and converged on the same answer: no evidence supports full substitution.**
- SLA: all AI-conversation-practice studies are short-duration (6-10 weeks) and reduce *situational* but not always *trait* anxiety; researchers explicitly frame these as "rehearsal partners," not interaction replacements.
- Clinical SLP: instrumented biofeedback protocols (visual-acoustic, ultrasound) in the literature are explicitly validated *with a clinician present*; no study tested a fully clinician-free deployment for adult L2 accent training.
- Speech-tech: the most defensible synthesis across every source is "complementary, not substitutive."
- Public speaking: VR/AI anxiety interventions show promise but are recent, small-N, and not yet meta-analyzed at the scale of the general-population CBT/VRET evidence.

**Implication:** this is arguably the single most important design constraint that emerged from the entire roundtable — if a future feature set assumes an AI coach can fully replace a human conversation partner or clinician, no lens found supporting evidence for that assumption, across four independent search efforts.

### Blind spot — no persona addressed accessibility/neurodivergence
None of the seven lenses considered how the app would need to adapt for users with stuttering, hearing differences, ADHD, or other conditions that affect speech production or auditory processing independent of L2 status. Given the target population ("any native language") will inevitably include such users, this is a genuine gap that would need dedicated research before feature design, not an oversight to wave away.

### Blind spot — no persona addressed data privacy/biometric risk of continuous voice recording
The speech-tech lens noted on-device processing as a technical *pattern* (for latency), but no lens examined the privacy, consent, or voice-biometric/voice-cloning risk of an app whose core mechanic is continuously recording a user's voice — a real regulatory and trust surface (e.g., biometric privacy laws like Illinois' BIPA) that a health/self-improvement-adjacent app should not discover late.

### Blind spot — thin/no coverage of L1 diversity at true global scale
Every lens that gave L1-specific detail (phonetics, clinical SLP) used the same handful of well-studied pairs — Japanese, Mandarin/Cantonese, Spanish. The user's stated goal is "no matter what your native language is," but the contrastive-analysis and clinical literature is heavily concentrated on a small set of L1s. For dozens of other L1s (e.g., most South Asian, African, and Southeast Asian languages beyond Mandarin), the specific transfer-error literature is much thinner. This is a scalability risk that no persona named directly, even though several hinted at needing "per-L1 tailoring."

### Over-consensus flagged, not smoothed over — "intelligibility over nativeness" is near-unanimous, but not unchallenged
Every lens that touched pronunciation goals (SLA, phonetics, clinical SLP, sociolinguistics) converged on "intelligibility, not nativeness" as the right target. This is good, real convergence — but the sociolinguistics lens itself flagged that this apparent consensus sits on top of an unresolved tension between learner autonomy (some learners *want* to sound more native for personal/professional reasons, independent of discrimination) and the field's structural critique of that desire. Treat "intelligibility over nativeness" as the evidence-backed default, not as license to ignore what users say they actually want.

### Methodological caution worth carrying forward
The public-speaking lens caught that the widely-repeated "75-85% of people fear public speaking" statistic traces to non-methodologically-documented sources, while the rigorous epidemiological figure (21.2% lifetime prevalence) is much lower. This is a useful general reminder: several vendor and practitioner-sourced statistics throughout this review (ELSA's 93.88% figure, various retention/churn benchmarks) are marketing or SEO-blog claims, not peer-reviewed data, and were flagged inline as such by the researching lenses — worth treating with the same skepticism going forward.

---

## 9. Consolidated Bibliography (Selected Key Sources)

**Foundational SLA theory**
- Krashen, S. (1982). *Principles and Practice in Second Language Acquisition.*
- Swain, M. & Lapkin, S. (1995). Problems in Output and the Cognitive Processes They Generate. *Applied Linguistics*, 16(3), 371–391. [doi:10.1093/applin/16.3.371](https://doi.org/10.1093/applin/16.3.371)
- Long, M. (1996). The role of the linguistic environment in second language acquisition. In Ritchie & Bhatia (Eds.), *Handbook of Second Language Acquisition.*
- Selinker, L. (1972). Interlanguage. *IRAL*, 10, 209–231.
- Lyster, R. & Saito, K. (2010). Oral Feedback in Classroom SLA: A Meta-Analysis. *Studies in SLA*, 32(2). [doi:10.1017/s0272263109990520](https://doi.org/10.1017/s0272263109990520)
- DeKeyser, R. & Suzuki, Y. (2025). Skill Acquisition Theory. In *Theories in Second Language Acquisition* (4th ed.). [doi:10.4324/9781003491118-7](https://doi.org/10.4324/9781003491118-7)

**Pronunciation & intelligibility**
- Munro, M. J. & Derwing, T. M. (1995). Foreign Accent, Comprehensibility, and Intelligibility in the Speech of Second Language Learners. *Language Learning*, 45(1), 73–97. [doi:10.1111/j.1467-1770.1995.tb00963.x](https://doi.org/10.1111/j.1467-1770.1995.tb00963.x)
- Munro, M. J. & Derwing, T. M. (2006). The Functional Load Principle in ESL Pronunciation Instruction. *System*, 34(4), 520–531. [doi:10.1016/j.system.2006.09.004](https://doi.org/10.1016/j.system.2006.09.004)
- Field, J. (2005). Intelligibility and the Listener: The Role of Lexical Stress. *TESOL Quarterly*, 39(3), 399–423. [doi:10.2307/3588487](https://doi.org/10.2307/3588487)
- Levis, J. M. (2005). Changing Contexts and Shifting Paradigms in Pronunciation Teaching. *TESOL Quarterly*, 39(3), 369–377.
- Jenkins, J. (2000). *The Phonology of English as an International Language.* Oxford University Press.
- Lee, J., Jang, J., & Plonsky, L. (2015). The Effectiveness of Second Language Pronunciation Instruction: A Meta-Analysis. *Applied Linguistics*, 36(3), 345–366. [doi:10.1093/applin/amu040](https://doi.org/10.1093/applin/amu040)

**Cognitive fluency**
- Levelt, W. J. M. (1989). *Speaking: From Intention to Articulation.* MIT Press.
- de Bot, K. (1992). A bilingual production model: Levelt's 'speaking' model adapted. *Applied Linguistics*, 13(1), 1–24. [doi:10.1093/applin/13.1.1](https://doi.org/10.1093/applin/13.1.1)
- Segalowitz, N. (2010). *Cognitive Bases of Second Language Fluency.* Routledge.
- Yuan, F. & Ellis, R. (2003). The Effects of Pre-Task Planning and On-line Planning on Fluency, Complexity and Accuracy. *Applied Linguistics*, 24(1), 1–27. [doi:10.1093/applin/24.1.1](https://doi.org/10.1093/applin/24.1.1)

**Clinical / accent modification**
- ASHA Practice Portal: [Accent Modification](https://www.asha.org/practice-portal/professional-issues/accent-modification/).
- Gu, Y. & Shah, A. P. (2019). A Systematic Review of Interventions to Address Accent-Related Communication Problems in Healthcare. *Ochsner Journal.* [doi:10.31486/toj.19.0028](https://doi.org/10.31486/toj.19.0028)
- Byun, T. & McAllister, T. (2022). Tutorial: Using Visual-Acoustic Biofeedback for Speech Sound Training. *AJSLP.* [doi:10.1044/2022_ajslp-22-00142](https://doi.org/10.1044/2022_ajslp-22-00142)

**Public speaking & anxiety**
- McCroskey, J. C. (1977). Oral Communication Apprehension: A Summary of Recent Theory and Research. *Human Communication Research*, 4(1). [doi:10.1111/j.1468-2958.1977.tb00599.x](https://doi.org/10.1111/j.1468-2958.1977.tb00599.x)
- Reeves, R., Curran, D., Gleeson, M., & Hanna, D. (2022). VRET vs. in-vivo exposure meta-analysis. *Behavior Modification.* [doi:10.1177/0145445521991102](https://doi.org/10.1177/0145445521991102)
- Anderson et al. Meta-analysis of psychological interventions for Fear of Public Speaking. [PMC6428748](https://pmc.ncbi.nlm.nih.gov/articles/PMC6428748/)

**Sociolinguistics & ethics**
- Lippi-Green, R. (2012). *English with an Accent: Language, Ideology and Discrimination in the United States* (2nd ed.). Routledge.
- Spence, J. L., Hornsey, M. J., Stephenson, E. M., & Imuta, K. (2022). Is Your Accent Right for the Job? A Meta-Analysis on Accent Bias in Hiring Decisions. *Personality and Social Psychology Bulletin.* [doi:10.1177/01461672221130595](https://doi.org/10.1177/01461672221130595)
- Cavazos, A. G. et al. (2024). Beyond the Front Yard: The Dehumanizing Message of Accent-Altering Technology. *Applied Linguistics.* [doi:10.1093/applin/amae002](https://doi.org/10.1093/applin/amae002)
- Ramjattan, V. A. (2024). Imagining an anti-racist pronunciation pedagogy. *ELT Journal.* [doi:10.1093/elt/ccae013](https://doi.org/10.1093/elt/ccae013)

**Speech-tech / ASR**
- Microsoft Learn: [Pronunciation Assessment](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/how-to-pronunciation-assessment).
- Duolingo English Test Blog: [A pronunciation scoring model built around intelligibility, not imitation](https://blog.englishtest.duolingo.com/new-research-in-language-learning-a-pronunciation-scoring-model-built-around-intelligibility-not-imitation/).
- Roll et al. (2025). Scaling Conformation Bias in ASR. *SLaTE 2025.* [ISCA Archive](https://www.isca-archive.org/slate_2025/roll25_slate.pdf)

*(This is a selected list. Every claim in Sections 1–8 above carries its own inline citation; the full source list from each research lens — including many additional papers, theses, and vendor sources — is preserved in the underlying research transcripts and can be expanded on request.)*

---

## 10. Open Questions to Resolve Before Designing Features

1. Should the app's stated goal be framed around **intelligibility and confidence** (evidence-backed, ethically safer) or **accent reduction/native-likeness** (what some users may instinctively want)? Section 6 and Cross-Cutting Finding #2 make this a first-order decision, not a marketing detail.
2. Which technical bet does the app make on prosody? Given Cross-Cutting Finding #1, real-time intonation scoring is a genuinely unsolved problem — is the app comfortable shipping segmental (phoneme) feedback first and being honest about prosody being weaker, or does it need a different (e.g., human-in-the-loop, or visual/gesture-based) approach to prosody specifically?
3. Given Cross-Cutting Finding #3, does the product roadmap include any human-in-the-loop element (peer practice, coach marketplace, community), or is it committing to fully automated feedback despite no lens finding evidence that fully substitutes for human interaction?
4. How will the app handle the dozens of native languages outside the well-studied Japanese/Mandarin/Spanish set, given the contrastive-analysis literature is much thinner elsewhere?
5. What is the app's position on voice-data privacy, given its core mechanic requires continuous audio capture?
6. Does the app need dedicated design consideration for users with stuttering, hearing differences, or other speech/auditory conditions, given "any native language" implies a broad, non-homogeneous user base?
7. Which specific, evidence-backed techniques (functional-load-prioritized pronunciation, HVPT, 4/3/2-style fluency drills with feedback, PREP-style organization frameworks, prompts-over-recasts feedback, pre-task planning time) are worth prototyping first, and which (shadowing-for-segmentals, Monroe's Motivated Sequence, native-norm accent scoring) should be deprioritized or reframed given weak/contested evidence?

---

## Addendum: Three Follow-Up Deep Dives

After this review's first pass, three of the open questions/blind spots above were researched in depth. Each follows the same grounding rule (every claim cited or explicitly flagged as unverified).

### A. Can the speech-analysis pipeline run entirely on-device, instead of sending audio to servers?

**Confidence: MODERATE.**

- **What's easy today:** basic on-device transcription (Apple's `SFSpeechRecognizer`/`SpeechAnalyzer`, Android's `createOnDeviceSpeechRecognizer`, whisper.cpp — all real, shipped, documented APIs) and phoneme-level GOP pronunciation scoring *against a known target sentence* (i.e., scripted read-aloud practice) — academically demonstrated with compact models (Gong et al.'s GOPT, ICASSP 2022). Real-time pitch/F0 extraction for visual feedback is decades-old, cheap DSP (sub-5ms).
- **What's hard/unproven today:** open-ended spontaneous-speech transcription at cloud-grade accuracy fully on-device; prosody/intonation GOP scoring at production quality (even cloud-side, this lags segmental scoring badly — see Cross-Cutting Finding #1); and sustained continuous inference through a whole session without battery/thermal cost (unmodeled in any source found).
- **The critical, non-obvious finding:** smaller on-device models don't just cost some uniform accuracy penalty — even Whisper-Tiny already shows a **243.6% relative WER disparity** for non-native vs. native speakers, worse for tonal-L1 speakers, on top of the general accented-speech ASR bias already documented in Section 7 (Roll et al., SLaTE 2025). Since GOP pronunciation scores are derived from ASR phoneme posteriors, this bias plausibly propagates into and amplifies within the pronunciation score itself — meaning a learner with a heavier accent could get a *less* reliable score than one who already sounds close to the model's training distribution. No study directly measures this specific propagation yet — flagged as a real, unfilled research gap, not a solved problem.
- **Real hybrid patterns already in production or peer-reviewed prototype**: (1) confidence-gated edge/cloud split — cheap on-device pass, escalate to cloud only on low confidence, masking sensitive segments first (e.g., "SpeechShield," ACM 2025); (2) on-device feature extraction where only derived features/embeddings — never the raw waveform — go to the cloud; (3) federated learning for model improvement without raw data ever leaving the device (Google Gboard, at production scale, with formal differential-privacy guarantees); (4) Google's Read Along/Bolo pattern — deliberately narrowing the on-device task's scope (closed-vocabulary, known-passage) rather than trying to match cloud-scale generality.
- **What actually motivates on-device processing, legally:** this is not a theoretical concern. Illinois' BIPA explicitly names "voiceprint" as a protected biometric identifier, and voice-AI class actions are live and expensive right now — a case against Amazon's Alexa Voice ID had its class certified in November 2025 (~1.2 million Illinois residents), and in May 2026 nine coordinated class actions were filed against Meta, Google, Apple, Microsoft, and others over alleged voiceprint extraction. GDPR's biometric-data trigger is more legally ambiguous for this specific feature (would need dedicated legal review), but the UK ICO has already ordered deletion of 5–7 million voiceprints in an unrelated case for lack of consent/DPIA. COPPA is unambiguous and has zero tolerance if the product ever has minor users — audio *files* of a child's voice and voiceprint-adjacent biometric identifiers are both explicitly regulated, with essentially no exception that would cover a retained, graded pronunciation recording.
- **Bottom line:** on-device is genuinely feasible for the "scripted practice + phoneme scoring" slice of the product, is a real privacy risk-reducer worth having regardless of features, but does not (with today's technology) solve the harder "unscripted real-time coaching" ambition without either accepting a narrower scope (à la Read Along) or a hybrid architecture that still has some cloud exposure.

*Full research trace preserved in this session's agent transcripts; can be expanded into its own document on request.*

### B. Should lessons be tailored per native language, or should there be one universal lesson plan?

**Confidence: WEAK-TO-MODERATE** — this is the least-settled of the three follow-ups, largely because the literature has genuinely never run the comparison a product team would want.

- **The direct comparison doesn't really exist.** No study was found that isolates "L1-specific curriculum" as the variable against "universal curriculum," holding everything else constant, across multiple L1 groups. Every existing "comparison" tests L1-informed teaching against generic teaching *for that same L1 group* — not a cross-L1 test of whether tailoring beats one universal design.
- **Where L1-specificity does show a measured advantage, it's at the technical diagnosis layer, not necessarily the learning-outcome layer:** swapping a generic acoustic model for an L1-dependent one improved phone-error-detection precision by 27.37% in one study (Stanley, Hacioglu & Pellom, Interspeech 2012) — but that's a detection-accuracy result, not proof that L1-tailored *teaching* produces better learning outcomes.
- **The Contrastive Analysis Hypothesis (the theoretical basis for L1-specific design) is empirically shaky even where it's been tested most recently** — 2024–2025 papers on Yoruba and Amharic found real, direct predictive failures: errors CA predicted never appeared, and errors that did appear weren't predicted. One Amharic paper stated outright that "a contrastive study... has not yet been conducted between Amharic and English" as of its own 2025 publication.
- **The strongest, most-replicated CALL personalization effect (d = 1.18 within-group, a 61-sample meta-analysis) is about adapting to the *individual* learner** — pacing, content sequencing, individual error-specific feedback — **not about branching a curriculum by native language.** This is the single most important distinction the research surfaced: the evidence strongly supports personalization, but the personalization axis with the strongest evidence is individual adaptivity, not L1-group membership.
- **A concrete, working resolution to this false binary already exists in the research literature:** MIT's Ann Lee built a "personalized mispronunciation detection system based on unsupervised error pattern discovery" that explicitly makes **no assumptions about the learner's L1** — it discovers each learner's own recurring error patterns directly from their speech, and was empirically validated as portable across L1 backgrounds. This sidesteps the L1-data-availability problem entirely, because it never needed an L1-specific corpus in the first place. The pre-digital analogue is the clinical Compton P-ESL method: L1 background generates a *hypothesis* about likely error patterns, but the actual treatment plan is built from the individual's own recorded speech, not a fixed per-L1 template.
- **Real precedents for a middle path also exist:** Jenkins' universal Lingua Franca Core has been explicitly extended with L1-specific supplementary layers for specific groups (e.g., Arabic-L1 modifications by Zoghbor) — "universal core + optional L1-specific layer" rather than either extreme. ELSA Speak's disclosed architecture does something similar (generic model + optional L1-specific enhancement) — but their own research found a large fraction of real users either ignore or mis-select their L1 in a self-report field, meaning any L1-branching design also has to solve "how do we reliably know the user's L1" as a separate, nontrivial problem.
- **A genuinely useful, evidence-adjacent design implication:** Major's Ontogeny Phylogeny Model predicts L1-specific errors dominate early in learning, giving way to more universal, proficiency-driven patterns as the learner advances — implying L1-specificity's value (if any) is front-loaded to early-stage diagnosis, with a universal, individual-error-driven approach taking over for intermediate/advanced learners. Flagged as an inference from a general model, not a directly-tested finding.
- **Bottom line:** the literature does not clearly favor building separate per-L1 lesson plans. It more strongly supports a universal core (severity/functional-load-ranked, in the spirit of the Lingua Franca Core) combined with **individualized diagnosis from the learner's own speech** — which handles L1 differences implicitly without requiring thin-to-nonexistent contrastive-analysis literature for every native language the app claims to support.

### C. Accessibility and neurodivergence

**Confidence: MODERATE, unevenly distributed.** A full companion document, [`accessibility-neurodivergence-review.md`](./accessibility-neurodivergence-review.md), was written with the same citation rigor as this review. Headlines:

- **This is not a niche consideration.** Over 15% of English-language-learners in US public education already have a documented disability — a rate comparable to or higher than general-population estimates for several of the conditions below, directly inside this app's target population.
- **Stuttering** has the strongest evidence base of the six areas studied: L2 speaking measurably increases stuttering-like disfluency relative to L1 in most (not all) studies; ASR is independently documented to be biased against disfluent/stuttered speech (a 2024 study found "consistent, statistically significant" bias across six leading ASR systems, affecting an estimated 80 million people who stutter globally) — meaning a user who both stutters and speaks English as an L2 could face a compounded misrecognition problem before any coaching logic even runs. Applying monolingual disfluency norms to *any* bilingual speaker (stuttering or not) also risks false-positive "disorder" flags, since ordinary L2 disfluency can exceed monolingual clinical thresholds.
- **Dyslexia** shares its core mechanism (phonological awareness, verbal working memory) directly with L2 sound-learning difficulty — and a "language spontaneity deficit" finding suggests dyslexic adults are disproportionately burdened by real-time spontaneous speaking specifically (this app's stated goal) versus scripted/written practice. A genuinely counterintuitive finding: one controlled study found *non-gamified*, explicit phonological training beat gamified training for dyslexic learners' sound discrimination — directly complicating any assumption that gamification is universally the right lever.
- **ADHD** has real L2-specific research (a 2024 Norwegian study group) showing adults with ADHD report more pragmatic-language difficulty across their languages, with high heterogeneity in individual compensatory strategies — "one ADHD profile" doesn't exist. General ADHD app-engagement research is a genuine mixed bag: one RCT found gamification *helped* attention/engagement, while practitioner sources caution that streak mechanics can trigger permanent abandonment after one missed day — these two threads are in direct, unresolved tension.
- **Autism** research shows real, well-documented prosody *production* differences (pitch range, contour, focus-marking) with largely *intact* perception — autistic speakers can often hear a prosodic contrast they don't reliably produce. Critically, the autism-prosody literature itself warns that "appropriate" intonation is context-dependent, meaning a single scored target contour can be actively wrong in a different context, not just clinically insufficient. Autistic "masking" — suppressing natural communication style to match neurotypical expectations — is independently linked to anxiety, burnout, and depression; a feature that implicitly treats one neurotypical contour as "correct" shares its mechanism with masking-inducing interventions the clinical field is now moving away from.
- **Deaf/hard-of-hearing** users face a structural, not just suboptimal, mismatch with any audio-only feedback loop — the deaf brain cannot process auditory feedback of its own speech at all. Visual "sensory substitution" tools already exist and show early pilot success (a 6-month, 72-participant study took deaf children from zero vocalizations to an average of ~7 phonetic sounds using color-coded visual feedback), but none were studied specifically for *second*-language acquisition — only for learning spoken language in the first place.
- **Universal Design for Learning applied to language-learning apps** is a genuinely thin literature — essentially one PhD research program, entirely classroom-based rather than tested on self-directed app usage. No ASHA-level guidance was found combining "accent/pronunciation modification" with "neurodiversity-affirming care" as a single practice document — they exist as two separate, non-overlapping professional frameworks today.
- **The single biggest gap:** no study was found testing whether general-population L2-pronunciation-coaching apps are safe or effective for learners who are *also* stuttering, autistic, dyslexic, or D/HoH. This exact intersection — accessible design for L2 learners who are also neurodivergent — appears to be genuinely unstudied as a combined population, not just under-studied.

---

*End of literature review. No feature or product decisions have been made in this document — this is intentionally research-only, per the current phase of work.*
