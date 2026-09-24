# Conversation (Format 2) — technical layer

**Date:** 2026-09-21  
**Status:** Architecture locked. Roundtable + **Pass 2** holes locked the same day. **v1 promise aligned 2026-09-21** with the product shape (honest report, spoken cues off, backend is not mint-only). Product shape stays in `2026-09-21-conversation-format-design.md`.  
**Not a build plan.** Implementation plan comes after you sign the locks.

The live model is the mouth and ears. Our session controller is the brain. The model does not own the clock, wrap, or crisis. v1 spoken partner lines are `open` / `wrap_warn` / `wrap_close` only.

---

## Stack

| Layer | Choice | Where |
|---|---|---|
| Live talk | OpenAI Realtime **`gpt-realtime-2.1-mini`**, pinned snapshot, `reasoning.effort: low` | Cloud (must). Flagship `gpt-realtime-2.1` is a quality spike only, not the $20/mo SKU. |
| Transport | iOS WebRTC. Backend mints an ephemeral token. | Audio does not go to our servers. Backend also enforces budget / crisis counter / minor flag. |
| Turn taking | Semantic VAD, **eagerness low**. `create_response: false`. We send `response.create`. | Phone owns *replies*. OpenAI owns barge-in and `speech_stopped`. Not L2-aware VAD. |
| Noise | iOS voice-processing IO (AEC/NS) + Realtime `near_field` | Phone + OpenAI. |
| Scoring transcript | Apple `SpeechAnalyzer` family (SpeechTranscriber **if available**, else DictationTranscriber / on-device SFSpeech). **No SpeechDetector module.** Energy VAD + word `audioTimeRange`. | Phone. Same family as Reading. |
| Code-switch | Dual-locale `SpeechTranscriber` if L1 is known; else WhisperKit **language-id only** on the finalized turn (not a 15 min stream) | Phone. |
| Fillers | On-device acoustic filler model (Core ML, ~20 ms frames). Not ASR text. | Phone. |
| Pause time / pace | Word `audioTimeRange` + energy VAD gaps. **No SpeechDetector. No clause segmenter in v1.** | Phone. |
| Crisis | On-device: keyword / phrase list on every device; Apple Foundation Model structured classify when the silicon has it | Phone. Keywords fail closed. FM timeout fail-open. Persona never speaks crisis. |
| Report phrasing | Templates. No PMI corpus in v1. Foundation Model only if we later add a grammar line on Apple Intelligence | Phone. After hang-up. |
| Session brain | Clock, pause, cue queue, hang-up — **on the phone** | Phone. |
| Background | `UIBackgroundModes: audio` + `playAndRecord`. ActivityKit. **No CallKit.** | Phone. |
| Audio retention | Process-and-delete. Scalars + text report only. | Phone. |

**Cloud in v1:** OpenAI S2S (audio never hits our servers) **plus our backend:** ephemeral key mint, **server-enforced** 20 starts / calendar month, 1 concurrent session, 3 mints / 10 min, anonymous `crisis_referral_events` increment, persist `possible_minor_flag`. Not mint-only.

**Not used in v1:** AssemblyAI (or any second cloud STT). `omni-moderation` as a required hop. Gemini Live as the mouth (audio-only media still tops out at 15 min without compression; WebSocket ~10 min needs a mid-session resume; we already cap at 15 min, so this is a cost fallback to re-test, not the default). Hume as the conversation brain. MCP. Live STT→LLM→TTS. On-prem Moshi / Freeze-Omni.

### Cost vs a $20/mo subscription

AssemblyAI was never the bill. Streaming Pro is **$0.45/hr of open socket** → about **$0.11** for 15 min. Dropping it does not save the business.

Almost all of the **$1.20–$2.20** was OpenAI **flagship** audio (`$32` / `$64` per 1M audio in/out). Mini is **`$10` / `$20`** — about **⅓**. With caching and mic muted on pause:

| Live model | ~COGS / 15 min (on-device scoring) | Sessions until ~$14 net (Apple’s 30% cut of $20) |
|---|---|---|
| Flagship `gpt-realtime-2.1` | **$1.00–$2.00** | **7–14** |
| **Mini `gpt-realtime-2.1-mini` (v1 default)** | **$0.35–$0.75** | **18–40** |

So: OpenAI is still the right **mouth** (full duplex, 60 min session, we own `response.create`). Flagship is the wrong **price** for unlimited $20/mo. Mini is the SKU. A $20 plan still cannot be unlimited daily flagship talk — include a session budget (20 × 15 min / calendar month) and sell more, or the COGS eats the sub even on mini if someone talks every day.

