# Product ideas: gen-AI with a hard computing core

**Purpose.** A catalog of every distinct product the roundtable produced — not the verdict memo. Each idea is written so you can *feel* it, then judge it. Primary grade is **wow**. Feasibility (6–8 months), deployability, and technical difficulty come after.

**How to read this.** Ideas are ordered by wow, highest first. Related nominations from different personas are merged into one product (so you don’t read “intelligibility scan” five times). Compliance traps and platform-killed ideas are included on purpose: several of them are the *most* magical, and you should see why they still lose.

**The bar.** A user-facing product people would keep using. Internally it attacks a real computing problem (search, verification, realtime speech, planning, compilation) — not a ChatGPT wrapper. Shippable to real users in 6–8 months.

**Score key.** Wow / Feasibility / Deployability / Technical difficulty, 1–10. Hard internals are a *plus*. `—` means the roundtable did not score that axis as a standalone product.

---

## How to use this catalog

If you only have time for three:

1. **AuditSheet** — highest clean wow that is still a compiler, not a chat.
2. **Full-duplex meeting simulator** — highest *felt* wow in speech. The catch is Speak already owns “talk to an AI.”
3. **HearMe** — the only speech idea whose wow is a *diagnosis you can hear*, and whose internals are not a bought API.

The roundtable’s production pick was HearMe (scripted), because wow-plus-honest-ML-plus-you-already-have-the-research beat wow-alone. That is a *shipping* ranking. This document is a *wow* ranking. They are not the same list.

---

# Wow 9 — “I can’t believe that’s a product”

These are the ideas where the first session should make someone text a friend.

---

## 1. AuditSheet — a financial model that is actually a program

**Scores:** Wow 9 / Feasibility 6 / Deployability 6 / Difficulty 9

**Who.** FP&A lead at a Series B–D company, or a first/second-year at a boutique bank, who currently pastes ChatGPT numbers into Excel and then rebuilds formulas by hand.

**The product.** You answer a structured intake (revenue, headcount, burn, growth, hiring plan). You download a `.xlsx`. Every output cell is a **formula**. You change growth in B1 and the whole three-statement model moves. A sidebar lists every hardcoded value the compiler refused to emit, like a linter for a spreadsheet.

**The 60-second wow.** Paste last quarter’s actuals into the yellow inputs. Change “hires per month” from 4 to 7. Watch cash, runway, and headcount *recompute*. That is the moment ChatGPT-in-Excel has never delivered, because frontier Excel agents still **compute the right number and then type it in as a constant** (WorkstreamBench: even Claude Web scores 53.4/100 on the hardest spreadsheet tasks; SpreadsheetBench: Excel Copilot ~20%, GPT-4o ~17% on real manipulation).

**Hard computing problem.** Spreadsheet intermediate representation. Formula synthesis with absolute vs relative refs. Circular-ref handling. An audit graph from every output cell back to assumptions. This is a **compiler**, not a chat. The model is a typed IR; Excel is just the backend.

**Why it’s a good idea (wow-first).** Spreadsheets are the last place knowledge workers will forgive magic numbers. A model you cannot stress is not a model — it is a screenshot with gridlines. The wow is not “AI wrote my budget.” The wow is “this thing is alive.” That is a different category from Copilot-in-a-pane.

**Why it might still lose.** Claude for Excel is already generally available (cell-level citations, “preserve formula relationships,” build models across tabs). Microsoft Copilot Agent Mode edits the grid natively. You only win if formula-audit quality stays a category ahead of the platform for 12+ months. Distribution is *inside Excel*, which Microsoft owns.

**MVP (6–8 months).** One template family: 3-statement + headcount from a structured intake. Formula lint. “Hardcoded cell” report. No PowerPoint, no ERP, no full IB coverage.

**Kill criterion.** A frozen 20-model eval: if Copilot/Claude emit formula-native workbooks at similar quality in 90 days, stop.

---

## 2. Full-duplex meeting simulator — the standup that talks over you

**Scores:** Wow 9 / Feasibility 6 / Deployability 7 / Difficulty 9

**Who.** A non-native engineer or PM with a real meeting on the calendar this week. Not “language learners.” People who get talked over.

**The product.** You join a fake standup. Three voices. They interrupt you. They change the subject. They ask a question while you are still answering the last one. After 8 minutes you get a replay: the two moments you lost the floor, with the transcript evidence, not a “confidence 82%.”

**The 60-second wow.** You try to finish a sentence and the “tech lead” talks over you — and the system *lets it happen*, then shows you the clip. That is not a tutor. That is exposure therapy with a debugger. Current conversation apps (Speak, Praktika, Duolingo Video Call) are turn-based: the AI waits. Real meetings do not wait. Full-duplex turn-taking with barge-in and playback-aware state (the architecture people call GCM) is still middleware, not a consumer SKU.

**Hard computing problem.** Full-duplex voice, barge-in, overlapping speech, L2-aware VAD (a 600 ms hesitation is not a turn-end for a non-native speaker), conversational state that survives being interrupted. This is a realtime systems problem wearing a language-learning costume.

**Why it’s a good idea (wow-first).** Every professional English app practices the *wrong sport*. They train you for an oral exam. Your actual failure mode is a noisy standup. The demo GIF — three people talking at once, you holding a point — is the most shareable artifact in this entire catalog.

