# Home — dither identity, draft 1

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
| Top left | `ORATOR` in the label role, uppercase. Under it the state line at h1. |
| Top right | The existing recordings button, unchanged. |
| Middle | The figure, bleeding past the safe area. |
| Bottom | One capsule: `Begin`. |

State line is `First words` before the user has ever started a session, `Once more` after. Two words,
about craft rather than a streak.

### The one interaction

`Begin` is a press and hold of 1.25s. It is the only ceremony on the screen — the slow-down has to be
real, and it has to be one gesture rather than a maze.

While held:

- A fill sweeps across the capsule so the remaining time is visible.
- Haptics tick on press and land a solid impact on completion.
- The figure's dither resolves from coarse dots to fine, so the statue comes into focus under the
  thumb.

Releasing early springs everything back, critically damped. Under Reduce Motion the resolve becomes a
plain cross-fade and the spring becomes a short ease.

Holding is what makes the user stop for a beat before speaking, and the dither resolving points the
app's own visual promise at the person using it.

## Format screens

The hold completes and home cross-fades into a horizontal pager of three full screens. These replace
the three rows; they are not cards.

| Order | Heading | Line | Figure |
| --- | --- | --- | --- |
| 1 | Reading | Read a passage aloud. Hear every sound. | Seated scholar reading from a scroll |
| 2 | Monologue | One topic, three takes, less time each. | Lone orator, arm extended, mid-word |
| 3 | Conversation | Fifteen minutes with a partner. No script. | Two figures in dialogue, as equals |

The line is capped at 60% of the screen width so it never runs over the figure.

Each screen carries a back control to home, a three-dot index, and a start button. Conversation shows
its monthly allowance as a quiet label (`3 of 20 this month`) instead of appearing disabled, and when
the month is spent the button says so in words.

Starting from a format screen enters the existing flows untouched: Reading goes to the passage
library, Monologue to its planning page, Conversation straight into the session.

## Structure

`AppModel.Route` gains `.formats`. Home and the format pager are both pre-session surfaces, so they
live inside one `EntryFlowView` that owns the existing navigation destinations. That keeps every
current push path — library → reading → report, conversation, monologue, recordings — exactly as it
is, with no new nesting.

Three pieces of logic move into SpeechAppKit so they can be tested without a view:

- `EntryGreeting` — the state line from whether the user has begun a session before.
- `HoldToBegin` — elapsed time to a 0…1 fraction and a completion flag.
- `PracticeFormat` — the three formats, their copy, and what the start control says given the
  conversation budget.

`AppModel` records that the user has begun a session when a session actually starts, so the greeting
tells the truth.

## Out of scope

Everything inside a session. The passage library, the monologue planning page, the countdowns, the
reports and the recordings library are untouched.