**Ballpark, not a worksheet.** Mini **$0.35–$0.75** / 15 min assumes cache hits after turn 3 (`cached_input_tokens / input_tokens ≥ 0.5` is a quality-spike watch). Mute + no `response.create` on pause stops *new* audio billing; history may still be re-read on resume. Token sticker prices (mini `$10` / `$20` per 1M audio in/out) are real; the 15-minute dollar band is not derived in-repo. **Battery/thermal of 15 min SpeechAnalyzer + WebRTC on iPhone 11 is not modeled** — ANE exclusivity is a rule, not a soak. Quality spike does not replace that soak.

Gemini Live’s sticker audio is cheaper (~$0.005/min in, ~$0.018/min out) but it is not a clean swap: 15 min media ceiling without compressing history, ~10 min connection, pause/VAD still needs us to drive turns. Revisit only if mini COGS still misses the sub after a quality spike.

---

## Who decides what

```
iOS  — mic, playback, pause UI, clock, aurora, Live Activity
       session controller (cues, crisis gate, hang-up)
       SpeechAnalyzer family + energy VAD + filler Core ML
       language-id on each finalized user turn
       WebRTC audio ↔ OpenAI
       sends response.create (with optional extra instructions)

Our backend
       mints ephemeral Realtime keys
       enforces 20 starts / calendar month, 1 concurrent, 3 mints / 10 min
       anonymous crisis_referral_events; possible_minor_flag

OpenAI Realtime
       hears them, speaks, barges in
       does not call tools in v1
```

Barge-in (they interrupt the partner) stays on the Realtime path. Cues (we need the partner to mention something) wait for the **next user turn**.

---

## Cues — fold into the next reply

We never splice into the current sentence. One active response at a time. `response.create` during playback errors or, if cancelled, cuts them off.

**Rule:** when a cue is due, set a flag. Do not talk. On the next `speech_stopped`, attach the cue to that turn’s `response.create` `instructions`. **`instructions` replace session instructions** — send **frozen persona prefix + stance card + cue**, never the cue alone.

Prompt shape (one pending cue at a time):

> {frozen_persona_prefix}
> {stance_card}
> Answer them as you were going to. In the same turn, one short aside: {cue}. Stay on the topic. Do not announce a timer or a system message.

| Cue | When we set the flag | What they should hear |
|---|---|---|
| `open` | Session start (no user turn yet) | A real question. Forced first `response.create`. |
| `wrap_warn` | Clock hits T–2 min | In-character: about two minutes left. Then the talk continues. |
| `wrap_close` | Clock hits cap **and they did not tap Stop** | In-character close, then we hang up. User Stop never gets a spoken close. |
| `code_switch` | On-device language-id says this turn was not English | Try that last bit in English; messy is ok. |
| `filler_ok` | Repeated filler *pattern* (not a single “uh”) | Take your time; silence is fine. Do **not** name or count “uh”. |
| `crisis` | On-device crisis gate flags self-harm / intent | **Not** a persona cue. Stop the partner. Play a canned 988 referral. End session. |

v1 **speaks** `open` / `wrap_warn` / `wrap_close` only. Live `code_switch` / `filler_ok` ship as flags, **default OFF**. When later enabled: at most **1–2 heard** asides per session, never both in the same turn — take `code_switch` first. Wrap warn/close do **not** count against that 1–2. A cue the model ignores does **not** consume the heard-aside budget.

If T–2 min hits while they are silent, wait. If 1.5 min silence auto-pauses first, freeze the clock; on resume the wrap flag is still pending and folds into the next reply. If they never speak again after the cap, skip a spoken close and go to the report. Do not wait forever. Copy never says “you went quiet.”

Wait for `response.done` before any new `response.create`.

**Do not:** `conversation.item.create` fake system/user lines; `session.update` of instructions for a one-shot cue (often ignored); `input: []` (drops the conversation).

---

## Per-turn detectors (on the phone, not the speaking model)

The live model is **not** asked to notice code-switch, fillers, or crisis. Its transcript is cleaned (fillers dropped, L1 often turned into English). Putting that in the system prompt would also fight “do not name uh” and would fail the same way tools fail: the model may just keep talking.

No second cloud STT. No detector LLM in the cloud. Mic PCM is forked **on device**: WebRTC → OpenAI (talk only); a short RAM ring → Apple Speech + local classifiers. Audio is not uploaded to us.