**Why it might still lose.** Speak is a $1B conversation tutor on OpenAI’s Realtime API. If your demo *looks* like “talk to an avatar,” you are a feature. Duolingo already has Video Call. Unit economics of realtime audio are brutal (flagship speech-to-speech is cents per minute of *talk*, not per user). Security: other people’s synthetic voices are fine; recording *you* with process-and-delete is mandatory; never score emotion.

**MVP.** One scenario (standup or interview panel). 5–8 minutes. Hard session cap. Captions always on. Evidence clips, not scores. One L1.

**Kill criterion.** If barge-in quality is 12–18 months of middleware, this is not a 6–8 month product. Ship HearMe first and add this as the wow *surface* later.

---

## 3. Native speech-to-speech tutor (uncapped magic)

**Scores:** Wow 9 / Feasibility 7 / Deployability 5 / Difficulty 6

**Who.** Anyone who has used ChatGPT Voice and wanted it to *teach*.

**The product.** You talk. It talks back, in your language, interrupting, laughing, switching to a drill when you stumble. No buttons. The OpenAI Realtime / Gemini Live demo everyone has now seen, productized as a coach.

**The 60-second wow.** It feels like a person. That is the entire trick. Advanced Voice Mode made interruption and emotion the 2024 demo for a reason.

**Hard computing problem.** **Thin.** You are buying `gpt-realtime-2.1`. Data/ML scored technical difficulty **6** and said so. Curriculum and session design are product work, not a computing problem. This **fails the brief’s internal-hardness bar**, which is why it is here as a wow object and not as the recommended company.

**Why it still belongs in this document.** It is what users will compare you to. If you cannot explain in one sentence why you are *not* this, you will be this — and then you will compete with Speak, ChatGPT Voice, and Duolingo Max on their cost curve.

**Why it loses as a company.** Speak already runs this stack. Uncapped minutes destroy a $15–20 subscription (SRE: a chatty tutor is the cost driver, not the user). OpenAI org-level 429s take the product down at launch. Apple shipped on-device Live Translation. Inflection built Pi on a 22k-H100 cluster and still could not make consumer chat pay for the GPUs.

**If you ship any of it:** 3-minute sessions, mini model, prompt cache, hard `$` kill switch per session. Never as the core.

---

## 4. Voice-clone “your voice, but native” — the forbidden wow

**Scores:** Wow 9 / Feasibility 6 / Deployability 2 / Difficulty 8  
**Status:** Compliance trap. Included because the wow is real.

**Who.** Call-center agents, salespeople, anyone who has been told their accent is “costing them deals.”

**The product.** You speak. The output is *you*, with native pronunciation, live. Sanas/Krisp adjacent. The demo makes executives lean forward.

**The 60-second wow.** Hearing your own voice, corrected, is viscerally more magical than any score.

**Hard computing problem.** Voice conversion / accent conversion in realtime. This *is* a hard speech problem.

**Why it is a terrible company for a 6–8 month team.** Enrolment utterance → voiceprint. Illinois BIPA names **voiceprint** as a biometric identifier ($1,000–$5,000 per violation, private right of action). EU AI Act Art. 50: synthetic audio must be machine-readable marked; audio deepfakes need a *perceivable* label — a watermark is not enough. Stolen clones are bank/CEO-fraud material. The FTC Impersonation Rule already exists. Security ranked deployability **2**.

**Do not build this.** The wow is the bait.

---

## 5. “Speak English while the agent uses your computer”

**Scores:** Wow 9 / Feasibility 4 / Deployability 3 / Difficulty 9  
**Status:** Compliance + reliability trap.

**The product.** You practice a support call in English while an agent actually clicks through a sandbox CRM. Language practice with consequences.

**The 60-second wow.** The computer does something because you *said* it.

**Why it dies.** OSWorld 2.0: frontier computer-use agents complete **20.6%** of hour-scale workflows. Prompt injection via on-screen content is unsolved at OpenAI and Anthropic (their own system cards). A 6–8 month team cannot build the control plane (per-action auth, HITL, audit) that labs still fail at. Blast radius is the product.

---

# Wow 8 — “I would try this today”

---

## 6. HearMe — 15-second intelligibility scan

**Scores:** Wow 8 (Designer scored the *flow* 9) / Feasibility 7 / Deployability 8 / Difficulty 8  
**Roundtable production pick, with a spike gate.**

**Who.** L1-Mandarin / Hindi / Korean professionals with a dated event: on-site in six weeks, visa medical English, OSCE, a standup they already dread. Not “everyone who wants a nicer accent.”

**The product.** One screen, one button: “Speak 15 seconds of something you’d say at work.” Instant waveform. Named wait phases (“aligning sounds…”), not a spinner. **One** finding: “Listeners hear *develop* as *deVELOP* — that costs you more than your ‘th’.” Play original vs a minimally-edited intelligible version. Tap the word → what the system heard (Granola’s quote-zoom). One retry. Stop. No dashboard.

**The 60-second wow.** An A/B of *your own voice*. Not a 92% accent score. Not an avatar. The first-session test the designer insisted on: a visible artifact you can accept or undo.

