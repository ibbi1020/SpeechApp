# Formats — Canonical Names

Use these names in conversation and new writing. Numbers (`Format 1/2/3`) are aliases only.

**Live document.** If a name here disagrees with an older doc, this file wins.

---

## The three core formats

| Name | Alias | What the user does | What it is for |
|---|---|---|---|
| **Reading** | Format 1 | Reads a known short passage aloud (connected sentences, not isolated word drills) | Pronunciation / diagnosis. Only format where phoneme-level scoring is technically honest, because the target script is known. |
| **Conversation** | Format 2 | Open-ended talk with an AI partner | The product’s target behavior: spontaneous, interactive speech. Post-session feedback only. |
| **Monologue** | Format 3 | Familiar topic, optional notes, then three takes under 4 → 3 → 2 min ceilings | Utterance fluency on a repeated monologue. Named-index profile (take 1 vs take 3), not a letter grade. |

**Reading is not “open-vocabulary speech.”** The passage is connected prose (that is the “open reading” people mean in conversation), but the app knows every word in advance. That closed script is the whole point.

**Conversation is the product MVP** in `docs/product-spec.md`. Reading is the diagnostic / drill loop. Monologue v1 is the 4/3/2 regimen in the app — not a 5–15 min one-shot talk.

---

## Cross-format drills (not fourth/fifth formats)

These ride on sessions from the three above. Do not treat them as extra core loops.

| Name | Hosts | Job |
|---|---|---|
| **Explain It Another Way** | Conversation | After a stall / L1 switch: say the same idea three ways, no translation. |
| **Say It Like You Mean It** | Reading tech, used as a drill | Produce a sentence with an intended attitude; score contour *class*, not exact pitch. |
| **Connected Speech Challenge** | Standalone drill + sometimes inside Conversation | Fast native clip → what was actually said (reduced vs citation form). |
| **Storytelling** | Monologue variant | “Tell about a time when…” with a beginning / tension / resolution rubric. |

---

## Named, not committed

Logged in the spec, not in the product yet: **Shadowing**, **HVPT / minimal-pair drills**, **PREP frameworks**, **graduated anxiety ladder**, **formulaic-chunk retrieval**.

---

## What exists in code today

**Reading**, Slice A: live presence (**top aurora waveform** from mic energy + plain serif book passage; no live text tracking), stall nudge, struggle-led next passage; match/skip/extra on the report after Stop. Pronunciation scoring (GOP) is stubbed.

**Conversation** is in the app (home row + session).

**Monologue** v1 is in the app: the session loop, an on-device recorder, and a report after the regimen.

**How Reading live follow-along works (tech + UI + every decision’s reasoning):** `docs/scoping-reading-follow-along.md`.