**Why not AssemblyAI:** it is a hosted ASR. It returns words, timestamps, `language_code`, and (on Pro) disfluencies. That is convenient, but (1) it is another cloud hop, (2) language-id on mixed speech flickers, (3) the 300 ms wait against OpenAI `speech_stopped` made live nudges depend on a network race — that is the non-determinism. Local models still vary utterance-to-utterance (all ASR does), but weights are pinned with the OS / our Core ML file, and cue timing no longer waits on a second vendor.

Apple `SpeechTranscriber` has **no verbatim/filler mode** (it can even apply `.etiquetteReplacements`). Do not count “uh” from Apple’s text. Fillers come from a small **acoustic** model on the waveform.

When OpenAI emits `speech_stopped`:

1. Scoring may `finalize(through:)` the on-device turn (wait up to **2 s**). **`response.create` waits only for OpenAI `speech_stopped`**, plus the **keyword** crisis gate. SpeechDetector is **not** attached in v1.
2. **Crisis keywords** — always, on volatile ∪ final. Hit → canned 988, hang up, **no** `response.create`. FM classify if present (400 ms timeout → **fail open**, allow reply). Keywords win over FM timeout: a keyword hit is fail-closed even if FM is slow. Empty Apple text after 2 s → **still allow S2S**; skip scoring cues; do not 988 (Apple hiccup is not crisis).
3. **Cough / empty turn:** OpenAI `speech_stopped` **and** Apple transcript empty **and** energy-VAD speech &lt; ~300 ms → **no** `response.create`, do not consume a cue. This is not the 2 s Apple-timeout case.
4. **Code-switch / filler** — report path after hang-up; live cues default **OFF**. Until live-on, do not wait for LID/filler before `response.create`.
5. Attach at most one **lifecycle** cue (`wrap_warn` / `wrap_close`) in v1. Then `response.create` unless cough/empty as above.

Wrap warn/close still come from **our clock**.

The speaking model only sees the extra `instructions` on that `response.create`. It never classifies the user.

On-device crisis will miss paraphrases a hosted moderation API would catch. That is the trade for not sending turn text off-device. **Keywords fail closed; FM timeout fail-open; empty Apple text is not 988.** The persona never *speaks* crisis — canned 988 owns that path. Keyword+FM is **not** claimed as SB 243 “evidence-based.” Website protocol + counsel copy remain a **ship blocker**. `omni-moderation` optional, default off.

---

## Tools

### Realtime `tools` array: empty in v1

`tool_choice: none`.

The model does not select tools. `gpt-realtime-2.1` has a documented production failure: it answers instead of calling (~25% vs 98–100% on `gpt-realtime` Aug 2025). MCP also mixes up local vs remote tools. Load-bearing work must not wait for a call that may never arrive.

Optional lookups (web, topic facts) can be added later as **local function tools**, `tool_choice: auto`, never `required`. Not v1.

### Local functions (our code — these are the real tools)

The session controller, not the model:

| Function | Job |
|---|---|
| `mintEphemeralKey` | **Server.** Realtime client secret + safety identifier. One of several cloud functions (also budget, crisis counter, minor flag). |
| `startSession` | Stance card sampled. First `response.create` with `open`. **Wall clock starts when first partner audio plays**, not at this call. |
| `pause` / `resume` | Mute **and release** mic. Freeze/unfreeze clock. Same Realtime session. |
| `onSilence1_5min` | Auto-pause. **Same 1.5 min in foreground or background.** |
| `onUserTurnFinal` | Local transcript final. Keyword crisis before reply. LID/filler async for the report while live cues are off. |
| `onClockTminus2` | Queue `wrap_warn`. |
| `onClockCap` | Queue `wrap_close` if a turn is in flight; else hang up to report. |
| `hangUp` | Stop audio, close Realtime, run report, delete PCM. |
| `onCrisis` | Abort persona. Referral. Hang up. |

Scoring worker (after stop, on the **on-device** transcript + timestamps + filler spans — not the live model):

| Function | Job | Method |
|---|---|---|
| `timeSpoken` | Sum of user speech segments | Union of EN `audioTimeRange`; energy-VAD coverage check. Uncertain if coverage &lt; 0.7 |
| `englishSlips` | Turns / spans not English, or `uncertain` | WhisperKit language-id on finalized turn (v1 does not collect L1, so dual-locale is unused unless we add an L1 field later) |
| `fillerPattern` | Only if a pattern exists | Acoustic filler spans. Describe as filled pauses. **L2 soak before claiming a pattern on the report**, not only before live. |
| `pace` | Syllables / min, **no target** | Grapheme / vowel-nucleus heuristic documented in code. Raw number only. |
| `pauseTime` | How much they paused | Pauses ≥250 ms from energy VAD + `audioTimeRange` gaps. **Not** mid- vs between-clause. |
| `hardToFollow` | **Not v1 UI** | Needs a named spoken-corpus collocation table **and** a closed effortful-grammar list. PMI slogan without those artifacts stays off the report. |
| `logOnly` | Raw scalars for later baseline / chips | Duration, turn count, pace, pause ms, slip/uncertain flags, filler spans. **Do not** log IC / coherence / vocal variety / Gap 2 variance as if extractors exist. |