**Hard computing problem.** Forced alignment. Functional-load ranking (Munro & Derwing 2006: one high-FL error hurts more than three low-FL errors). F0 / duration / energy for stress. L2-robust scoring. **Must be closed-vocab / known target text.** Modern ASR *corrects* learner errors — Parakeet overcorrected ≥1 mispronunciation in 82% of speechocean762 utterances. If you score spontaneous free speech with Whisper/Realtime, you will ship a confident liar. Scripted CTC-GOP (GOPT phone PCC 0.612 on public data) is the honest engine. Azure Pronunciation Assessment’s AccuracyScore is *match a native speaker* — the wrong construct. Duolingo’s research path is intelligibility, not imitation.

**Why it’s a good idea (wow-first).** ELSA drills phonemes. BoldVoice sells American accent with Hollywood coaches. Speak sells conversation. Yoodli/Orai score *native* fillers. **Nobody sells “the three errors that make you hard to understand” as the product.** The wow is *specificity*: one colored error, one replay. That is also the trust moment. PAIR’s rule: numeric confidence is how you get blind accept; evidence is how you get a second session.

**Why the production ranking put this first (not because it has the most wow).** It is the rare idea that is (a) magical in 60 seconds, (b) a real ML problem you own, (c) operable at $0.01–$0.04 per clip as a batch diagnostic, (d) adult-only and process-and-delete (Security’s only green speech SKU), (e) sitting on research you already did. The conversation gym has *more* raw wow and fails the hardness bar.

**The honest constraint.** A 15-second scan of *spontaneous* speech is the Designer’s dream and the ML scientist’s nightmare. The synthesis is: 15 seconds of a **prompted line** (read this standup update). Still wow. Scientifically defensible. Slightly less “I just talked.” Worth it.

**MVP.** One L1 × one scenario. Adult 18+. No emotion/confidence labels. No school/HR SKU. No phoneme scores on open conversation. Captions of their own audio.

**Kill criterion (week 4).** Pearson/Spearman of your scores vs human intelligibility on ~200 held-out clips. If near zero, stop. If the first diagnosis is humiliating or obviously wrong in 10 guerrilla phone tests, stop.

---

## 7. Knot — the scheduler that can prove it is impossible

**Scores:** Wow 8 / Feasibility 7–8 / Deployability 5–8 (Engineer 8, GTM/PM much lower) / Difficulty 8–9

**Who.** A clinic coordinator, field-service dispatcher, or film production manager who currently lives in a color-coded Google Sheet that breaks every time someone calls in sick.

**The product.** Paste constraints in English and drop in calendars. You get a feasible roster **or** a minimal conflict in English: “Drop constraint 4 *or* add one Saturday and it works.” You can toggle a constraint off and watch it re-solve. The constraint IR is visible and editable (Tab/undo) — the solver never hides behind “the AI said so.”

**The 60-second wow.** You feed it an *impossible* week. It does not hallucinate a schedule. It says **why** it is impossible, and the reason is a *minimal* set — not a wall of red cells. That is a different magic from ChatGPT producing a plausible Gantt that violates the night-shift rule.

**Hard computing problem.** NL → MiniZinc / OR-Tools / Z3. Combinatorial search. MUS / UNSAT-core extraction (MiniZinc FindMUS). Iterative repair. This is the 2025–2026 neuro-symbolic pattern: the model *proposes* an encoding, the solver *disposes*. MCP-Solver already exposes MiniZinc/Z3 over MCP. NAACL 2025 showed GPT-4 + Z3 beating ReAct on TravelPlanner by compiling NL to SMT.

**Why it’s a good idea (wow-first).** Everyone has been burned by an AI that sounds sure and is wrong. A product that can say “this cannot be done, and here is the smallest reason” is a new *kind* of confidence. The wow is epistemic. Engineers will tweet the UNSAT core. Coordinators will care that Tuesday now has a nurse.

**Why it might still lose.** Text2Zinc (2025): even with copilots, LLMs are **not yet push-button** for combinatorial models from text. Nextmv and Timefold already sell scheduling APIs with visual explainability. A FindMUS dump is not a sentence a shift manager trusts. A wrong encoding that Z3 SAT-solves is a confident lie — you must show the IR. Sales cycles for ops software exceed 6–8 months unless you pick **one** vertical and walk in with CSV.

**MVP.** One vertical, one schema, one artifact (Gantt + conflict list). Calendar APIs. No MES, no IoT, no “describe any factory.”

**Kill criterion (week 4).** Ten real customer constraint sets. True UNSAT cores. A non-engineer understands the explanation. If not, it is a research demo.

---

## 8. CiteLock — the brief that cannot invent a case

**Scores:** Wow 8 / Feasibility 6–8 / Deployability 6–8 / Difficulty 8

**Who.** US civil litigators at solo / 2–10 attorney firms who already draft in ChatGPT and cite-check by hand. Not BigLaw (Harvey/Lexis). Not pro se (they don’t pay).

**The product.** Drop last week’s brief. Red highlights on **fabricated cites** and **wrong-page quotes**. Green links to CourtListener/PACER text. Export a one-page verification log into the matter file.

