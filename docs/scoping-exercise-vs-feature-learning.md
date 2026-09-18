# Scoping: Does scripted read-aloud actually help people speak English better?

**Format name:** this is **Reading** (alias Format 1). See `docs/formats.md`.

**Frame:** Empathy-first adults who freeze speaking aloud. Ignore our product-spec and current UI. Exercise = what professionals/research use; feature = digital adaptation.

**Panel:** SLA pedagogy · Clinical SLP · CAPT effectiveness · Fluency/anxiety · Learner empathy. All five: **YELLOW**.

---

## TL;DR verdict

- **Overall:** **GO-IF** — the *exercise* is real and useful as **Stage 1**; it is **not** enough alone for “confident public speaking.”
- **Feasibility (of benefit):** 🟡 — large effects on controlled/read-aloud clarity; weaker on spontaneous talk.
- **Scope:** **M** — keep private read-aloud; add transfer ladder + non-shaming feedback; don’t claim public-speaking cure from scripts alone.
- **Product-fit (empathy):** 🟡 — private alone practice fits anxious users; score-heavy ASR can recreate shame.
- **Market-fit:** n/a (learning-outcome question, not GTM).
- **Next step:** Keep the exercise; redesign the feature around **intelligibility + keep-moving-forward + bridge to unscripted speech**.

---

## Does the exercise help? (short answer)

**Yes — for clearer speech on known text and low-stakes mouth practice.  
No — not by itself for “speak confidently in public without tripping.”**

| Claim | Evidence |
|-------|----------|
| Pronunciation teaching works | Lee, Jang & Plonsky 2015, *d* ≈ 0.89 ([doi](https://doi.org/10.1093/applin/amu040)) |
| Read-aloud / controlled practice is where gains are strongest | Same meta: controlled *d* ≈ 0.96 vs free speech between-group *d* ≈ 0.37 |
| Therapists really use passage reading + clarity feedback | [ASHA Accent Modification](https://www.asha.org/practice-portal/professional-issues/accent-modification/) lists read-aloud, record/self-review |
| Goal should be being understood, not “sound native” | Munro & Derwing; ASHA elective intelligibility framing |
| Digital CAPT helps (medium effect) when feedback is explicit | Ngo et al. ASR-CAPT *g* ≈ 0.69; explicit CF *g* ≈ 0.86 |
| Solo unsupervised CAPT is weaker | Ngo: alone *g* ≈ 0.44 vs teacher *g* ≈ 1.24 |
| Reading aloud ≠ talking | Segalowitz: planning/retrieval load missing; transfer to spontaneous often fails ([Speech Prosody 2022](https://doi.org/10.21437/speechprosody.2022-163)) |
| Confidence in public needs exposure to *unscripted* speaking | PSA/CBT exposure meta ([doi](https://doi.org/10.1177/0145445521991102)); RA anxiety drop ≠ skill transfer ([EUROCALL](https://doi.org/10.4995/eurocall2023.2023.16956)) |
| Clear-speech style work can raise ease of understanding + reported confidence | Behrman 2017 ([AJSLP](https://pubs.asha.org/doi/10.1044/2017_AJSLP-16-0177)) |

**How it helps when it works:** learner practices hard sounds/stress on a known script (attention free for form) → gets corrective feedback → repeats → builds clearer articulation. Prosody + high-impact sounds matter more than polishing every accented phone.

**How professionals structure it:** assess → few high-impact targets → listen/imitate → short known passages → **then** role-play/spontaneous probes → fade feedback (ASHA; Maas et al. motor learning 2008).

---

## Exercise vs feature

| | Exercise (literature) | Typical digital CAPT feature |
|--|------------------------|------------------------------|
| Keeps | Known-script practice, repetition, private rehearsal | Same |
| Often loses | Teacher target selection, bridge to free speech, prosody coaching, mediation | Solo “score the script” |
| Extra friction | — | False ASR “wrong,” shame scores, mid-flow judgment |

**Adaptation verdict:** A digital feature *can* deliver Stage-1 benefits **if** feedback is sparse, intelligibility-first, forgiving, and followed by a transfer step. Straight “score my passage” is **not** a full adaptation of therapy.

---

## Blind spots (Moderator)

1. **Unknown:** For *this* persona, is the real bottleneck pronunciation, message planning, or fear of being judged? Panel assumed mix — **unverified without user research**. Wrong primary exercise if fear >> pronunciation.
2. **Conflict:** Empathy wants private safety; CAPT meta says **alone** under-delivers vs peer/teacher. Tension: keep private *core*, add optional mediated/transfer later — don’t force peers early.
3. **Over-consensus:** Everyone said YELLOW/transfer gap. Real, but risk of killing a good Stage-1 tool. Therapists still use read-aloud — don’t over-correct.
4. **What kills this in 6 months:** Claiming “speak confidently in public” from read-aloud alone → users feel lied to when real conversation still hurts.

---

## Open questions

1. Primary bottleneck for target users: sounds, planning, or anxiety?
2. Will listener-rated spontaneous comprehensibility move, or only script scores?
3. What false-rejection rate makes anxious users quit?

---

## Sources (panel)

- [SLA pedagogy](b9f32274-8ce2-4629-b526-6e50ada6aeed) · [Clinical SLP](a065f8d0-c4d0-4ced-97df-be80cf12a4d9) · [CAPT](460c3926-59fd-4675-96c6-711af988ebb9) · [Fluency/anxiety](7cac706f-f842-4de5-ba6f-83e5d3414a95) · [Empathy](3e3b1cf3-e4b8-4bca-a42e-db40a05df8fb)