“Understood?” stays gated (disfluency bias). Not v1 UI. No population-normed “normal ranges” on the v1 report.

---

## Partner (prompt, not a tool)

Session instructions, stable for the whole call (so prompt cache holds):

- Rehearsal partner, not a friend, therapist, or human.
- Holds a **stance card** sampled at start (3–5 real views). Disagrees on the point, not the person.
- Warm, curious, never fawning. Do not pile on.
- English only. **Do not** sprinkle calibrated slang/connected speech as a Gap 1 mechanic in v1 — that is later, with a frequency cap. Casual register is fine; do not bully.
- Fillers and silence are allowed. Do not name “uh”. There is no live `filler_ok` cue in v1.
- Educational rehearsal, not therapy, counseling, or a mental-health companion.
- Do **not** infer stuckness, hesitation, or fillers from how they sound — those live in on-device detectors, not this prompt.

AI disclosure is **on-screen at each Conversation start** (at most once per calendar day) and a persistent “AI partner” label. The voice does not claim to be human. Minimum age: **18+** attestation at account create. Architecture is locked; **ship is blocked** on website protocol + counsel 988/22604 copy. FTC / EU AI Act / relationship-rupture / telemetry-disclosure remain open (not v1 engineering).

---

## iOS surface (UI only, from Reading)

Reuse: start countdown, pause/stop row, aurora from mic energy, dark serif chrome, report as a stable-order scroll.  
Do not reuse: TokenAligner, GOP, passages, StruggleLedger, live text tracking.

Live Activity: listening / they-speak / paused.

---

## P99 bar

| Must happen | How we guarantee it |
|---|---|
| Session ends by 15 min | Our clock, not the model |
| Cue never mid-sentence | Flag + next user turn only |
| Crisis stops the buddy | On-device gate before `response.create` |
| Report has slips / fillers we can defend | On-device Speech + acoustic fillers + language-id; else `uncertain` / omit |
| Wrap still happens if they ignore the aside | Timer hangs up anyway |

Spoken asides are UX. They are not the control plane.

---

## Locked after roundtable (2026-09-21)

Panel: staff engineer, PM, on-device STT, conversational-voice product, security/privacy, legal/compliance. All **YELLOW**: stack is right; session-edge, detectors, VAD flags, mint, and SB 243 artifacts were unspecified. Conflicts resolved below (not averaged).

**Build** against this file. **Ship mini as the $20/mo mouth** only after the quality spike **and** an iPhone 11 15-min thermal soak. **Ship the product** only after website protocol + counsel copy. Counsel still owns 988/22604/protocol **wording**.

### Transport and audio

- **Client:** in-house WebRTC over `stasel/WebRTC`. Data channel `oai-events`. SDP offer → `POST /v1/realtime/calls` with ephemeral Bearer. No Pipecat, no community Swift Realtime SDK as the control plane.
- **Audio session:** `.playAndRecord` + `.voiceChat`. **`defaultToSpeaker: true`** so earpiece-only iPhones are audible without headphones. WebRTC owns activation (`RTCAudioSession` manual). One **bounded PCM ring** (not Reading’s unbounded `PCMStore`) fans out to OpenAI + SpeechAnalyzer. **Never** start Reading’s `MicAudioSource` (`.record` / `.measurement`).
- **Headphones:** unplug / Bluetooth drop while talking → **pause** (same as the pause button). Volume 0 is **not** pause. Plug-in does not auto-resume.
- **Countdown:** send-muted until 0. Mint + SDP **after** 0, not during the 3-2-1.
- **ICE:** wait `iceGatheringState == complete` (10 s) before posting SDP. Include Google STUN (`stun:stun.l.google.com:19302`) plus OpenAI’s candidates. One retry. **v1 has no WebSocket fallback** (rejected: extra truncate path). Hard fail → partial report. Residual: we do **not** require a server-SDP rewrite in v1; name it if NAT fails in TestFlight.
- **Mint body:** nested JSON as OpenAI documents (`session.session.type = realtime`, model, audio, tools: []). Do not flatten to top-level `model`.
- **Drop mid-talk:** freeze clock on `disconnected`. **3 s** same-peer grace. If `failed` / closed: **do not** mint a silent second Realtime and keep talking. Capsule: connection lost. **End and see report** always. **Try again** = new session; **does not** consume a second budget slot if they never saw a report. Staff “inject 800-char summary into a new session” is rejected (fake continuity).
- **Model pin:** request `gpt-realtime-2.1-mini` (today that *is* the alias). Log `session.created` model. If a dated snapshot appears, pin it within 48 h. `reasoning.effort: low`. Voice: `marin` or `cedar`, pick in the spike, then freeze.