**The 60-second wow.** It catches a cite that does not exist — or worse, a quote that exists in a *different* case — in *their* brief. That is a cold-sweat demo. Q1 2026: ≥$145k in US sanctions for AI filing failures. Damien Charlotin’s tracker (updated 30 Aug 2026): **1,983** court decisions, **1,647** fabricated, **539** false-quote events.

**Hard computing problem.** Citation parsing and reporter normalization. Retrieval. **Quote-span alignment** (the hard remainder). Subsequent history is a citator monopoly (KeyCite / Shepard’s) — do not promise it. Existence-only is a wrap of CourtListener’s citation-lookup API (~18M citations, documented as a hallucination guardrail).

**Why it’s a good idea (wow-first).** The error is *falsifiable in the first session*. That is the rarest kind of B2B wow: not “save time,” but “you almost filed this.” Stanford: even Lexis+ AI and Westlaw AI-Assisted Research hallucinate on 17–33% of queries. ChatGPT cannot be the checker of ChatGPT.

**Why it might still lose.** PelAIkan is Charlotin’s own checker. FinalVerify and LawDroid CiteCheck already exist. Fastcase Authority Check is often **free via the state bar**. Thomson Reuters bundles KeyCite into CoCounsel. Charlotin’s mix is **1,136 pro se vs 794 lawyers** — volume is self-represented filers, not a SaaS ICP. ABA Formal Opinion 512: confidentiality (Rule 1.6) sits on the lawyer; uploading live briefs to a two-person startup is a procurement object. If MVP is “does this case exist?” you are a feature.

**MVP.** PDF/DOCX in → quote/page flags vs open full text → human confirm → matter-file PDF. Cut Shepard’s, 50-state statutes, Word plugin, drafting.

**Kill criterion.** 10 paid pilots after catching one *real* error in *their* brief. If they shrug “I’ll just be more careful,” there is no product. Never ship existence-only.

---

## 9. CSV Ghost-Fill — Cursor Tab for messy tables

**Scores:** Wow 8 / Feasibility 8 / Deployability 9 / Difficulty 7

**Who.** Anyone who has cleaned a CSV at 11pm. Analysts, ops, researchers, founders.

**The product.** Drop a CSV. Type two corrected cells in a dirty column. The rest of the column ghosts in. Tab accepts, Esc rejects, a chip shows the named transform in English (“split on comma, trim, parse as date”). Undo bar. Apply to 20 rows, then the rest.

**The 60-second wow.** Forty dirty rows fill in place, like Cursor Tab, except the artifact is a table. Chat is not invited.

**Hard computing problem.** Program induction from 1–2 examples. Named transforms (split, normalize, date parse) as an IR, not a black-box fill. Showing the program is the trust mechanism.

**Why it’s a good idea (wow-first).** It is the most *legible* magic in the catalog. You see the ghost, you see the rule, you undo. Designers loved it because it is an existing skill loop (spreadsheets) with accept/reject cheaper than thinking. Cursor’s Tab lesson: fewer, better suggestions beat a firehose.

**Why it might still lose.** Excel Flash Fill shipped in **2013**. Copilot already does NL edits in a pane. Claude for Excel converts hardcoded totals to formulas. The UX bet has to be **ghost-in-grid**, not another chat — and even then you are a sidecar to Microsoft.

**Honest position.** Best as a *wedge demo* or a feature inside AuditSheet/Sheetproof, not as a standalone company.

---

## 10. Sheetproof — the workbook that can lie, caught with a counterexample

**Scores:** Wow 8 / Feasibility 6 / Deployability 7 / Difficulty 8

**Who.** FP&A inheriting a 40-sheet model they did not build. Auditors. Anyone who has been burned by a silent unit error.

**The product.** Extract the formula graph. Infer units and invariants (“this column is USD, this is shares, this ratio cannot exceed 1”). Either find a **concrete input that breaks a stated invariant** or emit tested Python. You do not generate the model. You **prosecute** it.

**The 60-second wow.** “Change growth to 12% and row 847 goes negative — here.” A counterexample cell, highlighted. That is the same family of wow as Knot’s UNSAT core and SameQuery’s tiny database: *disproof*.

**Hard computing problem.** Spreadsheet semantics, program analysis, unit/invariant inference, SMT. Lineage exists (ExceLint, CheckCell, 2013 QSIC Z3-for-spreadsheets). Deterministic graph extractors exist (linexcel, etc.).

**Why it’s a good idea (wow-first).** Generation is being absorbed by Claude-in-Excel. **Checking** is what Copilot is incentivized *not* to over-do (attachment). A proof object — this invariant failed on this input — is a different product.

**Why it might still lose.** Racing Anthropic and Microsoft inside Excel. Invariant language design is the actual product and will slip. Bounded checks are not unbounded proofs; copy that says “proven correct” is a liability.

**MVP.** Invariant language + SMT + counterexample cells. No generation. Differentiate *only* on solver-backed semantic bugs.

---

## 11. Claim–evidence auditor for papers

**Scores:** Wow 8 / Feasibility 7 / Deployability 5 / Difficulty 8

**Who.** A postdoc about to post a bioRxiv/arXiv paper, or a reviewer with 48 hours.

**The product.** Upload PDF → list of claims with support / contradict / not-found against the *actual PDF* of the cited paper. A hostile reviewer in 10 minutes.

