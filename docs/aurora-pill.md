# Aurora pill — port this, don’t redesign it

Source of truth: `prototypes/mic-visualizer/index.html`.
The lab is approved. A Swift port matches these numbers. It does not reinterpret them.

This replaces `ios/App/Design/AuroraPresenceView.swift` (teal/indigo stroked ribbons). That view is the rejected look. Do not extend it, and do not substitute `MeshGradient`. MeshGradient cannot reproduce a hard capsule clip, a traveling sine, or per-crest screen-blended color. Draw the heightfield.

One component. Same drawing on Reading and Conversation. It lives in the bottom black chrome, between pause and stop, not as a band above the passage.

## What it is

A stadium (capsule) on `#050508`. Inside it, a filled horizon. `y` grows downward, so a **smaller** ridge value is a **taller** crest. `x` is 0 at the left lip and 1 at the right lip.

The silhouette is one filled path from the ridge down past the bottom of the pill. There is no stroke. Softness is a blur on that fill. The capsule edge stays hard: clip first, then draw.

Three modes, only one active:

| Mode | When | Shape |
|---|---|---|
| `listen` | User may be speaking. Energy is mic RMS. | Two soft crests. Each has its own slow clock, so one can sit low while the other is up. Shallow. A dim shelf keeps the floor from going hollow. |
| `connect` | Agent is connecting or thinking. No mic drive. | One sine. Two rounded humps, one shallow trough, traveling left to right at constant speed and constant amplitude. A child’s pond ripple. No second harmonic, no color accents, no extra highlight layer. |
| `speak` | Agent is talking. | Three narrower crests on fast independent clocks. They slide. Troughs between them are deep (the rest line sits low). Tall crests pick up color: magenta on the first, bottle green on the others. |

Listening must stay the slow two-crest field. Speaking must stay the fast three-crest field. Connecting must stay the single shallow sine. Do not share one parameter set across modes.

## View API

```swift
struct AuroraPill: View {
    var energy: Float   // 0...1. See Energy.
    var mode: Mode      // .listen | .connect | .speak
    var glass: Bool = true
    enum Mode { case listen, connect, speak }

    var body: some View {
        pillCanvas
            .frame(width: 132, height: 52)
            .glassEffect(glass ? .regular : .identity, in: .capsule)
    }
}
```

Frame it at **132×52 pt** in the chrome (the lab slot). The drawing is resolution-independent: all ridge math is in 0…1 of that box, then multiplied by width and height. Blur radii below are in **points**, then scaled by the same factor as the canvas.

Chrome, both formats: black bar, pause button, pill, stop button. Conversation status line:

- `speak` → “Speaking.”
- `connect` → “Connecting.”
- `listen` and energy > 0.28 → “Hearing you.”
- otherwise → “Listening.”

Accessibility label uses those same words. `accessibilityReduceMotion`: freeze time (`t` constant), draw one static frame of the current mode, keep a dim glow. Do not animate.

## Clock — two different `t`s

Let `t` be seconds from an arbitrary origin (`TimelineView(.animation)`, `date.timeIntervalSinceReferenceDate` is fine).

**Energy and the speak syllable formula use raw `t`.**
**The ridge uses a scaled copy:**

- `speak`: `tDraw = t * 0.9`
- `listen`: `tDraw = t * 0.5`
- `connect`: `tDraw = t` (do not slow it)

Pass `tDraw` into every `ridgeY` call, including the listen shelf (`tDraw + 1.3` is an extra phase on that same scaled clock). If you scale the syllable formula too, speaking will feel sluggish. If you forget to scale listen, the crests race.

## Energy

`e` is clamped to 0…1.

The app already has Reading `speechEnergy = min(1, rms / 0.06)` in `ReadingSession.handle(chunk:)`. **Feed that value in as the listen target.** Do not also apply the lab’s Web Audio mapping `(rms - 0.018) * 6.2`. That mapping exists only because the browser analyser is a different meter. Double-scaling will pin the pill at full height.

Smooth the target every frame. `dt` is frame delta in seconds, clamped to 0.05:

```
atkHz = speak ? (target > energy ? 7.5 : 3.4)
              : (target > energy ? 4.2 : 2.0)
energy += (target - energy) * (1 - exp(-atkHz * dt))
```

Targets:

- **listen:** mic `speechEnergy`. Floor at 0.1 when the mic is open and silent, matching the lab’s idle. If you have no level yet, use 0.1, not 0 — zero collapses the blue.
- **speak:** prefer the agent’s playback RMS, normalized the same way (`min(1, rms / 0.06)`), then smoothed with the speak attack. If playback RMS does not exist yet, use the lab stand-in on **raw** `t` (not `tDraw`):

```
syllable = 0.5 + 0.5 * sin(t * 6.4)
phrase   = 0.55 + 0.45 * sin(t * 1.9 + 0.4)
target   = max(micOrZero, 0.42 + 0.5 * syllable * phrase)
```