### VAD, barge-in, cues

```
turn_detection: {
  type: "semantic_vad",
  eagerness: "low",        // ~8s max wait; there is no silence_duration_ms on semantic_vad
  create_response: false,
  interrupt_response: true // native barge-in; do not copy the docs’ both-false example
}
noise_reduction: near_field
```

- **`response.create` is gated on OpenAI `speech_stopped`.** Ghost turn = `speech_started` with **no** `speech_stopped` for **8 s** → do not reply. Energy-VAD end with no OpenAI stop is **not** a ghost.
- **Cue `instructions` REPLACE session instructions** (they do not append). Every `response.create` that carries a cue MUST send **`frozen_persona_prefix + stance_card + cue`**. Missing the prefix wipes the partner for that turn.
- **Cue ignore:** on `response.done`, regex the output transcript. `open` miss → retry **once**. `wrap_warn` miss → fold again next turn. `wrap_close` miss → hang up anyway. `code_switch` / `filler_ok` miss (when those cues are live) → **do not** consume the heard-aside budget; do not retry in-turn. If they **name “uh”**, treat as leakage, do not re-queue.
- **Cue pending + barge-in:** let WebRTC cancel; attach the **same** pending cue on next `speech_stopped`. Empty cough transcript: no `response.create`, do not consume cue.
- **`wrap_close` sequence:** mute send → `session.update` `{ turn_detection: null }` → **wait `session.updated`** → **clear input buffers** → `response.create` (frozen prefix + close) → hang up on `response.done`. Do not restore VAD. If they still barge after mute: hang up, **no** new debate turn. User **Stop** (before or after T–2): confirm, hang up, **no** spoken close.
- **First `open`:** after `session.updated`, `response.create` with frozen prefix + `open`. **8 s** to first audio delta; retry once; then fail with reconnect UI. **Clock starts when first partner audio plays.** 1.5 min silence auto-pause starts after **they** have spoken once.
- **Prompt cache prefix (freeze after first audio):** model, effort, voice, empty tools, static persona (no preambles, not therapist, English-only, never name “uh”). Stance card = **last block** of session instructions, never rewritten. Cues never live in `session.update`. `truncation.retention_ratio = 0.8`. The only allowed mid-session `session.update` is wrap_close `turn_detection: null`.
- **Watchdog:** if `response.create` and no audio in 8 s → retry once → hang up to report. Do not wait forever.

### Pause, background, budget, first session

- **User pause and 1.5 min auto-pause are the same state.** Mic **muted and released** (leave `playAndRecord` so the orange dot goes off). Clock frozen. No `response.create` on resume; wait for them. Silence timer does not run while user-paused. Copy: **Paused — still here.** Never “you went quiet.”
- **Pause TTL: 10 minutes** then hang up to report, no spoken close. Abandoned pause, not an idle scold.
- **Background while active:** orange + Live Activity stay. Silence in background uses the **same 1.5 min auto-pause** as foreground — **no 30 s forgotten-mic hang-up** (that fought the pause design). Background while paused: deactivate the audio session; Realtime may drop — if it does, resume = new connection is **not** v1; show connection-lost → report / try-again without a second budget slot if they never saw a report. Prefer keeping the Realtime session alive while paused in-app; background-paused teardown is a residual to spike.
- **Wall clock: 15 min.** `wrap_warn` at T–2 (minute 13). Dev/test 5 min is a flag, not a second product SKU.
- **Budget:** **20 started sessions / calendar month.** A start = countdown reached 0 **and** first partner audio played. Pause/resume/auto-pause/drop-retry-before-report do not add a start. Unused do not roll. Home shows `n of 20`. At 0, Start disabled. **Never paywall a live talk.**
- **First session:** no topic picker, no visible stance card. One primary **Start a conversation**. Curated `open` bank (everyday adult life, not news, not trauma) — **write 20 before build**. Account create: 18+ attestation + `§ 22604` minor-unsuitability sentence. **AI partner card at the start of each Conversation, at most once per calendar day** (NY GBS § 1702). Persistent **AI partner** label every session including Live Activity.
- **Partner does not change topic** unless the user does. No Change Topic control.

