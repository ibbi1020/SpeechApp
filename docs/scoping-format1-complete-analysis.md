# Scoping: Finish Reading analysis (least-cost path)

**Format name:** **Reading** (alias Format 1). See `docs/formats.md`. Conversation = Format 2.

**Frame:** What blocks a “finished” Reading today, and what is the cheapest credible way to catch “right word, wrong sound” without training a huge custom model?

**Decision this informs:** Train vs buy vs reuse open on-device models; whether cloud CAPT is allowed; sequencing vs Format 2.

**Panel:** [Staff Engineer](1a6a5178-5056-465e-8f69-c3a831b555c2), [Product Manager](f259bcca-22c3-4b60-8a9a-7552bc31d424), [Data/ML](b0f9c39f-afd4-474d-a414-2364bce68285), [Finance](7567962e-f8ac-47a4-9e88-60df362a4b95), [Security & Privacy](8662b1b5-af73-4718-9589-aad31ae06c61), [GTM](15953f43-ae95-45c9-afd2-e41ad9a078c2). Moderator pass completed 2026-09-07.

---

## TL;DR verdict

- **Overall:** **GO-IF** — finish Format 1 with a **reused on-device phoneme model + sound-scoring math**, not by training from scratch and not by shipping cloud CAPT under today’s privacy copy.
- **Feasibility:** 🟡 — science exists; **this repo still has no audio buffer for scoring and no real sound scorer** (`NotAssessedGOPScorer`; empty PCM at stop).
- **Scope:** **M** — post-Stop scoring of **high-importance sound contrasts** on known passages + ranked report + next-passage picks. Cut: accent meters, full ELSA parity, custom foundation model, live red “poor sound” until calibrated.
- **Product-fit:** 🟢 — Format 1’s job is private diagnosis of sounds that matter for being understood; Slice A alone is not that job.
- **Market-fit:** 🟡 — ELSA/BoldVoice win paid phoneme feedback with cloud CAPT; SpeechApp should not pretend to beat them — keep Format 1 as honest calibration while Format 2 carries the product.
- **Recommended next step:** **2-week spike** — keep audio slices on device → run a small open phoneme model + published scoring math → plant ship/sheep-style errors → measure false “you said it wrong.” Only then wire the UI. Do **not** train a model from scratch. Do **not** send user audio to Azure/ELSA/Speechace while Consent still says “stays on this phone.”

---

## Plain answer (what was planned / what’s blocking)

### What Format 1 was always trying to do

From the product plan (`docs/product-spec.md`):

1. User reads a **known short passage**.
2. App follows along (skip / add / swap) — **Slice A, largely built**.
3. App also checks **whether the sounds were right**, even when Apple’s listener wrote the correct word — **Slice B, not built**.
4. End report ranks **easy-to-catch** sound mistakes and picks the **next practice passage**.

You do **not** need to invent “phoneme detection” from zero. The plan was: use an existing speech acoustic model + a known scoring method (often called GOP) on the **raw audio vs the script’s expected sounds** — never score Apple’s transcript (`docs/architecture-format1-prototype.md`).

### What is blocking *right now*

| Blocker | Why it matters |
|---|---|
| **No real sound scorer** | `NotAssessedGOPScorer` always says “not assessed” (`GOPScorer.swift`). |
| **No saved audio slices** | Stop path scores an empty buffer; `PCMStore` from the architecture doc was never built. |
| **No per-word sound spellings** | Passages only have coarse tags for scheduling, not the phone sequences GOP needs. |
| **Not “we must train a giant model”** | Panel unanimous: **reuse** a pretrained open model; train-from-scratch is XL and unnecessary. |

### Do we need to train an ML model?

**No — not from scratch.** Least-cost path: take a **pretrained open phoneme model** (research already published), convert it for iPhone, run published scoring math against the script’s sounds, calibrate on free L2 test sets (e.g. Speechocean762) plus a tiny in-house minimal-pair battery. Optional tiny fine-tune later if needed — that is weeks, not a foundation-model project ([Data/ML](b0f9c39f-afd4-474d-a414-2364bce68285); GOPT / CTC-GOP literature).

