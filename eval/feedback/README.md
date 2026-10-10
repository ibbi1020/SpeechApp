# Feedback eval

Test the Monologue feedback (pause, filler, and restart markers) without recording in the app.

When a marker is wrong, the fault is in one of three places. Each is tested separately:

| Layer | What can go wrong | How it is tested |
|---|---|---|
| Grok transcript | It did not hear the "um", merged a repeat, or blurred the silence | Audio clips → Grok → saved words |
| Marker rules | 1.5 s rule, filler window, cap, spacing picked the wrong moments | `rules.json`, no audio, runs in `swift test` |
| Wording | The note is not what a coach would say | Read the "Shown" notes in the report |

## Quick start (from the repo root)

    eval/feedback/run.sh rules        # marker rules only, instant
    eval/feedback/run.sh generate     # make spoken clips from clips.json (Mac voice)
    eval/feedback/run.sh run          # send new clips to Grok, then score

`run` needs the local server (`server/ensure-mint.sh`, with `XAI_API_KEY` in `server/.env`),
the same relay the app uses. Grok answers are cached in `<clip>.grok.json`; add `--refresh` to resend.

The report is written to `eval/feedback/out/report.md`. For every clip it shows what Grok heard
(fillers in *italics*, gaps of 0.7 s or more written as `[1.2 s]`), the markers shown, and each
problem. For each miss it says whether the **transcript** or the **rules** are to blame.

## How scoring works

- A marker matches a label when the kind matches and the start times are within 0.5 s
  (or the two spans overlap). This is the event-based scoring used in sound event detection
  ([sed_eval](https://tut-arg.github.io/sed_eval/sound_event.html)).
- **Detected** (before the cap): did the rules find every labeled moment?
- **Shown** (after the cap and spacing): are the markers on the scrubber the ones a person would pick?
- Problems are listed as: not detected, detected but not expected, wrong kind,
  detected but hidden by the cap, shown but should not be.

## Markers per exercise

| Exercise | Markers | Why |
|---|---|---|
| Monologue | long pause, filler cluster, restart | 4/3/2 trains utterance fluency |
| Reading | skipped word, swapped word (ranked by functional load; low-load swaps dropped), pause before a word mid-phrase (not at a comma or full stop) | The passage is known, so mistakes are about the words (Munro & Derwing 2006). Mid-clause pauses point to word-level trouble |
| Conversation | long pause, filler cluster, and restart inside an answer; slow start (2 s+ before answering) | Answer timing is the interactive skill. L2 beginners average ~1 s, listeners read meaning into gaps from ~0.7 s (Kendrick & Torreira 2015) |

Pause notes say where the pause fell: after a word like "the" or "to" it is mid-sentence ("what word
were you looking for?"); after a full stop followed by a word like "So" it is between sentences
("were you planning your next point?"). Grok adds full stops at long pauses, so anything less clear
keeps the open question.

Set `"exercise": "reading"` with `"passage"`, or `"exercise": "conversation"`, on a rule case or clip.

Reading's live stream sends the passage words to Grok as hints. With hints Grok writes the passage
word even when another was said ("ship" for "sheep"), so the app runs a second, unhinted stream
for feedback. The CLI matches that by default; `--hints` reproduces the live stream instead.

## Script format

One line says what is spoken and what should be flagged. Used by `rules.json` and `clips.json`.

    Last weekend I went to the [2.5 pause] market <fillers> umm, with my, uhh, </> sister

- `[2.5]` is 2.5 s of silence. Add `pause`, `pause maybe`, or `not pause`.
- `<fillers> … </>` and `<restart> … </>` wrap words that should be flagged.
  `<restart maybe>`: the cap may hide it. `<not restart>`: must not be flagged.
- Reading: `[0.2 skip]` where a passage word was left out, `<swap> sheep </>` around a wrong word.
- Conversation: `{2.0 What do you do?}` is the partner talking for 2 s (silent on the user's mic),
  then `[3.0 slowstart]` for the wait before answering.
- `maybe` matters when a take has more moments than its marker cap (3 per minute, at most 7).
- In `rules.json` a silence is the gap between two words as Grok reports it. Grok word edges add
  about 0.2 s, so a pause marker needs a 1.7 s word gap (a real 1.5 s silence). In `clips.json` a
  silence is real audio, so `[1.5]` there is a true 1.5 s pause.

## Files

| Path | What it is |
|---|---|
| `rules.json` | Marker-rule cases. Also run by `swift test` (`FeedbackRuleCaseTests`). Add `knownIssue` to record a gap without failing the build. |
| `clips.json` | Scripts for generated clips (`say` voices: Samantha, Daniel, Karen, …). |
| `clips/generated/` | Generated `.wav` + `.labels.json` + cached `.grok.json`. Git-ignored; rebuild with `generate`. |
| `clips/real/` | Your own recordings with Audacity labels. Git-ignored. See its README. |
| `out/report.md` | Latest report. Git-ignored. |

## Known limits of generated clips

- The Mac voice says "um"/"uh" unnaturally. Spell them `umm,` / `uhh,` with commas, or Grok hears "I'm".
  Karen says "uhh" as "ooh". Real recordings are still the best test for fillers.
- Pauses and restarts from `say` are reliable.
- Reading without hints: Grok sometimes mishears a word boundary ("A light rain" → "Allied rain"),
  which shows as a false swap (`reading-skip-phrase`). The marker asks "what did you say?", so the
  reader hears that they read it right.

## Later: public datasets

Real learner speech with labels, if generated and own clips are not enough:

- [ICNALE Spoken Monologues](https://language.sakura.ne.jp/icnale/modules.html): 60 s learner monologues,
  each topic spoken twice (close to 4/3/2). Needs registration; you add labels yourself.
- [PodcastFillers](https://podcastfillers.github.io/): timed "uh"/"um" labels. Research-only license.
- [SEP-28k](https://github.com/apple/ml-stuttering-events-dataset/): 3 s clips labeled for repeats and fillers.

Drop their audio into `clips/` with a `.labels.json` or Audacity `.txt` and `run` scores them the same way.