### Report floor

- **Full report** if user speech ≥ **45 s** and ≥ **3** user turns: time spoken, turn count, slips or `uncertain`, filled pauses if present, pace (raw), pause time.
- Else **thin report:** time spoken + turn count + “Too little speech to score the rest.” No zeros for pace/slips/fillers.
- **Do not** print collocation, grammar, hesitation location, vocal variety, IC, or coherence.
- Crisis: 988 screen, **not** a fluency report.

### On-device detectors

Live `code_switch` and `filler_ok` **ship as machinery, default OFF** until eval gates. Wrap/`open` still live. Until then, slips/fillers are **report-only** (or `uncertain`). Better a missed nudge than a scold on accented English.

**Device matrix**

| Capability | iPhone 11 / iOS 26 | Apple Intelligence (15 Pro+) |
|---|---|---|
| EN live ASR | `SpeechTranscriber` if `isAvailable`; else `DictationTranscriber` / on-device SF | Prefer SpeechTranscriber |
| SpeechDetector module | **Off.** Scoring uses `audioTimeRange` + energy VAD | Same |
| Dual-locale transcriber | Batch **per turn** only, never 15 min dual live | Same |
| WhisperKit LID | multilingual `tiny` only; encoder CPU+GPU; decoder CPU; prewarm; ≥2.0 s speech | Same. No `base` mid-session |
| Acoustic filler Core ML | CPU/GPU, **never ANE** while EN ASR is live | Same |
| Foundation Models | Absent. Crisis = keywords. Report = templates | Optional classify only. No grammar line in v1 |

**ANE:** at most one live ANE client = EN SpeechAnalyzer. **Critical path before `response.create`:** keywords (+ FM). While live nudges are OFF, Uhm + LID run **after** the reply, for the report. 300 ms p95 is a **measured ship gate** for turning live nudges on, not a v1 constant. Thermal `.serious` / `insufficientResources` / jetsam → drop filler/LID, keep S2S.

**Code-switch (when live enabled):** ≥**2.0 s** speech. Softmax Whisper `langProbs` first (they are logprobs). If fewer than 3 language keys → `uncertain`. Dual-locale 0.25/0.65/0.45 cuts are **eval starting points**, not physics. Cue never names the language. **Ship gate:** precision ≥ 0.90 on accented-English-only turns.

**Fillers:** acoustic only; live pattern = filler vs not (`uh`/`um`/`hmm`; drop `and`/`other`). ≥80 ms, softmax ≥0.75. **One rule:** ≥**8** events per minute of phonation over rolling **60 s of phonation**, spanning ≥2 user turns. Prefer pre-AEC PCM. License + L2 soak before live.

**Hesitation / pause:** pauses ≥250 ms, report **duration** only. Location (mid-clause vs between) is **not v1** — no clause segmenter.

**SpeechAnalyzer hard fail:** S2S continues, `degraded=true`, **no** live cues, **no** OpenAI input transcription fallback (privacy). Partial report with a “limited analysis” line.

**Eval (blocking for turning live nudges on):** ≥12 speakers, ≥3 L1s, near-field, process-and-delete after annotation. Same soak required before the **report** claims a filler “pattern.” Do not ship live detectors on LibriSpeech numbers.

### Crisis, injection, SB 243 (engineering contracts)

**Not legal advice.** Architecture is locked. **Ship is blocked** on website protocol + counsel 988/22604 wording. Keyword+FM is **not** claimed as “evidence-based.” FTC inquiry, EU AI Act manipulative-design, relationship-rupture, and telemetry-disclosure stay **open** (product/legal, not this file’s v1 control plane).

On every finalized user turn, **before** `response.create`:

1. Keyword list (always). Hit → crisis. **Fail closed.**
2. FM classify if present. Yes → crisis. **FM timeout (400 ms) → fail open** (allow reply). Keywords still catch the obvious cases. The persona does not *speak* crisis either way — canned 988 owns that path. What fail-open accepts: paraphrases keywords miss, and FM-cold-start timeouts.
3. Therapy/override phrases (“ignore instructions”, “you are my therapist”, “pretend you are human”). Hit → **do not** `response.create`. Canned: rehearsal partner, not a therapist. Offer **Back to practice**; hang up if they persist. Do not stay in-role.
4. **Output side:** if assistant transcript hits SI keywords → `onCrisis` (SB 243 is content **to** the user). Requires an output transcript without enabling `audio.input.transcription`. If we cannot get output text with input transcription null, this abort is **not available** — do not pretend it is; residual.
5. No on-device text after **2 s**: **still allow S2S**; skip scoring cues; do not 988 on empty. Distinct from cough/empty (no `response.create`).