- **connect:** force `target = 0.28` after any mic value. The sine does not use `e` for its height. `e` only tints the gradient, and it must sit still.

Attack is fast, release is slower. That is the whole envelope. Do not add a spring on top.

## Shared helpers

```
lerp(a, b, t) = a + (b - a) * clamp(t, 0, 1)

smoothstep(edge0, edge1, x):
    u = clamp((x - edge0) / (edge1 - edge0), 0, 1)
    return u * u * (3 - 2 * u)

wander(t, a, b, c, phase) -> 0...1:
    return 0.5 + 0.5 * (
        0.48 * sin(t * a + phase) +
        0.32 * sin(t * b + phase * 1.73) +
        0.20 * sin(t * c + phase * 2.41)
    )
```

`wander` is not random. The frequencies are incommensurate on purpose, so two crests do not peak together. Do not replace it with `noise` or a shared phase.

## Ridge

`xn` in 0…1. Result is a fraction of height. Multiply by the pill height, then add `yShift` (points).

```
lift = 0
for peak in peaks:
    d = xn - peak.x
    mountain = exp(-(d * d) / (2 * field.width * field.width))
    lift += field.lift * mountain * peak.amp

if mode == connect:
    return field.rest - 0.08 * sin(xn * π * 4 - tDraw * 1.6)

wave =
    speak:  0.055 * sin(xn * π * 3.4 + tDraw * 2.4)
          + 0.032 * sin(xn * π * 6.1 - tDraw * 3.3)
    listen: (0.018 * sin(xn * π * 2.05 + tDraw * 0.62)
           + 0.010 * sin(xn * π * 4.6 - tDraw * 1.05))
           * (0.22 + e * 0.12)

return field.rest - lift + wave
```

Connect returns before `wave`. It has no peaks. The `− tDraw * 1.6` term is what makes the hump travel **left to right** (a crest of constant phase moves toward larger `xn` as `t` grows). `π * 4` is exactly two cycles across the pill: two equal humps, one trough. Do not add a second sine. That was tried; it split each crest into two peaks and was rejected.

Field constants, after `e` is known:

| | width | rest | lift |
|---|---|---|---|
| listen | 0.18 | 0.60 | `0.05 + e * 0.40` |
| connect | unused | 0.62 | unused |
| speak | 0.095 | 0.92 | `0.46 + e * 0.28` |

Speak `rest` is 0.92, near the floor of the pill. Crests only exist where a peak’s `lift` subtracts from that. Gaps between peaks stay low. That is the deep trough. Do not “fix” it by lowering `rest`.

Listen peaks (`t` here is `tDraw`):

```
liftL = wander(t, 0.41, 0.67, 1.13, 0.20)
liftR = wander(t, 0.29, 0.83, 1.01, 2.74)
left  = (x: 0.18 + 0.16 * wander(t, 0.33, 0.59, 0.97, 1.12),
         amp: 0.36 + e * 0.10 + (0.18 + e * 0.58) * liftL)
right = (x: 0.64 + 0.16 * wander(t, 0.27, 0.71, 1.19, 3.41),
         amp: 0.36 + e * 0.10 + (0.18 + e * 0.58) * liftR)
```

Speak peaks:

```
speak(x0, spread, phase) = (
    x:   x0 + spread * (wander(t, 1.9, 3.1, 4.7, phase) - 0.5),
    amp: 0.08 + 1.12 * wander(t, 2.4, 3.8, 6.1, phase + 1.4)
)
peaks = [speak(0.22, 0.12, 0.3), speak(0.50, 0.10, 2.2), speak(0.78, 0.12, 4.1)]
```

The spread is intentional. An earlier pass pinned each crest in a lane; that read as static and was rejected. Restore this slide.

## How a frame is drawn

Sample the ridge at **72** steps across the width. Path:

1. Start left of the pill, at the bottom (`x = -pad`, `y = height + pad`), `pad = blur * 2.5`.
2. Line through each sample `(xn * width, ridge * height + yShift)`.
3. Close at the bottom right, past the pill.

Fill that path with a **vertical** gradient (not horizontal). Gradient top is `(0.22 - e * 0.14) * height`, bottom is `height`.

```
floor = lerp( (130,168,228), (38, 96,250), e )
mid   = lerp( (100,140,214), (44,108,248), e )
crest = lerp( (150,186,232), (70,150,255), (e*0.55, e*0.45, e*0.2) )
stops: 0.00 crest α 0
       0.18 crest α 0.85
       0.42 mid   α 1
       1.00 floor α 1
```

Then, in order:

1. Clip to the stadium. Radius is `height / 2`. Fill the clip with `#050508`.
2. **Body.** Blur `blur` points. `yShift = 0`. Peaks as above (empty for connect).
3. **Listen shelf only.** Same peaks with `amp * 0.22`, blur `blur * 1.15`, `yShift = height * 0.07` (down, so it is a low echo). Time is `tDraw + 1.3`. Gradient stops: `(40,80,210,0)` at 0, `(40,90,230,0.55)` at 0.35, `floor` at α 0.9 at 1. Skip for connect and speak.
4. **Cyan filament, listen and speak only.** Screen blend. Same peaks, blur `blur * 0.8`, `yShift = -height * 0.015`. Stops: `(160,210,255, 0.20+e*0.14)` at 0, `(70,140,255,0.14)` at 0.18, `(20,50,160,0)` at 0.45, clear at 1. **Skip for connect.** A second layer on the sine is what made each hump look like two peaks.
5. **Color accents, listen and speak only.** Screen blend. `k = 0` for connect, so this loop does not run.

```
k = speak ? 0.85 : smoothstep(0.36, 0.78, e)
for i, peak in peaks:
    tall = k * smoothstep(speak ? 0.38 : 0.62, speak ? 0.85 : 0.95, peak.amp)
    if tall <= 0.02: continue
    magenta = speak ? (i == 0) : (i == last)
    green   = speak ? (i != 0) : true
```

Magenta layer: that peak alone, blur `blur * 0.85`, `yShift = -height * 0.02`. Stops `(210,90,255, 0.55*tall)`, `(80,40,180, 0.28*tall)`, clear.

Green layer: that peak at `amp * 1.05`, blur `blur * 0.65`, `yShift = -height * 0.03`. Stops `(168,236,168, 0.82*tall)`, `(96,196,120, 0.58*tall)`, `(36,110,70, 0.12*tall)`, clear.

Green follows **each** eligible crest’s own height. Do not give the color to whichever crest is tallest this frame. That swap was visible as the hue jumping.

6. **Liquid Glass is Apple’s modifier, applied after the frame.** Do not paint a sheen, a specular ellipse, a rim stroke, or a darkened floor. The lab does not draw glass; a browser cannot call this API.

The project already deploys to iOS 26, so `glassEffect` is available with no fallback. Apple’s docs: [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views). The system draws the material behind the view and the foreground lighting over it. Default shape is a capsule, which is this pill.

```swift
AuroraPill(energy: energy, mode: mode)
    .frame(width: 132, height: 52)
    .glassEffect(glass ? .regular : .identity, in: .capsule)
```

`Glass.identity` is the documented no-op when `glass` is false. Use `.regular`, not `.clear` — clear is for cases that need extra dimming to stay legible, and it will wash this aurora. Do not tint it. Do not add `interactive()`; the pill is not a button, and that modifier adds press response that fights the wave.

Apply `glassEffect` **after** `.frame`. One pill does not need a `GlassEffectContainer`. Add the container only if pause and stop become Liquid Glass too, so those shapes can blend. See `glassEffect(_:in:)` and `Glass`.

Blur amounts:

```
speak:   max(5, height * 0.09)
listen:  max(7, height * 0.13)
connect: max(4, height * 0.05)
```

Connect’s blur is lighter on purpose. The listening blur is wide enough to erase a 0.08 sine. Do not reuse it.

## Blur in Swift

`Canvas` has no CSS `filter: blur`. The blur is load-bearing.

Draw each layer into a bitmap the size of the pill (plus `pad`), run `CIGaussianBlur` with `inputRadius` equal to the point radius above (multiply by screen scale if the bitmap is in pixels), then draw the bitmap into the capsule clip. Clip **after** the blur so the light is soft and the pill edge is sharp. Blur-then-clip matches the lab. Clip-then-blur fringes the capsule.

If the first paint looks a little sharper than the lab, raise the radius slightly. Do not change ridge amplitudes to compensate.

Screen blend is `CGBlendMode.screen` / `GraphicsContext.BlendMode.screen`. The body and the shelf stay `sourceOver` (normal).

## What not to port

- The lab’s three canvases, mic button, demo pulse, and spacebar. One view, `mode` + energy.
- A hand-drawn glass skin (white sheen, catchlight ellipse, inner stroke, darkened floor). Glass is `glassEffect(_:in:)`.
- `MeshGradient`, particle orbs, LiveKit Aura, Murmur, bar visualizers. Those were research. The silhouette is this file.
- A rainbow that cycles with time. Color moves only because `e` changes and because a crest’s `amp` crosses the `smoothstep`. Connecting does not change color over time.
- Mutating a mesh grid size per frame. Not used here. If someone later tries a mesh anyway: fixed grid, pin the outer vertices, animate interior points only, `smoothsColors: true`, `colorSpace: .perceptual`. It still will not match. Don’t.

## Check against the lab before calling it done

Run `prototypes/mic-visualizer/index.html` (`?demo=1`, `?connect=1`, `?talk=1`).

- Listen: two crests, uneven, slow, shallow, blue. Green only when a crest is actually high.
- Connect: two equal rounded humps, shallow trough, constant height, sliding left to right. No magenta, no green, no second ridge on a hump.
- Speak: three crests, deep gaps, they slide past each other, magenta on one side and bottle green on a tall crest. Not a single orb. Not a stroked waveform.