**The 60-second wow.** “Citation 14 does not say what this sentence says.” Scientists will feel that in their chest.

**Hard computing problem.** Claim extraction, retrieval, NLI against the cited PDF. Scite/Consensus/Elicit do discovery and citation *sentiment*, not sentence-level lock.

**Why it might still lose.** Grad-student WTP. Publisher PDFs. False positives destroy trust in one session. Humanities are a different sport — cut them.

**MVP.** 20-page STEM papers, Crossref + open PDFs, human confirm.

---

## 12. Live in-meeting L2 overlay

**Scores:** Wow 8 / Feasibility 6 / Deployability 5 / Difficulty 8

**Who.** Non-native professionals who want a whisper during the *real* Zoom, not a rehearsal.

**The product.** Poised, but for intelligibility: live hints on the errors that make you hard to understand, in the meeting.

**The 60-second wow.** Coaching while it counts.

**Why it dies as a 6–8 month company.** Poised shut after a Deepgram acquihire (~50k users). Founder’s post-mortem: businesses buy holistic L&D; spoken change takes effort; orgs want platforms. Overlay products die on IT, consent, and “spy” optics (Poised’s FAQ: others don’t know you’re using it — a feature *and* a landmine). Hedy already sells on-device live coaching. This is a graveyard dressed as a vacuum.

---

## 13. High-stakes voice rehearsal (interview / pitch)

**Scores:** Wow 8 / Feasibility 5 / Deployability 4 / Difficulty 9

**Who.** Someone with an interview on Thursday.

**The product.** Paste talk track → full-duplex voice with captions always on → 60 seconds later, two evidence clips on a transcript canvas (“you hedged here”).

**The 60-second wow.** Interruptible conversation, then receipts. Advanced Voice Mode’s magic plus Granola’s inspectability.

**Why it is hard to ship polished.** Realtime UI + captions + scoring without science-project chrome is XL design for a small team. Humane AI Pin is the consumer proof that silent ~10s waits plus generic failure kills wow. Voice-only excludes deaf/HoH (W3C NAUR; WCAG 2.2 live captions). Designer ranked deployability **4** and said do not pick this as production #1.

**Relationship to #2.** This is the meeting simulator with less chaos and more “score my pitch.” Prefer #2’s scenario (other people talking) if you want wow; prefer HearMe if you want to ship.

---

## 14. L1-agnostic error-pattern discovery

**Scores:** Wow 8 / Feasibility 5 / Deployability 5 / Difficulty 9

**Who.** The same HearMe user, after three weeks of scripted takes.

**The product.** “Your recurring pattern is word-final stops and misplaced stress on verbs — not ‘th.’” No L1 dropdown (ELSA users mis-select L1). Clusters from *your* speech.

**The 60-second wow.** It knows *you*, not your passport.

**Hard computing problem.** Unsupervised clustering on GOP + phone features without an L1 prior. Research-grade. Do not gate MVP on it. Natural v2 on HearMe once you have longitudinal takes.

---

## 15. Ambient conversational fluency gym

**Scores:** Wow 8 / Feasibility 8 / Deployability 7 / Difficulty 6

**Who.** Intermediate learners who will not open a drill app but will take a phone call.

**The product.** A conversation partner. After the call, delivery metrics only: pause *location* (mid-clause vs boundary), fillers, code-switch. **No phoneme scores on this stream.** That refusal is the product integrity.

**The 60-second wow.** It talks. It waits the right amount. It does not talk over your L2 pause — or it does, on purpose, if you are training for meetings.

**Hard computing problem.** L2-aware VAD is real; the S2S loop is a bought API. Data/ML ranked this #1 *because* GOP-on-open-speech is bankrupt, so they retreated to the commodity. That retreat **fails the brief**. Speak already is this, with curriculum, $20/mo, 10M learners, OpenAI Realtime underneath. Reviewers say Speak’s recognition is *lenient* — it optimizes flow, not honesty.

**How to use it.** As a later surface on HearMe, session-capped, never as the company.

---

# Wow 7 — strong, but the first session is quieter

---

## 16. SameQuery — “are these two SQLs the same?”

**Scores:** Wow 7 / Feasibility 6 / Deployability 6–8 / Difficulty 9

**Who.** Analytics engineers comparing two dbt models, or a rewrite vs production.

**The product.** Paste two queries. **EQUIV (bounded)** or a tiny counterexample database you can run. The bound is printed in the UI. You never stamp unbounded “proven.”

**The 60-second wow.** A three-row database where query A returns 4 and query B returns 3. You can `SELECT` it. That is a debugging artifact, not a chatbot paragraph.

**Hard computing problem.** SQL semantics (3-valued NULL, bags, GROUP BY, OUTER JOIN) → SMT. Equivalence is **undecidable** in general. VeriEQL / Cosette-style tools do bounded model checking. Cosette is unmaintained. Wrapping VeriEQL on a published fragment (Postgres SELECT/JOIN/GROUP BY/UNION + NULLs) is the cheap path.

**Why it’s a good idea (wow-first).** Disproof you can run is catnip for engineers. It is also honest: bounded verification is not proof. GTM never modeled the buyer because the workspace pulled everyone toward speech consumers — the actual buyer is dbt/Snowflake/text-to-SQL *vendors* who need eval infra.

