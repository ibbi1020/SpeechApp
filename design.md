# Orator design system

Source of truth for type: `ios/App/Design/SpeechType.swift`.

Sizes below are what you see at the **Large** Dynamic Type setting. Larger and smaller text settings scale from those sizes.

## Typography

### Fonts

Two jobs. Headings and chrome use SF Pro. A prompt, a subtitle, a passage, or a transcript uses New York, through `SpeechReading`.

Reading text is 22pt at the Large text setting. Words sit 8pt apart. Lines sit 14pt apart. The spoken word is semibold and underlined. The size and the gaps scale with the Title 2 text style.

| Face | Source | Weight | Roles |
| --- | --- | --- | --- |
| SF Pro | System | Semibold (600) | h1, h2, h3, h4, label |
| SF Pro | System | Regular (400) | body, subtext |
| New York | System serif | Regular (400), Semibold on the spoken word | prompts, subtitles, passages, transcripts |

SF Pro and New York are not bundled. SwiftUI’s system font draws them.

### Scale

Body is **16pt**. The four headings step up from body by a perfect fourth: each step is 4/3 the size of the one below, then rounded to a whole point.

```
16 × 4/3                         = 21   h4
16 × 4/3 × 4/3                   = 28   h3
16 × 4/3 × 4/3 × 4/3             = 38   h2
16 × 4/3 × 4/3 × 4/3 × 4/3       = 51   h1
```

Subtext and label do not use that ratio. One more step down from 16 would already be 12pt, and that is as small as a label should go. So subtext is 14 and label is 12.

### Roles

Tracking is extra space between letters, as a fraction of the point size. Negative is tighter. It scales with the text size.

Line height is the target height of one line, as a multiple of the point size. The point values are that multiple at Large.

| Role | Size | Face | Tracking | Line height | Dynamic Type bucket |
| --- | --- | --- | --- | --- | --- |
| h1 | 51 | SF Pro Semibold | −0.025 em (−1.28pt) | 1.10 (56.1pt) | Large Title |
| h2 | 38 | SF Pro Semibold | −0.020 em (−0.76pt) | 1.12 (42.6pt) | Large Title |
| h3 | 28 | SF Pro Semibold | −0.015 em (−0.42pt) | 1.15 (32.2pt) | Title |
| h4 | 21 | SF Pro Semibold | −0.010 em (−0.21pt) | 1.20 (25.2pt) | Title 3 |
| body | 16 | SF Pro Regular | 0 | 1.45 (23.2pt) | Body |
| subtext | 14 | SF Pro Regular | 0 | 1.40 (19.6pt) | Subheadline |
| label | 12 | SF Pro Semibold | +0.060 em (+0.72pt) | 1.25 (15pt) | Caption |

Tracking tightens as the heading gets larger. Body and subtext stay at 0. Labels open up so small semibold text stays readable, including when the caller sets them in capitals.

Line spacing is the gap added on top of the font’s own line height so the result matches the multiple above. That added gap is never negative.

### Dynamic Type

Each role’s size is the Large setting. The app scales it with the system text-size control, using the bucket in the table. Tracking and line height stay in proportion because both are fractions of the current size.

### Page titles

A screen title uses the navigation bar, not a text view in the page.

| Bar style | Role |
| --- | --- |
| Large title | h1 |
| Inline title | h4 |

The title string stays on the screen as its navigation title, so the back button still has a name and the title moves with the screen. The bar keeps its own material. Only the h1 and h4 fonts, and their tracking, are written onto it.

### How to apply it

```swift
Text("Read this aloud")
    .speechReading()

Text("The passage")
    .speechType(.h2)

Text("Details")
    .speechType(.label)

.speechPageTitle("Orator", large: true)   // h1
.speechPageTitle("Your reading")          // h4, inline
```

Section labels that should read as small caps set `.textCase(.uppercase)` at the call site. The label role does not do that by itself.

### Where the roles are used

