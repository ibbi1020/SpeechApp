# Your own recordings

Audio in this folder is git-ignored so your voice never leaves your Mac.

## Record (about 10 clips, 30–60 s each)

Use QuickTime (File → New Audio Recording) or Voice Memos, and export as `.m4a` or `.wav`.
A phone take from the app works too (`take-1.m4a` from the app's Recordings folder).

Cover the moments you care about. Do each on purpose:

1. A long freeze while looking for a word (3 s or more).
2. Two "um"s close together.
3. A restart: "I went, I went to the…"
4. A normal 1 s thinking pause. This must **not** be flagged.
5. A clean take with no trouble.
6. "very very good" or "that that". This must **not** be a restart.

## Label in Audacity

1. Open the clip. Select the moment by dragging on the waveform.
2. Edit → Labels → Add Label at Selection (⌘B). Type one of:
   - `pause`, `fillers`, or `restart`: it should be shown as a marker.
   - Add ` maybe` at the end (`fillers maybe`): it should be detected, but the cap may hide it.
   - Start with `not ` (`not pause`): it must not be flagged.
3. File → Export → Export Labels… and save next to the clip with the same name:
   `my-clip.m4a` → `my-clip.txt`.

You can also write `my-clip.labels.json` by hand (same format as the generated clips).

Reading clips: label `skip` or `swap`, and save the passage text as `my-clip.passage.txt`
next to the clip so the rules know what should have been read.

## Run

From the repo root:

    eval/feedback/run.sh run --only my-clip

Grok's answer is saved as `my-clip.grok.json`, so changing marker rules and re-scoring
(`eval/feedback/run.sh score`) is free and instant.