**`onCrisis`:** cancel in-flight response, **close WebRTC**, play canned **call or text 988 / chat 988lifeline.org** (audio + matching full screen), `endReason = crisis_referral`, increment **anonymous** backend `crisis_referral_events` (no user id, no transcript). Persona never speaks. **Non-US:** same 988 screen plus “If you are not in the US, use your local emergency number.” Counsel owns IASP/geo copy; v1 does not geo-route a different hotline.

**omni-moderation:** flag default **OFF**. Counsel may turn on; if on, fail closed on HTTP timeout >300 ms.

**Spoken “I’m 16” / “I’m a minor”:** no `response.create`; end; persist `possible_minor_flag` (boolean + date, not the utterance); do not mint again until review.

### Security and mint

- Backend mint only, authenticated account. Org key never on device.
- Secret TTL **120 s** (create-session window only — the **call continues** after expiry, up to OpenAI’s 60 min max). OpenAI will mint **multiple** sessions per secret; **our** 1-concurrent lock is the real one-session rule. `tracing: null`. `audio.input.transcription: null`. Mint immediately before SDP POST, not at countdown start. Discard `ek_` after first `/v1/realtime/calls` 2xx.
- Safety identifier: `HMAC-SHA256(server_pepper, account_uuid)` hex. Never log it next to account id. If OpenAI blocks it: generic unavailable; freeze mint; do not issue a new hash.
- Pin mini + empty tools on the mint. If client `session.update` drifts model/tools/tracing/instruction prefix → hang up (`config_drift`).
- Rate limits: 1 concurrent session / account; 3 mints / 10 min; 20 successful starts / **calendar** month (account timezone, **server-enforced**).
- **ZDR / Modified Abuse Monitoring:** required for any copy that says we don’t keep the conversation. If not approved by TestFlight: consent must say voice is streamed to OpenAI and they may keep **safety logs up to 30 days**; we do not receive the audio.
- **WOPRA / BIPA:** Washington biometric + Illinois BIPA stay in counsel copy. Process-and-delete + no speaker embeddings is the engineering contract; counsel decides whether voice-to-OpenAI needs a separate biometric consent screen in those states.
- **Never log:** PCM, ASR text, partner transcript, stance card, filler spans, crisis words. Allow: mint metadata, duration, hang-up enum, crisis **boolean**, billed seconds.
- Do not reuse Reading `SessionDiagnostics` JSONL for Conversation.
- Rewrite `NSMicrophoneUsageDescription`: live AI partner, stream to OpenAI, on-device scoring, not kept by us. In-app 5.1.2 permission **before** first mint.
- v1: **no** milestone snippets, **no** speaker embeddings, **no** diarization.

### Quality spike (ship gate, not a build gate)

Same iOS WebRTC build; SKU is the only variable. n ≥ 8 L2 speakers or 20 scripted 10–15 min dialogues.

Pass mini as default iff vs flagship on the same prompt: cue-fold ≥80% for `open` and `wrap_warn` (**human raters**, not regex); leakage (timer/system/cue) ≤5%; ≥1 real disagreement per session when the user opposes the stance; mid-clause cutoff ≤1 / 15 min; zero `function_call` items; after turn 3, `cached_input_tokens / input_tokens ≥ 0.5` on a 15 min script (else cue instructions are busting the cache). **Barge-in false-positives are monitor-only**, not a ship gate (`interrupt_response: true` has no cough filter).

Fail → mini stays internal; do not ship as the $20/mo mouth. Flagship never unlimited.

### Success metrics (log now; chips still not v1)

Activation = first **full** report. Habit = conversations/week (not daily). Early-exit % in first 2 min. Report opened. Internal: COGS $/completed session, crisis-abort rate, reconnect-fail rate, thin-report %, reach-wrap_warn % (**log only** — a 10-minute intentional Stop is allowed and must not be treated as failure). **Do not optimize** filler-down, WPM-up, grammar count, streaks, or reach-wrap_warn.

### Explicitly rejected from the panel

- WebSocket audio fallback in v1
- Silent new-Realtime resume with a summary
- 3-minute pause TTL (10 min kept; 30 s background hang-up **also rejected**)
- FM-timeout = crisis
- OpenAI input transcription as SpeechAnalyzer fallback
- Live code-switch/filler on day one without precision gates
- Mid-talk paywall
- Visible stance card / topic picker / Change Topic
- `interrupt_response: false` as wrap_close insurance (does not hold on WebRTC)
- SpeechDetector as the turn-boundary / pause clock
- Cue-only `response.create.instructions` (wipes persona)
- Minting the secret at countdown start (ICE + 60 s TTL race)

