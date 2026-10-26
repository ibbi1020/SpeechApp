# Home — dither identity, draft 1

> Superseded for implementation. The dither plates and the composition rules in this draft were
> dropped. The entry flow that replaced them is `docs/scoping-entry-ritual.md` §8. This file stays
> as the record of the draft.

Draft run. The goal is to find out whether a dot-dither visual identity lands, not to ship a final
look. Everything here is replaceable.

## Why the home screen changes

Home today is three glass rows: Read a passage / Start a conversation / Talk about something. That
asks the user to compare three things before they have committed to doing anything at all. The
decision is cheapest to make *after* commitment and most expensive before it, so the order is wrong.

Reference: FocusFlight (iOS). Its ritual is home → drag a ruler to pick a duration → book → pick a
seat → boarding pass → fly. The extra steps work because none of them is a menu. Each one is a
continuous gesture that produces an artifact, and by the end the user has authored a plan with their
name on it. Its home screen is one object and one verb, and the question of *what* comes after the
commitment to *something*.

## Who this is for

Users are not confident in their English and are improving themselves discreetly. That rules out
imagery that implies an audience or a performance — an auditorium, rows of seats, anyone watching.
The visuals must inspire confidence without demanding a performance.

## Visual language

Monochrome two-tone dot dither on black. Classical Greek marble figures, lit from one side, floating
in empty space with no architecture, edges dissolving into drifting dots. One figure per screen,
chosen to represent that exercise rather than a place.

Composition rule for every plate: the top-left corner and the bottom third stay empty black. The
figure lives in the middle band. Text and controls sit in the empty regions, never over the figure.

Typography is unchanged — `design.md` stands. Headings are Instrument Serif, everything else SF Pro.

Assets are bundled images for this draft. If the effect lands, a Metal dither shader replaces them
and the treatment becomes available to live session visuals too.

## Home

Full-bleed figure on black: a standing orator at rest, composed, not speaking.

| Region | Content |
| --- | --- |
| Top left | The state line at h1. No app name. |
| Top right | The existing recordings button, unchanged. |
| Middle | The figure, bleeding past the safe area. |
| Bottom | One white capsule: `Begin`, a plain tap. |

State line is `Find your voice` before the user has ever started a session, `Speak with poise` after.
Two or three words, meant to encourage rather than count a streak.

An earlier draft made `Begin` a press and hold that resolved the figure from coarse dots to fine. It
was removed: one tap is enough ceremony here.

## Format screens

`Begin` cross-fades into one fixed screen that shows a single exercise at a time. These replace the
three rows; they are not cards.

| Order | Heading | Line | Figure |
| --- | --- | --- | --- |
| 1 | Reading | Read a passage aloud. Hear every sound. | Seated scholar reading from a scroll |
| 2 | Monologue | One topic, three takes, a minute longer each. | Lone orator, arm extended, mid-word |
| 3 | Conversation | Fifteen minutes with a partner. No script. | Two figures in dialogue, as equals |

The line is capped at 60% of the screen width so it never runs over the figure.

A horizontal swipe changes the exercise in place. The figure cross-fades and the copy slides a short
way in the swipe direction; the back control, the three-dot index and the start button stay put. The
swipe resists at the first and last exercise. VoiceOver changes exercise with the adjustable action. Conversation shows
its monthly allowance as a quiet label (`3 of 20 this month`) instead of appearing disabled, and when
the month is spent the button says so in words.

Starting from a format screen enters the existing flows untouched: Reading goes to the passage
library, Monologue to its planning page, Conversation straight into the session.

## Structure

`AppModel.Route` gains `.formats`. Home and the chooser are one surface in two states inside
`EntryFlowView`, which also owns the existing navigation destinations. That keeps every current push
path — library → reading → report, conversation, monologue, recordings — exactly as it is.

### Motion

Timings are taken from FocusFlight, measured frame by frame off a screen recording. Its screen changes
land in about a quarter second, and its primary button never leaves the screen — `Start Journey`
becomes `Book My Flight` in place while the map and copy change around it.

So: every swap uses `SpeechMotion.swap`, a no-bounce spring of 0.25s. Going from home to the chooser
cross-fades the figure and the copy, and the white button stays where it is and changes its label.
Under Reduce Motion everything becomes a 0.2s fade.

Two pieces of logic move into SpeechAppKit so they can be tested without a view:

- `EntryGreeting` — the state line from whether the user has begun a session before.
- `PracticeFormat` — the three formats, their copy, and what the start control says given the
  conversation budget.

`AppModel` records that the user has begun a session when a session actually starts, so the greeting
tells the truth.

## Out of scope

Everything inside a session. The passage library, the monologue planning page, the countdowns, the
reports and the recordings library are untouched.