| Role | Use |
| --- | --- |
| h1 | Large page titles (Home, Passages). Crisis screen heading. |
| h2 | Passage title on the reading screen and on the reading report. |
| h3 | The word “minutes” beside a stage duration. |
| h4 | Inline page titles (Conversation, Your reading, Your talk, Your conversation). |
| body | Stop-modal title. |
| subtext | Defined. No screen uses it yet. |
| label | Report section labels, including Diagnostics. Call sites set them in capitals. |

## Color

Not defined yet.

## Spacing

Not defined yet.

## Materials

Not defined yet.

## Motion

Source of truth: `SpeechAppKit/Design/BlurMotion.swift` for the numbers, `ios/App/Design/SpeechBlur.swift` for the SwiftUI vocabulary.

### Blur is the transition

Nothing slides and nothing scales between states. What is leaving blurs out of focus; what is arriving resolves into it. This is measured off FocusFlight, where every screen change, label change and modal works this way.

Blur does a job that opacity alone cannot: a cross-fade of two sharp layers reads as two things overlaid, and the eye tries to read both. Blurring the outgoing layer removes it as something readable before it is gone, so only one thing is ever legible.

### The three moves

| Move | Radius | Duration | Use for |
| --- | --- | --- | --- |
| Dissolve | 20pt, or 0.4 × type size for text | 280ms, ease-in-out | One surface or line of copy replaced by another |
| Burst | 30pt | 120ms, ease-in-out | A control leaving with nothing taking its place |
| Backdrop | 28pt + 55% black scrim | 300ms, ease-in-out | Content pushed behind a modal |

Picking the right move matters more than the numbers.

- **Dissolve** is the default. Both ends blur: out over the first 45% of the duration, in over the remaining 55%. Measured end to end at 290ms on the reference; ours lands at ~250ms.
- **Burst** is harder and faster because nothing replaces the element, so the eye should release it rather than track it out. The reference's confirm button hit 18pt within a single frame and was down to a sixth of its opacity by 120ms.
- **Backdrop** holds for as long as the modal is up — it is a state, not a transition. The scrim is required: a Gaussian blur preserves mean brightness, so blur alone does not push anything back.

### Text blur scales with type size

`BlurMotion.textRadius(forSize:)` returns four tenths of the point size, with a 6pt floor. A fixed radius lands wrong in both directions: 20pt erases a caption into a grey bar, and 6pt leaves a 51pt headline perfectly readable. The reference's 51pt header dissolves through about 20pt, which is where four tenths comes from.

### Changing text in place

`BlurDissolve` shows one value at a time. Cross-fading two strings in a `ZStack` sizes the container to the taller one, so a two-line heading replacing a one-line heading leaves a gap below it for the whole transition — and the point of the move is that nothing shifts. So the old value blurs out, the swap happens under the blur unanimated, and the new value resolves in.

### Curves

| Token | Curve | Use |
| --- | --- | --- |
| `SpeechBlur.motion` | ease-in-out 280ms | Anything driving a blur dissolve |
| `SpeechMotion.settle` | spring, response 0.35, damping 1.0 | Layout settling, not blur |
| `SpeechMotion.press` | spring, response 0.22, damping 1.0 | Press and highlight |
| `SpeechMotion.scroll` | ease-in-out 450ms | Passage auto-scroll |

Blur never gets a spring. Overshoot on a blur radius reads as a lens hunting for focus.

### Reduce Motion and Reduce Transparency

Reduce Motion drops the blur ramp entirely and leaves a 200ms fade — a blur ramp is exactly the kind of motion that setting exists to avoid. `BlurVeil` and `BlurPhase.dissolved(radius:reduceMotion:)` both handle this, so callers do not each have to remember.

Reduce Transparency drops the backdrop blur and raises its scrim to 72%, since the scrim then carries the whole separation on its own.

### What stays sharp

Numbers use `.contentTransition(.numericText())`, not blur. Digits rolling is the system's own idiom for a value counting, and blurring them loses that.

The reading countdown fog is deliberately softer than a backdrop at 7pt (`SpeechCountdown.fogBlurRadius`). The passage behind it should stay present and shaped, just not readable, because that is the thing you are about to read.

## Iconography

Not defined yet.

## Components

Not defined yet.
