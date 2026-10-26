# Visual system: 3D heroes and a dither treatment on iOS

Date: 2026-10-26. Question for SpeechApp. No Swift sources were changed.

This note answers three production questions: which pipeline to use on current iOS, how a look like Yaroslav Demidov’s is actually made, and what the picture is made of (a 3D object, then a separate screen treatment). Claims are tied to a source. If a source was not opened, the claim is marked **UNVERIFIED**.

## Recommendation

Bake the scenes. Keep one small ordered-dither shader as the shared treatment. Do not build a runtime that can restyle arbitrary video and 3D, and do not expect a prompt tool to hold the look.

Speech practice needs a few calm, looping plates. The skeleton, boat, and seagull are authored 3D assets. The fine dot field is one screen treatment over the finished picture, including the heroes. Water and sky look more like a shader only because they are smooth gradients, so the same dots read as a field. Those are two jobs: author the picture, then apply one treatment. Offline tools already do the first. A single per-pixel shader does the second, and it is the piece that makes every screen belong to one system.

Use the shader on stills, on simple live drawings (a waveform), and on a plate when you want one source image to wear the house treatment. Ship the heroes as short looping video, or as an image sequence, with the treatment already decided in the composite. Add a RealityKit scene and a post-process only for a shot that must respond to the user while it is on screen.

## There is no iOS 25

