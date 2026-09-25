# Reading flow redesign

**Date:** 2026-09-20  
**Status:** Draft for review. Aurora is explicitly out of this pass.  
**App:** Orator, Reading (Format 1) prototype.

This spec captures the flow and chrome we locked in the companion. It is a presentable prototype, not a finished product. Implement with system text styles and native iOS controls so it can be shown to people without looking like a Settings menu or a letterpress costume.

Source for type: [Apple HIG Typography](https://developer.apple.com/design/human-interface-guidelines/typography), iOS Dynamic Type size **Large (default)**.

---

## 1. Goal

Open the app into a dedicated Reading home, pick a long passage, start with a 3-second ready beat, read in dark chrome, pause without wrecking the take, and end through a real confirmation, not a toast.

### In scope

- Drop the consent screen and the "on-device listening is ready" screen from launch.
- Passage library as home: editorial featured card plus a list of long passages only.
- Dark reading screen: back to Passages, serif passage, Start on the same surface.
- 3-2-1 countdown that warms the listener.
- Live status capsule, Pause, Stop, confirmation dialog.
- Pause semantics for the session timer and ASR input.
- HIG text styles throughout.

### Out of scope

- Aurora waveform design (reserved strip only).
- Report screen redesign (it should inherit dark chrome and paused-aware duration).
- Conversation / Monologue.
- Restoring short and medium passage variants in the picker.

---

## 2. Launch and routing

`AppModel.route` starts at `.library`. Remove `.consent` and `.availability` from the user-visible path.

Mic permission, speech authorization, asset download, and `prepareIfNeeded` still happen. They run when the user taps Start, during the countdown, not on their own screens.

If speech is unavailable or permission is denied, show an inline error on the reading screen (footnote, secondary or red) and keep Start enabled to retry. Do not invent a new onboarding page.

`RootView` keeps `NavigationStack`. Library is the root. Reading is pushed. Report stays a route after a confirmed stop.

---

## 3. Passage library (home)

### Catalog

The picker shows **one passage per story: the longest variant** (`.long` if it exists, else `.medium`). Short variants stay in the bundled JSON for later work but do not appear in the UI.

Featured card uses `NextPassagePicker` over that long-only list (today that is typically Harbor Morning). The featured passage is not duplicated in "More to read".

### Layout

Not a grouped `List` with chevrons. `ScrollView` on a black/graphite background.

1. Large Title **Passages** (text style `largeTitle`, bold).
2. Featured card (`Title 2` title, `Subheadline` excerpt truncated to two lines, `Footnote` duration, `Headline` Start).
3. Section **More to read**: rows of title (`Body`) and duration (`Subheadline`). Tap opens that passage. No length pills.

Start on the featured card opens that passage's reading screen. It does not start listening from the library.

Suggested toolbar action is gone. Choosing is the featured card plus the list.

---

## 4. Reading screen (idle)

Dark throughout (`Color(.systemBackground)` in a forced dark scheme, or explicit graphite). No cream paper, no `.ultraThinMaterial` dock that reads as a second theme.

- Navigation: system back **Passages**. No trailing Passages button.
- Reserved aurora strip at the top (existing view, no visual redesign in this pass).
- Title: New York / `.serif` at `title3` emphasized (20/25).
- Meta: `footnote`, duration only (e.g. "About 2 min").
- Passage: New York at `body` (17/22). Use `.font(.system(.body, design: .serif))` so Dynamic Type still applies. Do not bump point size to make it feel like a book.
- Bottom: full-width **Start** (`headline`, filled, same background as the page). Press scale 0.97, feedback on touch-down.

---

## 5. Countdown

Tap Start (after permissions if needed):

1. Stay on the same screen. Passage does not navigate away.
2. Replace Start with a 3-2-1 count (about 64 pt, SF, tabular). Caption **Get ready** as `footnote`.
3. During the three seconds, prepare the transcription engine (this is the warmup).
4. At 0, enter live listening. Count is not part of analyzed duration.
5. Back remains available. Leaving during countdown cancels start and does not create a report.
6. Reduced motion: cross-fade the digits. No scale bounce.

Do not feed ASR or PCM into the session clock until the count finishes.

---

## 6. Live chrome

| Element | Treatment |
|---|---|
| Status | Capsule, `footnote`, green dot when listening. Copy: **Listening**, **Take your time**, **Falling behind**. Replaces the caption and the stall toast. |
| Pause | Square secondary control, pause symbol. |
| Stop | Primary filled, destructive red, `headline`. |

The stall banner is gone. Silence maps onto the capsule. No "I'm ready" toast. Dismissing stall is pause/resume or just speaking again, using existing stall detector behavior without a separate bottom card.

---

## 7. Pause

Pause is in. A cough or a knock should not wreck the take.

### While paused

- Session object stays alive. Do not tear down the engine or audio session.
- Stop forwarding audio into the transcriber (do not call `handle(update:)` with new speech). Implementation: ignore chunks for ASR and skip `pcmStore.append` while paused.
- Mic may stay running so resume is instant. Energy UI should go idle (aurora later).
- Stall detector does not count pause as a stall event.
- Capsule: **Paused**. Pause control becomes play/resume.

### Analysis

`durationSeconds` and speech rate use **running time only**: sum of intervals from countdown-end (or resume) until pause or stop. Wall-clock including pause is not the report duration. PCM used for GOP must not include paused samples.

Resume continues from the same occupancy state. Do not reset the aligner.

---

## 8. Stop

Tap Stop presents a native `.confirmationDialog`:

- Title: **End this reading?**
- Message: **You can start this passage again from the report.**
- Destructive: **End Reading**
- Cancel: **Keep Going**

Not a toast. Not an immediate `session.stop()`.

**End Reading** runs the existing stop drain (mic off, finalize ASR, report). **Keep Going** dismisses and stays live (or paused, if they were paused).

While finishing, disable Pause/Stop, capsule **Finishing**, then navigate to the existing report.

---

## 9. Typography (implementation rule)

Use semantic text styles. Do not hardcode point sizes except the countdown display number.

| UI | Style | Large default |
|---|---|---|
| Library title | `largeTitle` | 34 / 41 |
| Featured title | `title2` | 22 / 28 |
| Featured excerpt | `subheadline` | 15 / 20, two lines max |
| Passage title | `title3` emphasized | 20 / 25 |
| Passage, rows, Start, Stop | `body` / `headline` | 17 / 22 |
| Meta, capsule, sheet copy | `footnote` | 13 / 18 |
| Sheet actions | system confirmation (Title 3 / 20) | native |
| Countdown digit | display | ~64 pt, not a text style |

System font (SF) for chrome. New York / `.serif` only for passage title and body. Support Dynamic Type and `accessibilityReduceMotion`.

---

## 10. Architecture

```
AppModel.route: library -> reading -> report
                     ^                 |
                     +-----------------+
```

- **AppModel:** drop consent/availability routes; `currentPassage`; long-only catalog helper or filter at the view.
- **PassageLibraryView:** editorial `ScrollView`; featured + rows.
- **ReadingSessionView:** phases in the view: `idle`, `countdown`, `live`, `paused`, `confirmingStop`, `finishing`. Session kit gains `pause()` / `resume()` and paused-aware duration.
- **ReadingSession:** `Phase` adds `paused` (and optionally `countdown` stays UI-only so the kit only starts after 3). Prefer UI-owned countdown, then `start()`, so tests for pause/duration stay in the kit.
- **LiveTranscriptionEngine:** unchanged public start/stop; session gates chunks while paused.

Countdown warmup: create the engine, `prepareIfNeeded`, request permissions, then `session.start` at 0 so the first spoken audio is after the beat.

---

## 11. Error handling

| Case | UI |
|---|---|
| Mic denied | Footnote on reading screen; Start retries |
| Speech denied | Same, plus Settings hint |
| Engine unavailable | Same |
| Asset download | Countdown / Starting state can show a short ProgressView; do not return to a dedicated availability page |
| Start throws | Error footnote; return to idle Start |

No empty catch. Failures stay visible.

---

## 12. Testing

Kit (Swift Testing), TDD for new behavior:

- Long-only catalog: each family contributes its longest passage; shorts absent.
- Pause: ASR/PCM not recorded during pause; duration equals running intervals; occupancy unchanged across pause.
- Stop confirmation is UI; kit `stop()` still drains as today.
- Existing aligner / session integration tests still pass.

UI: exercise library → reading → countdown → live → pause → resume → stop sheet → report. Verify back during idle and countdown. Cannot verify on-device ASR in this environment; call that out at implementation time.

---

## 13. Decisions already locked

1. App opens on the passage library.
2. Editorial home (featured + list), not Settings grouped lists.
3. Long passages only.
4. Featured excerpt is two lines.
5. Reading is dark graphite; Start shares that surface.
6. 3-second countdown on the same screen.
7. Status capsule, Pause in, Stop confirmation sheet.
8. HIG Large text styles; 390 pt iPhone as the type reference.
9. Aurora visual pass is later.