---

## What we'd build (scope)

**MVP (finished Format 1 at least cost)**

1. Keep mic audio in a short on-device ring buffer; delete after Stop (already the privacy lock).
2. After Stop (v1 — safer than live): for each finalized word window, score expected sounds vs audio.
3. Author **expected sounds** for the 8–12 passages (or generate + hand-check).
4. Report only **high-importance** sound misses (functional-load ranked) — not a native-likeness %.
5. Feed StruggleLedger → next passage (scaffolding already exists).
6. Gate ship on a **planted-error harness** (deliberate ship/sheep takes must light up; clean takes must not flood with false poor).

**Out of scope for this pass**

- Training a custom acoustic model from labeled learners.
- Shipping Azure / ELSA / Speechace as the product scorer under current consent.
- Accentedness scores, live IPA, spectrograms, forced pace.
- Claiming Format 1 alone creates confident spontaneous speaking (transfer gap — prior exercise scoping).

**Later**

- Lagged live “poor sound” underline (after post-Stop path is proven).
- Stress/rhythm as a separate report line.
- Optional labeled cloud only if product deliberately rewrites privacy story + BIPA program ([Privacy](8662b1b5-af73-4718-9589-aad31ae06c61)).

---

## Feasibility

- Slice A shell + ledger + picker: **done** ([Staff Eng](1a6a5178-5056-465e-8f69-c3a831b555c2)).
- Slice B: open CTC / alignment-free GOP stacks exist; Apple SpeechAnalyzer is **not** a pronunciation scorer ([Data/ML](b0f9c39f-afd4-474d-a414-2364bce68285); WWDC25 session 277).
- Hard parts: CPU-only scoring while Apple speech runs; phone-set mapping; L2 false-poor rate; A13 floor still unproven (`docs/scoping-on-device-compatibility.md`).
- Effort: **L** eng + **M** calibration for on-device path; **XL** if train-from-scratch (reject).

---

## Product-fit

- Finished ≠ “follow-along works.” Finished = catch ASR-accepted sound errors on a known script ([PM](f259bcca-22c3-4b60-8a9a-7552bc31d424); `architecture-format1-prototype.md` honesty test).
- Success metric: sessions where ≥1 high-importance sound miss is surfaced that word-follow would miss — without shaming intelligible speech.
- Format 2 remains product MVP; Format 1 is soft calibration/drill (`docs/product-spec.md`).

---

## Market-fit

- Paid adult apps sell phoneme feedback via **cloud CAPT** (ELSA, BoldVoice, Speechace, Azure PA) ([GTM](15953f43-ae95-45c9-afd2-e41ad9a078c2)).
- Light on-device GOP will **not** beat that category on raw accuracy; it can still fulfill SpeechApp’s job if positioned as **private, scoped diagnosis**, not “ELSA killer.”
- Shipping Slice A as if it were phoneme diagnosis is a **trust collapse** risk (critical).

---

## Cost & economics

| Path | Build | Run (early MVP) | Panel call |
|---|---|---|---|
| Cloud CAPT (Speechace ~$40–80/mo; Azure ~STT rates) | 0.5–1 eng-mo | Low $ at small scale | Cheap $ — **expensive privacy/positioning** |
| Open pretrained → on-device | ~3–6 eng-mo (more if A13+live) | ~$0 inference | **Best fit to locks** |
| Train own AM + labels | 6–12+ mo + label $ | ~$0 later | **Worst ROI** |

Format 2 speech cost/battery risk already dwarfs Format 1 CAPT COGS at scale (`docs/product-spec.md`) — so **don’t burn a quarter on Slice B before Format 2 learning** unless the honesty bar for demos requires it ([Finance](7567962e-f8ac-47a4-9e88-60df362a4b95)).

---

## Risks (ranked)