**Kill criterion.** If v1 is “all of BigQuery including JS UDFs,” it is RED.

---

## 17. Cited bid-package extractor (trade-filtered)

**Scores:** Wow 7 / Feasibility 6 / Deployability 5 / Difficulty 8

**Who.** Estimator at a 20–150 person electrical / mechanical / fire-protection subcontractor. 48-hour bid window. 200–1,000 page spec + addenda.

**The product.** Upload the set → every requirement that hits *your* trade, with the PDF page you can show the GC if you miss it.

**The 60-second wow.** Page 412 highlighted, filtered to *your* trade, from a document nobody reads cover to cover. A missed spec is six-figure.

**Hard computing problem.** Layout-aware multi-PDF retrieval, addenda diffs, trade classification, citation enforcement. ChatGPT summarizing one section is the competitor they already tried.

**Why it might still lose.** DeadFront, Flikt, Mavlon already pitch this. Acquisition is founder-sales into estimators, not Product Hunt. Quantity takeoff (vision) is a different, harder product — cut it from MVP.

---

## 18. Shop-floor scheduler (CP-SAT, not NL-everything)

**Scores:** Wow 7 / Feasibility 6 / Deployability 4 / Difficulty 9

**Who.** Owner-operator fabricator, 5–10 work centers, planner spends 15–20h/week repairing the Excel.

**The product.** CSV of open jobs in → a Gantt that is **feasible** (0 hard-constraint violations) → “what if order 92 jumps to today.” Lucie’s rule: the agent must not invent the schedule; OR-Tools CP-SAT does.

**The 60-second wow.** The mill is down and a new sequence appears that still hits Friday’s due dates.

**Relationship to Knot.** Same family. Knot is NL + explanations for *any* constraint class. This is one shop, CSV, no English-to-MiniZinc moonshot. Lower wow, higher chance of a correct answer. Lucie / Skody / EZIIL already hunt this. Dirty data is the product.

---

## 19. Meeting contradiction receipts

**Scores:** Wow 7 / Feasibility 7 / Deployability 7 / Difficulty 8

**Who.** Teams drowning in Granola/Otter notes that *summarize* and therefore lie.

**The product.** Upload a transcript or record locally (no bot in the call). Zero to three cards: two quotes, timestamps, play. “You said ship in April; later you said June.” Dismiss / “not a conflict.” Empty state is “no conflict found,” never a fake insight.

**The 60-second wow.** Catching a real conflict. Trust is the receipts. False positives destroy this in one meeting.

**Hard computing problem.** NLI / contradiction over a transcript. Quotes only — no summary-as-truth.

**Why it might still lose.** Granola is becoming a context system of record ($1.5B). Consent. GDPR-ish recording norms. Meeting notes as a category are crowded; this survives only if it *refuses* to be a notetaker.

---

## 20. Visual pitch-contour coach (“say it like you mean it”)

**Scores:** Wow 7 / Feasibility 5–7 / Deployability 7 / Difficulty 8

**Who.** Professionals whose words are fine and whose *intent* does not land (agreement vs disagreement vs given-new).

**The product.** A pitch contour on screen, like a tuner. **Not** an “anxious / confident” label. Visual biofeedback is the 2026-honest UX; a single ProsodyScore is a lie (CAPT meta-analysis: segmental *g* = 0.82 vs suprasegmental *g* = 0.37). LLMs fail on rhythm/intonation (EMNLP 2025).

**The 60-second wow.** Seeing your question look like a statement on the contour, then matching a target shape.

**Hard computing problem.** Classify contour *class* from F0/energy/duration. Need intent-labeled L2 takes — no adequate public corpus. Security: do **not** label affect. Emotion recognition in workplaces and education is banned under EU AI Act Art. 5.

**Natural home.** A mode inside HearMe, not a company. Visual F0 is days of DSP; a *trusted score* is a science problem.

---

## 21. Async functional-load diagnostic (the unglamorous HearMe)

**Scores:** Wow 6–7 / Feasibility 9 / Deployability 9 / Difficulty 5

**Who.** Same as HearMe, but they will wait 30 seconds for email.

**The product.** 30–60s clip → queue → batch STT + scoring → result in the app. SRE ranked this #1 for *operability*: $0.01–$0.04/clip, no GPU, nothing breaks at 10k users.

**The 60-second wow.** Weaker than live. The wow is the *finding*, delayed. Ship this first as the COGS-safe wedge, then add live.

**This is HearMe’s plumbing, not a separate idea.** Listed so the ops path is visible: you do not need WebRTC on day one.

---

## 22. On-device scripted pronunciation coach

**Scores:** Wow 6–7 / Feasibility 7–8 / Deployability 8–9 / Difficulty 7–8

**Who.** Privacy-sensitive adults. EU users. Illinois users. People who will not upload voice.

**The product.** Known target text. GOP on-device (Core ML / WASM). Scores stored as numbers, not waveforms. Cloud only for a weekly batch diagnosis.

**The 60-second wow.** It works on a plane. That is a trust wow more than a magic wow.

**Why Security ranked this #1.** No voiceprints, no Art. 9 biometric unique-ID purpose, Commission example: voluntary language apps with instant error feedback and no credential are *out of* Annex III high-risk education.

