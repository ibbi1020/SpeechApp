# Orator design system

Source of truth for type: `ios/App/Design/SpeechType.swift`.

Sizes below are what you see at the **Large** Dynamic Type setting. Larger and smaller text settings scale from those sizes.

## Typography

### Fonts

Three faces. Headings use the bundled serif. Everything else uses SF Pro, the iOS system font.

| Face | Source | Weight | Roles |
| --- | --- | --- | --- |
| Instrument Serif | `font/InstrumentSerif-Regular.ttf` | Regular (400) | h1, h2, h3, h4 |
| SF Pro | System | Regular (400) | body, subtext |
| SF Pro | System | Semibold (600) | label |

Instrument Serif is the only file we ship.

- Family name: Instrument Serif
- PostScript name: `InstrumentSerif-Regular`
- Registered in `UIAppFonts` (`ios/App/Info.plist` and `ios/project.yml`)
- One cut only. Headings do not switch to a bold serif.

SF Pro is not bundled. SwiftUI’s system font draws it.

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
| h1 | 51 | Instrument Serif Regular | −0.025 em (−1.28pt) | 1.10 (56.1pt) | Large Title |
| h2 | 38 | Instrument Serif Regular | −0.020 em (−0.76pt) | 1.12 (42.6pt) | Large Title |
| h3 | 28 | Instrument Serif Regular | −0.015 em (−0.42pt) | 1.15 (32.2pt) | Title |
| h4 | 21 | Instrument Serif Regular | −0.010 em (−0.21pt) | 1.20 (25.2pt) | Title 3 |
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

Not defined yet.

## Iconography

Not defined yet.

## Components

Not defined yet.