---

## Locked after Pass 2 (2026-09-21)

Second panel, **fresh context windows**, on the updated spec (not the first draft). Personas: staff engineer, PM, on-device STT, conversational voice, security/privacy, QA. All **YELLOW** again: stack still right; remaining holes were API mismatches, audio-route UX, and untestable races — not a new architecture.

Conflicts resolved (not averaged):

| Topic | Lock |
|---|---|
| SpeechDetector | **Off.** Apple’s module does not give the pause timestamps this spec assumed. Energy VAD + `audioTimeRange`. |
| iPhone 11 EN ASR | `SpeechTranscriber` if `isAvailable`; else **DictationTranscriber** / on-device SFSpeech. |
| Cue instructions | **Replace**, not append. Always `frozen_persona_prefix + stance + cue`. |
| wrap_close | Mute → `turn_detection: null` → wait `session.updated` → clear buffers → `response.create` → hang up. |
| Secret TTL | **120 s**, mint immediately before SDP. Call continues after expiry. Our 1-concurrent lock is the one-session rule. |
| Budget month | **Calendar** month, account TZ, **server-enforced**. Unused do not roll. |
| Headphones | Unplug = pause. Volume 0 ≠ pause. `defaultToSpeaker: true`. |
| Countdown | Send-muted; mint after 0. |
| Live LID / filler | Machinery ships **OFF**. Run **async after** `response.create` until live nudges turn on. |
| Background silence | **Same 1.5 min auto-pause** as foreground. No 30 s hang-up. |
| Report v1 | Time, turns, slips/`uncertain`, filled pauses, pace (raw), pause **time**. No location, no PMI/grammar. |
| Cue budget | Counts **heard** asides. Ignore ≠ consume. |
| FM timeout | **Fail open** (allow reply). Keywords still fail closed. |
| SB 243 | Architecture locked. **Ship-blocked** on website protocol + counsel copy. |
| 300 ms extra work | **Measured ship gate** for turning live nudges on, not a v1 constant. |
| Barge-in FP | **Monitor-only**, not a mini ship gate. |
| WebSocket fallback | **No** in v1. |
| Server-SDP rewrite | **Not required** for v1; residual if NAT fails. |
| Apple finalize | Wait up to **2 s**; S2S does not wait. |
| Filler live rule | One rule: ≥**8** / min of **phonation** over 60 s phonation, ≥2 turns. |
| Ghost turn | OpenAI `speech_started` with no stop for **8 s**. |
| PCM | Bounded ring. Do not reuse Reading `PCMStore`. |

### Session state machine (v1)

`idle → countdown → connecting → talking ⇄ paused → wrapping → report | crisis | dropped`

- From `talking`: pause, wrap_warn (still talking), wrap_close, crisis, drop, user Stop.
- From `paused`: resume → talking; 10 min TTL → report (no spoken close); unplug already in paused. Background silence auto-pauses into this state at 1.5 min, same as foreground.
- `wrapping` is send-muted, VAD off. No new user turns.
- `crisis` and `dropped` never enter `wrapping`.
- `report` is terminal for that start. Try-again from drop before report does not consume a second budget slot.

### Residuals (named, not averaged)

- OpenAI **ZDR / Modified Abuse Monitoring** approval before any “we don’t keep this” copy.
- Counsel: 988 / 22604 / website protocol / WOPRA / BIPA / non-US crisis line — **ship blockers**, not optional residuals.
- Quality spike is a **ship** gate, not a **build** gate. iPhone 11 15-min thermal soak is also a ship gate.
- Write **20 `open` questions** before implementation.
- Server-SDP rewrite only if TestFlight NAT fails.
- Live `code_switch` / `filler_ok` remain off until eval precision gates.
- Uhm-class Core ML license + L2 soak before live fillers **and** before report “pattern” copy.
- Output-side SI abort if we cannot get assistant text with input transcription null.
- Background-paused Realtime teardown vs keep-alive.
- Dual-locale code-switch: unused in v1 unless we collect L1.

**Verdict:** **GO to implementation plan if you sign these locks.** Do not start coding until the product-shape file and this file agree — they should, as of this pass.

---

## Explicitly later

Explain It Another Way, progress chips, L1 taper, connected-speech drills inside the chat, calibrated partner slang, collocation/grammar/register report lines, hesitation location, vocal variety / IC / coherence UI, model-called tools, Hume affect scores as telemetry, daily pushes, AI-initiated sessions.
