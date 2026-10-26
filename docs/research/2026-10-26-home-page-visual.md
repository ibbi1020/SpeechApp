# Home page visual

Date: 2026-10-26. Decision brief for the agent that builds the home picture. The longer pipeline research is `docs/research/2026-10-26-shader-visual-system.md`. This file is the part that binds the home screen.

The look is approved as a direction. The meshes are not. Build the home picture when the user supplies the hall and the person. Leave the rest of the app alone.

## The picture

Home is one standing person in the middle of an empty circular hall. Seats repeat around them. Water sits at seat height, so the lower tier meets the waterline. The person stands on the platform, above the water.

The same ordered dither covers the finished frame, including the person, the seats, and the water. Smooth light becomes a field of dots. Hard-lit forms stay readable. Type and the Begin button stay sharp, in front of the picture.

One person. Empty seats. Nobody in the seats.

An earlier draft, `docs/superpowers/specs/2026-10-11-home-dither-identity-design.md`, banned an auditorium and rows of seats because the product is private practice, not a performance. That draft is superseded for implementation. The ban on an audience still holds. The hall is the scene the user chose after rejecting a boat, a bell, and a shell. The seats are architecture. They are empty.

## What was judged

Approved:

- The ordered-dither treatment in `prototypes/code-dither/index.html`. The user called this the look to keep, and described it as glitter. Default: Bayer 8×8, pitch 2 physical pixels, 6 inks, the green grade below.
- The home composition: greeting at the top, the scene in the middle band, a white Begin capsule at the bottom.
- Real meshes for the hall and the person. The user will supply them. Water and the dither stay in code, so the dots can move and the grade can change without a new model.

Rejected:

- Analytic blob meshes (stone, stacked-sphere figure, hull, gull) in `prototypes/code-dither/index.html`. The shader in that file is the reference. The objects are not.
- The mannequin in `prototypes/hall-scene/index.html`. That file is a composition test: camera, ring of seats, water disc, chrome. Replace the figure and the chairs with the supplied models. Do not port the cylinder person.
- A crowd, a face in the audience, or anyone watching.
- Skull, boat, and other reference subjects as the home scene. The boat reel is the lighting and dither reference only.

Reference clips, already dithered on both the hero and the water: `inspo/ScreenRecording_10-25-2026 23-57-21_1.mov` (boat and gull) and `inspo/ScreenRecording_10-25-2026 23-58-43_1.MP4` (skull). Match the dot field, not the subjects.

## Asset contract

Accept glTF or USDZ. The user does not model in Blender. Do not replace a missing model with a shader sculpture.

The model contains:

- The round room, one repeated chair, columns if the design has them, and one standing person.
- A floor at a known height, with a gap or a flat where the water disc sits. Water is not a textured plane in the file.
- Simple materials and one clear key light. The dither only has a few inks. A noisy texture becomes mud. A smooth form with a hard silhouette becomes the boat look.

The model does not contain a second person, a filled audience, or baked dots. Dots are the screen treatment. Baking them into the texture blocks a later palette change.

For the app, USDZ is the delivery format. RealityKit is the renderer. `usdzip` is at `/usr/bin`. SceneKit is deprecated. Do not start a SceneKit scene.

## Water and dither

Two jobs, in this order: draw the lit scene, then run one full-screen dither over that image.

Water is a disc at seat height. A slow ripple in the vertex shader is enough. Opaque water hides whatever is below the line. The rings are how the dots show that the floor is liquid. A live fluid sim is out of scope. Under Reduce Motion, freeze time.

Dither is one Bayer 8×8 `colorEffect` (or one RealityKit `PostProcessEffect` when the picture is a RealityKit view). Per pixel, no neighbor reads:

```
t = (bayer8(pixel / pitch) + 0.5) / 64
q = floor(luma * (levels - 1) + t) / (levels - 1)
rgb = grade(q)
```

`bayer8` is the standard 8×8 matrix. Pitch is the cell size in physical pixels. `levels` is the ink count.

Approved grade, linear RGB:

| Stop | RGB |
| --- | --- |
| Shadow | 0.012, 0.030, 0.026 |
| Mid | 0.09, 0.28, 0.20 |
| Paper | 0.78, 0.90, 0.78 |

Below 0.5, mix shadow to mid. Above 0.5, mix mid to paper.

Approved defaults: pitch 2, 6 inks. Pitch 1 is the finer setting. The prototype’s Dots and Inks sliders exist so a person can compare. Ship the defaults. Do not ship the sliders on home.

`colorEffect` exists on iOS 17. `PostProcessEffect` exists on iOS 26. There is no iOS 25. The current OS line on this date is iOS 27. A full-screen Bayer pass is cheap next to a live water simulation or a video decode. Prefer one pass: lit color in, dithered color out. The prototype uses two passes only because it is a browser test.

The same dots land on the person and on the water. A mask that keeps the hero cleaner is a later choice. The reference clips do not do that.

## Chrome that stays

Home is `EntryFlowView.home` in `ios/App/Screens/EntryFlowView.swift`. The picture replaces the black fill behind the column. The column stays:

| Piece | Rule | Source |
| --- | --- | --- |
| Greeting | “Find your voice” before the first session, “Speak with poise” after. One line, h1, undithered. | `EntryGreeting.line` |
| Begin | White capsule, 61pt tall, 17pt medium black label, “Begin”. One tap starts the ceremony. | `SpeechStartButtonStyle`, `SpeechStartMetrics` |
| Ground | Black. The dither’s darkest ink is near-black green, so the picture can meet the background. | `CeremonyPalette.background` |
| Gallery | A sheet peeks 88pt from the bottom. Begin already clears it. The picture continues behind the peek. | `GallerySheet.peek`, `GallerySheet.homeClearance` |

The prototype stage is a phone frame, about 9:19.5, with the greeting at the top and Begin above the bottom controls. Those bottom controls are prototype-only.

## Done

The home screen is done when all of these are true:

- The supplied hall and one person are on screen, lit, and readable after the dither.
- Water is a separate surface at the seat line, with a slow ripple that stops under Reduce Motion.
- One Bayer treatment uses the grade, pitch, and ink count above, on the person and on the room.
- Greeting text and Begin are the existing views, sharp, and tappable. Begin still clears the gallery peek.
- The seats are empty.
- No new speech-session rendering, no SceneKit, and no prompt-to-image step in the home path.