Apple’s June 10, 2024 newsroom previewed **iOS 18**, a free update that fall for iPhone Xs and later. [iOS 18 newsroom](https://www.apple.com/newsroom/2024/06/ios-18-makes-iphone-more-personal-capable-and-intelligent-than-ever/)

Apple’s June 9, 2025 newsroom previewed **iOS 26**, a free update that fall for iPhone 11 and later. [iOS 26 newsroom](https://www.apple.com/newsroom/2025/06/apple-elevates-the-iphone-experience-with-ios-26/)

The press release names iOS 26 and does not say “we skipped 19.” The Associated Press, reporting the same WWDC, wrote that the autumn release “will be known as iOS 26 instead of iOS 19.” [AP, June 2025](https://apnews.com/article/apple-conference-iphone-artificial-intelligence-ba918c2091e0d49a8b3f164e4f980b6e)

Apple’s September 14, 2026 newsroom says the new features “start rolling out today across iOS 27” and the other 27 platforms. A footnote records Apple testing an iPhone 11 Pro Max on iOS 26.6 and a prerelease iOS 27. That shows the iPhone 11 generation was in the iOS 27 test set. It is not a full device list. [iOS 27 newsroom](https://www.apple.com/newsroom/2026/09/major-updates-for-apples-software-platforms-are-now-available/)

Apple Support documents iOS 27, released September 14, 2026, and a 27.0.1 bug-fix update. [About the security content of iOS 27](https://support.apple.com/en-us/149034) [About iOS 27 Updates](https://support.apple.com/en-us/149076)

**iOS 25 does not exist.** The public line on the date of this note is iOS 27. The API annotations below were read from the iPhoneOS 27.1 SDK in Xcode 27.1 on the machine used for this research (`SDKSettings.plist`: `CanonicalName` = `iphoneos27.1`, `Version` = `27.1`).

“Devices that run the current iOS” is a wide set. iOS 26 already reaches iPhone 11. The iOS 27 footnote puts an iPhone 11 Pro Max on a prerelease build. A17, A18, and A19 are the recent GPU classes. iPhone 11 is not in that class. A treatment that is comfortable on a new phone still needs a check on the oldest phone you ship to.

## What the picture is

The reference description is a composite, not one effect.

| Layer | What it is | What produces it |
| --- | --- | --- |
| Hero | A large modeled object: skeleton, boat, seagull. It has a silhouette, a material, and a light. | A 3D asset, rendered or drawn on its own. |
| Scene plate | Water, sky, ground. Smooth shading, including a reflective water surface. | A render or a shader: moving normals, a reflection, a horizon. |
| Screen treatment | A fine, stable field of dots or marks over the plate. It reads as ordered dither, stipple, or near-ASCII. | A threshold or a glyph chosen from brightness and pixel position. |

**Ordered dither (Bayer).** Bryce E. Bayer, “An optimum method for two-level rendition of continuous-tone pictures,” Proceedings of the IEEE International Conference on Communications, 1973, pp. 2611–2615. Bibliographic record: [CiNii](https://cir.nii.ac.jp/crid/1573105975705169408?lang=en). An archived PDF is at the [Wayback Machine](https://web.archive.org/web/20130512190753/http://white.stanford.edu/~brian/psy221/reader/Bayer.1973.pdf). This note did not re-read the PDF.

The working definition used here: tile a small threshold table across the frame. The pixel at `(x, y)` reads the cell `(x mod n, y mod n)` and keeps the light or dark ink according to its brightness. No pixel reads its neighbor. The pattern is stable when the picture moves, which is why a gradient (sky, water) breaks into a fine crosshatch instead of bands. A larger table makes a finer, less obvious repeat.

**Error diffusion** is the other famous dither. J-GLOBAL records “An adaptive algorithm for spatial greyscale,” vol. 17, no. 2, pp. 75–77, 1976, under L. Steinberg. [J-GLOBAL](https://jglobal.jst.go.jp/en/detail?JGLOBAL_ID=201002004108891171). The usual name Floyd–Steinberg includes a coauthor this bibliographic page does not list. **UNVERIFIED** against the PDF. The method adds the rounding error onto later pixels. That needs pixels in order. It does not fit a shader in which every pixel runs alone.

**Halftone**, in print, grows a dot on a grid so a coarser mark stands for a grey. Ordered dither can imitate that (a clustered threshold) or scatter single pixels (Bayer’s dispersed dot). The reference description, “fine” and “ordered,” matches a dispersed or high-frequency threshold, not a newspaper dot you can see across the room.

**Stipple** places marks whose density follows tone. The usual paper is Adrian Secord, “Weighted Voronoi Stippling,” NPAR 2002. **UNVERIFIED**: that PDF was not opened here. A fine Bayer field is often what people mean by stipple in motion work, because it is a shader. A true Voronoi stipple is a placed set of dots, usually baked.

**ASCII** picks a character from the brightness of a cell. A 2026 Codrops tutorial states the mechanism: the shader has no font calls, so glyphs are a grid or a texture, one sample per cell, darker cells get denser characters. [Codrops, Jan 4, 2026](https://tympanus.net/codrops/2026/01/04/efecto-building-real-time-ascii-and-dithering-effects-with-webgl-shaders/). “Near-ASCII” in the reference can be this, or it can be a Bayer field small enough to read as type. The two are different shaders. A glyph atlas is a texture sample. A Bayer field is arithmetic on `(x, y)`.

**Pixel sorting** reorders a run of pixels by brightness. It needs the run. It is a poor fit for the per-pixel SwiftUI shader model below. Crediting the look to Kim Asendorf is **UNVERIFIED** in this pass.

**Toon plus dither** is two steps. The material keeps a few bands of light and shadow. The dither then breaks the edge of a band so it does not posterize. The bands belong to the hero or the plate. The dots belong to the treatment.

**Reflective water** is a material, not a dither. Animated normals and a reflection make smooth gradients. Ordered dither is what turns those gradients into a stable dot field.

Frames from the two attached recordings of “Sinking into dither” (`inspo/ScreenRecording_10-25-2026 23-57-21_1.mov`, reel / 02, the boat and gull; `inspo/ScreenRecording_10-25-2026 23-58-43_1.MP4`, reel / 03, the skull and hand) show the same dot field on the heroes and on the water. The objects stay readable because the lighting is high contrast. A mask that holds the hero out, or dots it more lightly, is a possible extra rule. It is not what these two clips do. No public breakdown of the shots was found, so the DCC tool and whether a mask was used upstream stay **UNVERIFIED**.

## What Demidov has actually published

Public pages tie the name together. Contra’s profile markup for Yaroslav Demidov lists the job line “Digital Designer. Motion, Interaction, Direction, UI,” a “Rive expert” badge, and the same identity on Instagram `ya_demidov`, X `ydmdv`, and LinkedIn `yademidov`. [Contra profile](https://contra.com/yademidov)

His own posts name tools for specific pieces, not a Cinema 4D showreel:

- April 3, 2026, his Contra post is titled “Made in Rive.” [Post](https://contra.com/community/hLqVQJFJ-hire-expert-rive-animator-for-engaging)
- His Dribbble titles include “Interactive flower made in Rive,” “SVG Lottie Animation,” “Lottie Icons SVG Animation,” and “Webgl Interaction.” [Dribbble](https://dribbble.com/yademidov)
- September 16, 2026, he wrote that one browser piece was made “without opening a single design app,” by “telling Codex what I wanted it to do.” “It’s not a magic button. It took around 100 prompts and quite a few hours.” “The whole thing runs and renders right in the browser.” Tags on the post include WebGL. [Post](https://contra.com/community/jkcNJaZb-i-just-like-making-things-like)

A third party, Artistry Visual Lab, posted that “@ya_demidov turns generative dither and interaction into a frame” and tagged the post WebGL. That is their caption, not his tool list. [LinkedIn activity](https://www.linkedin.com/posts/artistry-visual-lab_avl-creativecoding-generativeart-activity-7516649255537676288-nipL)

**UNVERIFIED:** Cinema 4D, Redshift, Octane, Houdini, Blender, After Effects, Cavalry, TouchDesigner, Unreal, Notch, or Substance as his credit on the skeleton, boat, or seagull clips. Searches of those pairings did not return a post by him that names them. Do not plan the app’s pipeline on that assumption.

What the found posts do show is a working method used by this artist and by motion designers generally: author a picture in a tool that can hold a style, export a runtime file or a render, and use code or a shader where the picture has to run live. His Codex experiment is the caution about prompts. The result still needed a person to art-direct about a hundred tries, and a commenter on that post described the result as “deliberately art-directed, not like a raw generated output.”

A typical offline path, from the tool docs rather than from his captions:

1. Model and light the hero, and render the plate (water, sky, ground), in a 3D program. Export a still, a sequence, or a masked render.
2. Apply the dot treatment in comp, or with a shader that only sees the plate.
3. Lay the hero back on top if it should stay cleaner than the water.
4. Deliver a loop (video or frames) or, when it must stay interactive, a realtime file (Rive, Spline, or your own Metal).

Cavalry’s render manager writes that last delivery as MP4, QuickTime (including ProRes 4444 with alpha), PNG, WebP, GIF, SVG, a sprite sheet, or Lottie. [Render Manager](https://docs.cavalry.scenegroup.co/user-interface/menus/window-menu/render-manager/)

## SwiftUI shaders

Read from `SwiftUICore.swiftinterface` in the iPhoneOS 27.1 SDK.

`ShaderLibrary`, `ShaderFunction`, and `Shader` are available on iOS 17.0, macOS 14.0, and tvOS 17.0, and unavailable on watchOS. `ShaderLibrary.default` loads the app’s Metal library. A dynamic member (`ShaderLibrary.myFunction`) returns a `ShaderFunction`. Calling it with arguments returns a `Shader`.

`View.colorEffect`, `View.distortionEffect`, and `View.layerEffect` have the same floor: iOS 17.0. `distortionEffect` and `layerEffect` take a `maxSampleOffset`. `Shader.compile(as:)` is a later addition, iOS 18.0, with usage types for shape style, color effect, distortion effect, and layer effect.

`Shader.Argument` can carry floats, colors, an image, and `Data`. There is a `dithersColor` flag on `Shader`. The interface does not document it. What that flag does is **UNVERIFIED**.

Apple’s own description of the three calls, from WWDC26: [Compose advanced graphics effects with SwiftUI](https://developer.apple.com/videos/play/wwdc2026/322/)

- `colorEffect` gets the pixel position and the color already there, and returns a new color. Their example is a color change such as black and white.
- `distortionEffect` returns a position. SwiftUI samples the original view there. Their example is a geometric warp.
- `layerEffect` also runs per pixel, and it hands you the layer so you can sample other positions. Their example is a blur. The Metal function is marked `[[stitchable]]`, takes `float2 position` and `SwiftUI::Layer`, and returns `half4`.

WWDC24, which introduced the API: shaders were added in iOS 17, they are Metal Shading Language rather than Swift, SwiftUI calls the function for every pixel, and a layer sample must stay inside `maxSampleOffset` of that pixel. You pass colors, numbers, or an image in from Swift. [Create custom visual effects with SwiftUI](https://developer.apple.com/videos/play/wwdc2024/10151/)

WWDC26 states the limit that decides which treatments are possible: “Each pixel executes independently, with no awareness of its neighbors.”

Consequences, from that rule rather than from a sentence that says “particles are forbidden”:

- Ordered dither and a one-sample ASCII cell fit `colorEffect` (dither) or `layerEffect` plus an image argument (a glyph atlas). WWDC26 shows a `texture2d` argument fed by `Shader.Argument.image`.
- Error diffusion, pixel sorting, and a particle simulation do not fit. They need other pixels, or a store of particles. SwiftUI’s shader modifiers are stitchable fragment-style functions, not a compute pass and not a sprite system.
- A full 3D scene is not a SwiftUI shader. The shader restyles a view SwiftUI has already drawn.

For this app, the house treatment is a `colorEffect`: brightness of the pixel, Bayer cell from the pixel coordinate, two or three inks. Same cell size and same inks on every screen. That is the system.

## RealityKit, Metal, SceneKit

**USDZ.** Apple’s USD documentation says RealityKit is the renderer for Reality Composer, Reality Composer Pro, and RealityKit scenes, and that USDZ is the package to distribute: one archive of the scene plus textures and audio. USDA is the text working format. USDC is the binary working format. [Creating USD files for Apple devices](https://developer.apple.com/documentation/usd/creating-usd-files-for-apple-devices)

**Materials.** In the iOS 27.1 SDK, `CustomMaterial` conforms to `Material` and is available on iOS 15.0. A custom material is a Metal function on a model (surface and geometry). That is where a toon ramp or a water normal lives. It is not a full-screen dither of the finished picture.

**Post-process.** `PostProcessEffect` and `RealityViewRenderingEffects.customPostProcessing` are available on iOS 26.0, macOS 26.0, and tvOS 26.0, and unavailable on visionOS and watchOS. The context gives the command buffer, the source color texture, the source depth texture, and the target color texture. WWDC25 shows assigning one with `content.renderingEffects.customPostProcessing = .effect(...)`, and points at Metal Performance Shaders for effects such as bloom. [Bring your SceneKit project to RealityKit](https://developer.apple.com/videos/play/wwdc2025/288/) [Post-process article](https://developer.apple.com/documentation/realitykit/using-metal-performance-shaders-to-create-custom-postprocess-effects)

A dither of a live 3D scene belongs here, or in your own Metal pass, because it must see the finished image and, if the hero stays cleaner than the water, the depth or an object mask. `PostProcessEffect` is an iOS 26 API. It is present for an app that requires the current OS line. It is absent if you still support iOS 18.

**MTKView.** Apple’s MetalKit header calls it a “View for rendering metal content” that sets up Metal drawable textures. Available since iOS 9.0. (`MTKView.h` in the iPhoneOS 27.1 SDK.) Use it when the picture is a full custom renderer: load a USDZ or your own mesh, draw it, then run one fragment pass for the dither. That is more code than RealityKit’s post-process, and it is the right box only if RealityKit’s material and post-process model gets in the way.

**SceneKit.** WWDC25, Max Cobb: “this year Apple is officially deprecating SceneKit across all platforms.” It is a soft deprecation. Existing apps keep working. New work should use RealityKit. SceneKit is in maintenance: critical bugs only, no new features planned, no hard-removal date announced in that talk. The iOS 27.1 SDK still ships `SceneKit.framework`. The session is the deprecation. A new visual system should not start there.

## What a full-screen dither costs

No Apple page found in this pass publishes a frame time for a full-screen fragment shader on A17, A18, or A19. Any millisecond figure for those chips is **UNVERIFIED**.

What Apple does say, about Apple-designed GPUs as a class:

- They are tile-based deferred renderers. Geometry is binned into tiles. Fragments for a tile shade using on-chip tile memory. Load and store actions move those attachments to system memory, and “these actions consume the majority of your app’s system bandwidth.” Peak performance is when the GPU is not bandwidth-bound. Fewer passes mean less of that traffic. [Optimize Metal Performance for Apple silicon Macs, WWDC20](https://developer.apple.com/videos/play/wwdc2020/10632/)
- “Per-pixel operations with no interpixel dependency should be implemented using fragment functions.” [Create image processing apps powered by Apple silicon, WWDC21](https://developer.apple.com/videos/play/wwdc2021/10153/)

A Bayer dither is that case: one read of the pixel, a few arithmetic ops, one write. It does not sample a neighborhood, so it does not blow the `maxSampleOffset` budget, and it does not add a second heavy pass beyond the load and store Apple already counts as the main cost. On an A17-class phone this is a small effect next to speech recognition and a 3D lighting pass. That comparison is qualitative. Measure it on the oldest phone you support before treating it as free, especially at full resolution with other post effects.

The expensive version is a live 3D scene plus a post pass plus a video decode you then sample again. The cheap version is a decoded loop that already contains the dots.

## Video, then a shader, versus a bake

Apple, WWDC20: “in current versions of the OS, all media interfaces will automatically enable hardware decode when available.” Playback through AVFoundation uses that path. [Decode ProRes with AVFoundation and VideoToolbox](https://developer.apple.com/videos/play/wwdc2020/10090/)

The same talk shows the extra path: take decoded `CVPixelBuffer`s into Metal with `CVMetalTextureCache`, and do not let the buffer pool recycle an IOSurface Metal is still reading. Apple’s older sample `AVBasicVideoOutput` is the app-side version of that idea. `AVPlayerItemVideoOutput` gives you a buffer each vertical sync, and the sample then processes every frame before display. [Sample README](https://developer.apple.com/library/archive/samplecode/AVBasicVideoOutput/Listings/README_md.html)

So the costs separate cleanly:

| Path | What the device does | When to use it |
| --- | --- | --- |
| Baked loop | Hardware decode, then display. The dots are already in the frames. | Heroes and plates that do not react to speech. |
| Decode, then a shader | Hardware decode, a texture wrap, and a full-screen pass every frame. | One source plate that must wear the house dither, or change ink with the session, without storing a second encode. |
| Live 3D, then a shader | Skinning, lighting, and a post pass. No video decoder. | The object has to move because of the user. |

A baked HEVC or H.264 loop is the smallest runtime for a speech screen. The shader-on-video path is justified when you need one master and several treatments, or a treatment that follows live state. It is a bad trade when every shot is a fixed composition: you pay a pass you could have baked, and you take on the pixel-buffer lifetime rules above.

Lottie and a PNG sequence are bakes of a different kind. A sequence is simple and heavy on disk. A video is small and needs a decoder. Lottie is vectors and is the wrong container for this plate (next section).

## Prompts

Prompt tools make an asset. They do not store a design system. A system here is a fixed ink set, a Bayer cell size, a camera distance, a rule for which layer gets the dots, and the same hero language from one exercise to the next. None of the products below record that.

- **Meshy** text-to-3D is two calls: a preview mesh from a prompt, then a refine that textures it. The docs’ example asks for `glb` among target formats. The web app’s result, before you texture it, is “a mesh without textures.” Meshy says the tool is for exploring concepts, and that models are for art and games rather than CAD. [Text to 3D API](https://docs.meshy.ai/en/api/text-to-3d) [Web app](https://docs.meshy.ai/en/webapp/text-to-3d)
- **Tripo** documents text-to-3D, image-to-3D, and multiview-to-3D, including a P series aimed at cleaner topology. Output is a generated model, one task at a time. [Tripo docs index](https://developers.tripo3d.ai/llms.txt)
- **Runway Gen-4** makes a 5 or 10 second video at 24 fps from a required input image plus text. Resolutions are fixed sizes such as 720p. It is a shot generator. It is not a shader, and a later shot does not inherit the previous shot’s materials. [Creating with Gen-4 Video](https://help.runwayml.com/hc/en-us/articles/37327109429011-Creating-with-Gen-4-Video). Runway’s help page points newer work at Gen-4.5 and other apps. Treat Gen-4 as the documented older generator, not as the only 2026 model.
- **Demidov’s own prompt experiment** (Codex, about 100 prompts, browser, WebGL) is the first-party evidence that a prompt stack can produce a live picture and still needs a director. [Post](https://contra.com/community/jkcNJaZb-i-just-like-making-things-like)

**Luma** and **Spline AI** as 2026 prompt-to-3D or prompt-to-shader products were not pinned to a product page in this pass. **UNVERIFIED** as a recommendation. Spline’s iOS feature table says “AI Assistant Events are not supported yet,” which is a runtime gap, not a generator. [Spline iOS embeds](https://docs.spline.design/exporting-your-scene/apple-platform/native-3d-embeds-for-i-os)

Use a generator to draft a mesh or a mood frame. Rebuild the hero in the house scale, light, and palette, then run it through the same dither. Otherwise each exercise looks like a different app.

## Rive, Lottie, Cavalry, Spline

**Rive on Apple.** The runtime supports iOS 14 and later. A `.riv` file is what you export for runtimes. 3D content requires a `Worker` created with `enableGPUCanvas: true`, and that flag covers every file that worker loads. [Apple runtime](https://rive.app/docs/runtimes/apple/apple) [Choosing a renderer](https://rive.app/docs/runtimes/choose-a-renderer/overview)

Rive shaders are WGSL, vertex plus fragment, compiled into the `.riv` for selected targets including Metal. Compute shaders are not supported. A fullscreen triangle plus a fragment shader is a documented pattern, so an ordered dither can be written there. [WGSL shaders](https://rive.app/docs/scripting/wgsl-shaders)

That makes Rive a possible home for a small interactive graphic with a custom shader. It does not, by itself, replace a 3D plate pipeline. Demidov’s found Rive credits are interaction pieces (“Made in Rive,” an interactive flower). Putting the speech-app scenes in Rive means authoring them in Rive’s 3D and WGSL tools and shipping a second renderer next to SwiftUI. Reasonable for a control or a small hero. A poor fit for a library of filmed-feeling plates.

**Lottie.** Airbnb’s support table is vector artwork: shapes, fills, strokes, transforms, masks. [supported-features.md](https://github.com/airbnb/lottie/blob/master/supported-features.md). Cavalry’s Lottie export page lists what does not survive the trip, including all filters, the noise shader, the SkSL shader, and the color shader. [Lottie export](https://docs.cavalry.scenegroup.co/user-interface/menus/window-menu/render-manager/lottie-export/). A dithered 3D plate is a filter or a shader. Lottie will not carry it. Use Lottie for icon and UI motion.

**Cavalry** is an authoring tool with a render queue, not an iOS runtime. Render to MP4, QuickTime/ProRes, a PNG sequence, or a sprite sheet when the shot is this look. Export Lottie only for the vector parts.

**Spline** ships a Metal-based iOS runtime. `SplineView` loads a `.splineswift` file from the bundle or from a URL. Minimums in their table: iOS 16 and an A13. Export for Apple platforms needs a Pro or Max plan. The feature table marks materials, events, physics, particles, animated models, and post-processing as supported, with explicit gaps: cavity, dust, and reflection layers are not supported, and ambient shadows in post are not supported. Decals and hair are unfinished. [Native 3D embeds for iOS](https://docs.spline.design/exporting-your-scene/apple-platform/native-3d-embeds-for-i-os)

Spline can put an interactive 3D scene in the app. The docs do not describe an ordered-dither or ASCII shader, and the missing reflection layer matters if the water is supposed to be a reflective material. Treat Spline as a viewer for Spline scenes, then confirm the stipple by eye. Whether their post stack can fake this treatment is **UNVERIFIED**.

## What to build

1. Pick the inks, the Bayer cell size, and the rule that the reference clips actually use: the same dots on the hero and on the plate. A lighter hero is a later choice, not the look in the recordings. Write that down. It is the system.
2. Author each exercise as a short loop. Composite in the tool you already use. Export video (alpha only if a hero must sit over live UI).
3. Add one SwiftUI `colorEffect` in a `.metal` file for live 2D and for any plate that must be recolored without a new encode. iOS 17 is enough for that call. The current OS is far above it.
4. Reach for RealityKit, USDZ, and `PostProcessEffect` only when a hero has to move with the session. That post-process needs iOS 26.
5. Leave SceneKit, a general video-to-shader graph, Lottie-as-the-plate, and prompt-to-final-frame off the plan.
6. If a generator drafts a mesh, retopologize and relight it into the house. Demidov’s own account of prompting is a hundred directed tries, then a person still owns the taste.

## Sources

Primary or first-party pages this note relies on:

- Apple, [iOS 18](https://www.apple.com/newsroom/2024/06/ios-18-makes-iphone-more-personal-capable-and-intelligent-than-ever/), June 10, 2024.
- Apple, [iOS 26](https://www.apple.com/newsroom/2025/06/apple-elevates-the-iphone-experience-with-ios-26/), June 9, 2025.
- Apple, [iOS 27](https://www.apple.com/newsroom/2026/09/major-updates-for-apples-software-platforms-are-now-available/), September 14, 2026.
- Apple Support, [iOS 27 security](https://support.apple.com/en-us/149034), [About iOS 27 Updates](https://support.apple.com/en-us/149076).
- AP, [WWDC report](https://apnews.com/article/apple-conference-iphone-artificial-intelligence-ba918c2091e0d49a8b3f164e4f980b6e), iOS 26 instead of iOS 19.
- iPhoneOS 27.1 SDK, Xcode 27.1: `SwiftUICore.swiftinterface`, `RealityFoundation.swiftinterface`, `_RealityKit_SwiftUI.swiftinterface`, `MTKView.h`, `SceneKit.framework`.
- Apple, [WWDC24 shaders](https://developer.apple.com/videos/play/wwdc2024/10151/), [WWDC26 shaders](https://developer.apple.com/videos/play/wwdc2026/322/), [WWDC25 SceneKit](https://developer.apple.com/videos/play/wwdc2025/288/), [WWDC20 Metal bandwidth](https://developer.apple.com/videos/play/wwdc2020/10632/), [WWDC21 image processing](https://developer.apple.com/videos/play/wwdc2021/10153/), [WWDC20 video decode](https://developer.apple.com/videos/play/wwdc2020/10090/), [AVBasicVideoOutput](https://developer.apple.com/library/archive/samplecode/AVBasicVideoOutput/Listings/README_md.html), [USD for Apple devices](https://developer.apple.com/documentation/usd/creating-usd-files-for-apple-devices).
- Bayer 1973, [CiNii](https://cir.nii.ac.jp/crid/1573105975705169408?lang=en), [archived PDF](https://web.archive.org/web/20130512190753/http://white.stanford.edu/~brian/psy221/reader/Bayer.1973.pdf).
- Steinberg 1976 record, [J-GLOBAL](https://jglobal.jst.go.jp/en/detail?JGLOBAL_ID=201002004108891171).
- Yaroslav Demidov, [Contra](https://contra.com/yademidov), [Rive post](https://contra.com/community/hLqVQJFJ-hire-expert-rive-animator-for-engaging), [Codex post](https://contra.com/community/jkcNJaZb-i-just-like-making-things-like), [Dribbble](https://dribbble.com/yademidov).
- Rive, [Apple](https://rive.app/docs/runtimes/apple/apple), [renderer choice](https://rive.app/docs/runtimes/choose-a-renderer/overview), [WGSL](https://rive.app/docs/scripting/wgsl-shaders), [export](https://rive.app/docs/editor/exporting/exporting-for-runtime).
- Lottie, [supported features](https://github.com/airbnb/lottie/blob/master/supported-features.md).
- Cavalry, [Render Manager](https://docs.cavalry.scenegroup.co/user-interface/menus/window-menu/render-manager/), [Lottie export](https://docs.cavalry.scenegroup.co/user-interface/menus/window-menu/render-manager/lottie-export/).
- Spline, [iOS embeds](https://docs.spline.design/exporting-your-scene/apple-platform/native-3d-embeds-for-i-os).
- Meshy, [API](https://docs.meshy.ai/en/api/text-to-3d), [web app](https://docs.meshy.ai/en/webapp/text-to-3d).
- Tripo, [docs index](https://developers.tripo3d.ai/llms.txt).
- Runway, [Gen-4 Video](https://help.runwayml.com/hc/en-us/articles/37327109429011-Creating-with-Gen-4-Video).