**Why it is not the wow pick.** Apple SpeechAnalyzer + Foundation Models make a crude version a weekend composition of first-party frameworks. ELSA already occupies “scripted pronunciation.” HearMe should *use* this as the privacy architecture, not *be* this as the company.

---

## 23. SLP-prescribed between-session homework

**Scores:** Wow 7 / Feasibility 5 / Deployability 4 / Difficulty 8

**Who.** Adults in speech-language therapy, assigned homework by a clinician. Not a consumer “speech therapy app.”

**The product.** The clinician assigns; the app collects structured practice; the clinician sees completion and selected metrics. Explicitly **not diagnostic**, not a device.

**Why wow exists.** Replacing a paper worksheet with something that actually hears you.

**Why 6–8 months is tight.** Constant Therapy has FDA Breakthrough designation. Digital SLP is a ~$2B+ market *because* it is regulated. One clinical-adjacent marketing sentence and you are SaMD. Trust + HIPAA + clinician sales. Do not start here unless you have an SLP co-founder.

---

# Wow 6 and below — real products, quieter magic

---

## 24. Voice-agent QA for accented speech + barge-in

**Scores:** Wow 6 / Feasibility 8 / Deployability 7 / Difficulty 8

**Who.** Teams shipping voice agents on Vapi / Retell / LiveKit who test on studio American English and then fail in production.

**The product.** Eval harness: your agent on Indian/Korean English and interruption recovery. FAR/FRR on barge-in. L2 WER vs studio baseline. $30–100/mo self-serve (Coval is $100–$4,500).

**The 60-second wow.** A dashboard where the agent that looked perfect on your demo **dies** on a Mumbai accent and a mid-sentence interruption. Engineering wow, not consumer wow.

**Hard computing problem.** The same L2 ASR honesty and turn-taking problems as HearMe, sold as B2B eval instead of a tutor. Surface-faithful error preservation (do not let ASR “correct” the test set).

**Why it’s a good idea if you refuse consumer speech.** Smaller TAM, cleaner PLG, Show HN / Discord distribution. Hamming / Cekura / Coval exist; **non-native robustness as the product** is still a feature. If they ship it, you lose.

**This is the “I have speech ML skill and I will not fight Speak” company.**

---

## 25. Query Canvas — NL → inspectable SQL

**Scores:** Wow 6 / Feasibility 8 / Deployability 8 / Difficulty 7

**Who.** Analysts who cannot read SQL yet and overtrust paragraphs.

**The product.** Paste a CSV or one table. Ask in English. Results **and** the query appear in a canvas. Highlight a WHERE → “only last 30 days” as a targeted edit. Undo. The SQL is the provenance.