| Risk | Severity | Raised by | Mitigation |
|------|----------|-----------|------------|
| Claim finished Format 1 with Slice A only | Critical | PM, GTM | Don’t; gate on Slice B honesty test |
| Cloud CAPT under “stays on phone” consent | Critical | Privacy | On-device default; rewrite consent only if product flips |
| False “poor sound” shames anxious users | High | PM, GTM, ML | FL-only flags; high threshold; planted-error QA |
| Opportunity cost vs Format 2 | High | Finance, PM | Spike ≤2 weeks, then decide; Format 2 still MVP |
| A13 / CPU co-tenancy fails | High | Staff Eng, ML | Prove on iPhone 15 first; post-Stop-only v1 |
| Phone inventory mismatch | High | Staff Eng, ML | Author lexicon for catalog; map to AM phones |
| Train-from-scratch rabbit hole | Med–High | All | Explicitly cut |

---

## Blind spots & conflicts (Moderator)

### Unknown unknowns

1. **Content cost of phone authoring** for every word in 8–12 passages can rival the ML spike if done by hand — use G2P + linguist spot-check, not blank-page authoring. (Underweighted by panel.)
2. **Offline oracle vs product path:** Speechocean762 + a desktop open GOP stack can validate thresholds **without** shipping cloud to users — Finance’s “license CAPT briefly” and Privacy’s RED can both be true if cloud is **lab-only**, never in the App Store build.
3. **What kills this in 6 months:** either (a) users discover sheep/ship never flagged, or (b) endless Slice B polish delays Format 2 until the product has no conversation loop.
4. **HF / model redistribution license** inside App Store binary still unresolved ([Data/ML](b0f9c39f-afd4-474d-a414-2364bce68285) open Q).

### Conflicts (do not average away)

- **Finance:** cloud CAPT is cheapest dollars for early scoring. **Privacy:** cloud under current Consent is **RED**. → Resolution: **on-device for product**; optional **offline/lab** cloud or open oracle for calibration only.
- **GTM:** light on-device won’t win ELSA’s job. **PM:** Format 1 doesn’t need to win that job — soft diagnostic. → Resolution: **honest scoped Format 1**; monetization/WTP on Format 2.
- **Staff Eng / ML:** on-device is L and unproven on A13. **Finance:** don’t spend 6–9 months before Format 2. → Resolution: **time-boxed spike** with a kill criterion (fail ship/sheep discrimination → keep Slice A labeled incomplete).

### Over-consensus / rabbit holes

- Panel over-agreed “don’t train from scratch” (good — evidence-backed).
- Risk of **over-investing in full phoneme inventory** when Munro & Derwing high-FL contrasts are the product promise — start with **contrast set only**.

---

## Open questions before committing

1. Is “finished” for the next milestone **post-Stop FL sound report only**, or also live lagged poor-sound?
2. Absolute on-device for all user audio, or allow a future labeled opt-in cloud (product decision)?
3. Acceptable false-poor rate for anxious users?
4. Spike before Format 2 start, or after Format 2 skeleton?
5. Device floor for Slice B: iPhone 15 first, then A13?

---

## Sources (grouped)

- Product / architecture: `docs/product-spec.md`, `docs/architecture-format1-prototype.md`, `docs/scoping-on-device-compatibility.md`, `docs/scoping-exercise-vs-feature-learning.md`
- Code: `GOPScorer.swift`, `ReadingSession.swift`, `ConsentView.swift`, `Info.plist`
- Research stack: Speechocean762 (openslr.org/101), CTC-GOP (isca-archive / frank613), GOPT (arxiv 2205.03432), wav2vec2 phoneme AM (HF facebook/wav2vec2-xlsr-53-espeak-cv-ft)
- Commercial: Speechace API plans; Azure PA docs + MS Q&A pricing (~$0.66–$1.32/hr STT-tied)
- Privacy: 740 ILCS 14; Rosenbach; ConsentView / architecture locks