**The 60-second wow.** First answer is a table, not a paragraph. Quiet wow. SameQuery (#16) is the *checker* version and is more interesting as a computing problem.

---

## 26. Clause Canvas — PDF contract as Canvas, not chat

**Scores:** Wow 6 / Feasibility 7 / Deployability 6 / Difficulty 7

**Who.** Someone who has to redline a vendor contract tonight and is not a lawyer.

**The product.** Drop contract → clause blocks → highlight one clause → “plain English” or “soften” as a **targeted edit** (OpenAI Canvas pattern) → redline + restore. Labeled as drafting aid, not legal advice.

**The 60-second wow.** One clause changes, the rest does not. ChatGPT’s failure mode is rewriting the whole document.

**Why wow is only 6.** Harvey is $190M ARR enterprise. Spellbook lives in Word. Non-experts cannot audit legal text (BBC R&D on agents). Looks like legal advice. PDF + selection + redline is a product, not a skin (8–10 weeks design). SMB self-serve is the published Harvey gap — and still a liability mine.

---

## 27. SMB contract redline (Harvey for solos)

**Scores:** Wow 6 / Feasibility 5 / Deployability 4 / Difficulty 7

Related to Clause Canvas, with a sales motion. Legal AI ~$5.6B (2026). Harvey is unbuyable for solos. Price $33–100/mo. Distro: r/LawFirm. Needs E&O, lawyer review, and you are still in a liability category. CiteLock (#8) is the sharper legal wedge because the error is *falsifiable*.

---

## 28. HVPT perception trainer

**Scores:** Wow 5 / Feasibility 8 / Deployability 9 / Difficulty 6

**Who.** Learners whose problem is *hearing* a contrast their L1 does not have (classic Japanese /r/–/l/).

**The product.** Multi-talker minimal pairs. Tap which one you heard. High-Variability Phonetic Training: durable 3–6 month perceptual gains that transfer modestly to production. Multi-speaker TTS for stimuli.

**The 60-second wow.** Almost none. It looks like a psych experiment. Strongest *learning* evidence in the speech catalog, weakest wow. Natural as a HearMe mode (“hear it before you say it”), not a company.

---

# Map: what is the same product in different clothes

Use this when the roundtable names collide.

| Family | Members in this doc | One company |
|---|---|---|
| Intelligibility diagnostic | HearMe (#6), async diagnostic (#21), on-device GOP (#22), error-pattern v2 (#14), pitch contour (#20), HVPT (#28) | **Yes — HearMe** |
| Conversation / duplex | Meeting simulator (#2), S2S tutor (#3), ambient gym (#15), voice rehearsal (#13) | **One surface, not the core** |
| Spreadsheet compiler / checker | AuditSheet (#1), Ghost-Fill (#9), Sheetproof (#10) | **Pick checker or compiler, not both vs Microsoft** |
| Neuro-symbolic “prove it” | Knot (#7), SameQuery (#16), Sheetproof (#10), CiteLock quotes (#8) | **Same architecture, different artifact** |
| Legal documents | CiteLock (#8), Clause Canvas (#26), SMB redline (#27) | CiteLock is the falsifiable one |
| Construction / ops | Bid extractor (#17), shop scheduler (#18), Knot (#7) | Sales-cycle products |
| Voice-agent industry | Voice QA (#24), computer-use tutor (#5) | QA is shippable; computer-use is not |

---

# Wow ranking at a glance

| Wow | Idea | Ship in 6–8 months as a company? |
|---|---|---|
| 9 | AuditSheet | Maybe, if you beat Copilot/Claude on formulas-not-values |
| 9 | Full-duplex meeting simulator | As HearMe’s wow surface, not v1 |
| 9 | Native S2S tutor | No — wrapper; Speak owns it |
| 9 | Voice-clone native | No — BIPA / deepfake / impersonation |
| 9 | Computer-use English practice | No — agents don’t work; prompt injection |
| 8 | **HearMe intelligibility scan** | **Yes, if week-4 eval holds** |
| 8 | Knot scheduler | Yes, one vertical only |
| 8 | CiteLock quotes | Yes, quotes-only, with a lawyer partner |
| 8 | CSV Ghost-Fill | Feature, not a company |
| 8 | Sheetproof | Yes, as checker-that-cannot-write |
| 8 | Paper claim auditor | Fragile WTP |
| 8 | Live meeting overlay | No — Poised graveyard |
| 8 | Error-pattern discovery | v2 |
| 8 | Ambient gym | No as core; yes as capped later surface |
| 7 | SameQuery | Yes, as eval infra |
| 7 | Bid extractor | Sales-heavy |
| 7 | Shop CP-SAT | Sales-heavy, dirty data |
| 7 | Contradiction receipts | Maybe, if it refuses to be a notetaker |
| 7 | Pitch contour | HearMe mode |
| 6 | Voice-agent QA | Yes, if you skip consumer |
| 6 | Query / Clause canvas | Quiet wow, crowded |
| 5 | HVPT | HearMe mode |

---

# What “wow” actually was, across the panel

The 2024–2026 products that felt magical did not win with a smarter chat box. They put generation **inside an existing skill loop**, with accept/reject cheaper than thinking:

- Cursor Tab — ghost the next edit, Tab/Esc.
- Suno — two takes on the same object, iterate in place.
- Granola — notes you didn’t take; your text black, AI gray; zoom to quote.
- OpenAI Canvas — targeted edit of a span, version restore.
- Midjourney web — a canvas, not a Discord scroll.

The roundtable’s design rule, applied to this catalog: **if the happy path is a blank composer, kill it.** If the first session is an artifact you can see, tap, and undo, keep it.

That is why AuditSheet (a living workbook), the meeting simulator (a clip of you getting talked over), HearMe (A/B of your voice), Knot (a minimal impossibility), and CiteLock (a red fake cite) outrank conversation gyms — even when the gym *feels* more like 2024’s keynote.

---

# Sources (selected)

Full citations live in the roundtable persona outputs. Load-bearing ones for this catalog:

- WorkstreamBench / SpreadsheetBench — Excel agents hardcode numbers; Copilot ~20% on real tasks
- [OpenAI Realtime](https://developers.openai.com/api/docs/guides/realtime) — buyable S2S; 60-minute cap
- [BEA 2026, ASR overcorrection](https://aclanthology.org/2026.bea-1.23/) — 82% overcorrection on speechocean762
- [GOPT](https://github.com/YuanGongND/gopt) — public GOP ceiling
- [Munro & Derwing functional load](https://doi.org/10.1016/j.system.2006.09.004)
- [Speak $1B](https://techfundingnews.com/openai-backed-speak-closes-78m-at-1b-valuation-for-ai-powered-language-tutor/)
- [BoldVoice $21M / $10M ARR](https://slator.com/boldvoice-raises-21m/)
- [Charlotin hallucination tracker](https://www.damiencharlotin.com/hallucinations/)
- [CourtListener citation lookup](https://www.courtlistener.com/help/api/rest/v4/citation-lookup/)
- [Text2Zinc](https://arxiv.org/html/2509.08970) / MCP-Solver — NL → solvers not push-button
- [OSWorld 2.0](https://osworld-v2.xlang.ai/) — 20.6% long-horizon computer use
- EU AI Act Art. 5 / Art. 50; [BIPA](https://ilga.gov/legislation/ilcs/documents/074000140K20.htm); ABA Formal Opinion 512
- RevenueCat 2026 — AI apps retain worse; day-0 trial cancels
- This repo: `research/literature-review.md` (intelligibility vs nativeness; ASR vs suprasegmentals)

---

*Roundtable: Staff Engineer, Product Manager, Data/ML, GTM, Product Designer, DevOps/SRE, Security & Privacy, then Moderator. 30 Aug 2026.*
