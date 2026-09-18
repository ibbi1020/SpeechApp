# Scoping: On-device ASR floor (iPhone 10/11) + live-feedback failure

**Format name:** **Reading** (alias Format 1). See `docs/formats.md`. Compute placement for GOP was later opened to a backend (`docs/product-spec.md` §2, 2026-09-18); this note is about the live follow-along path.

**Frame:** Maximize on-device processing for Reading live read-aloud; decide whether to keep SpeechAnalyzer/iOS 26–first or pivot to older ASR stacks so a large share of users can run the app (~iPhone X / 11).

**Decision this informs:** Fix-first vs architecture pivot; product floor = iPhone X vs iPhone 11; cloud ASR allowed or not.

**Panel:** Staff Engineer, Product Manager, Data/ML, GTM, Security & Privacy. Moderator pass completed 2026-09-06.

---

## TL;DR verdict

- **Overall:** **GO-IF** — fix the confirmed wiring bug and speech-auth gaps on the current iPhone 15 build **before** any engine pivot; then set the public floor to **iPhone 11 (A13) / on-device SFSpeech (+ optional WhisperKit)**, not iPhone X, unless product explicitly accepts an iOS ≤16 dual-target.
- **Feasibility:** 🟡 — On-device known-script ASR without cloud is feasible on A13 via Apple on-device Speech; full on-device phoneme GOP on that hardware is unproven. SpeechAnalyzer alone cannot serve iPhone X.
- **Scope:** **M** — MVP = reliable live skip/extra/substitute on-device; expand floor after measured fallback on ≥1 older iOS 26 device. Slice B GOP stays stubbed.
- **Product-fit:** 🟢 — Spec already requires ~150–200 ms live marks + on-device privacy; “all skipped” is a core-loop failure, not a nice-to-have.
- **Market-fit:** 🟡 — Peers (ELSA, BoldVoice) win with **cloud CAPT** and low OS floors; Read Along proves **on-device read-along** works at scale. SpeechAnalyzer-only is not how winners ship.
- **Recommended next step:** Redeploy the subscribe-order + speech-auth fixes on device; if live marks work, spike SFSpeech-primary on one A13/iOS 26 phone before claiming iPhone 11+.

---

## Bug diagnosis (not primarily hardware)

Observed: stop → “no words spoken” / all script words skipped.

**Root cause (Staff Engineer, code):** `ReadingSession.start()` previously awaited `engine.start()` **before** creating `engine.updates`. `LiveTranscriptionEngine.updates` only assigns `updateContinuation` when the getter runs, so Dictation/SF yields hit `nil` and drop. On stop, `TokenAligner.finish()` marks remaining words as skips. That alone matches the symptom.

**Secondary gaps (same session):** missing `SFSpeechRecognizer.requestAuthorization` (only mic was requested); fallback previously assigned `supportsOnDeviceRecognition = true` instead of probing it.

**Status in repo:** subscribe-before-start is fixed in `ReadingSession.swift`; speech auth + on-device probe fixed in `LiveTranscriptionEngine.swift` / `ReadingSessionView.swift`. **Not yet proven on device** — retest before blaming SpeechAnalyzer hardware.

---

## What we'd build (scope)

### MVP (now)
1. Reliable live marks on developer iPhone 15 (post-fix retest).
2. Strict on-device: `requiresOnDeviceRecognition = true`, fail loud if unsupported — no silent Apple-server fallback.
3. Availability UI already shows Dictation vs SF path; surface `engineKind` on the report.

### Sequenced expansion
4. Validate SF / Dictation path on **one iPhone 11-class (A13) iOS 26** device.
5. Lower architecture lock from “A18-class” marketing to **iPhone 11+ / iOS 26** with SFSpeech on-device primary if Dictation unavailable.
6. Optional WhisperKit tiny/base as offline/locale fallback (not primary live karaoke until latency measured).

### Out of scope for this decision
- Claiming **iPhone X** as launch floor while staying on iOS 26 / SpeechAnalyzer.
- Slice B phoneme GOP on A13.
- Cloud ASR / cloud CAPT (ELSA-style) unless explicit labeled opt-in.
- Android / Format 2.

---

## Feasibility

| Path | Floor | On-device? | Effort | Notes |
|------|-------|-----------|--------|-------|
| Fix wiring + auth only | Current device | Yes (existing stack) | **S** | Required regardless |
| SpeechAnalyzer / DictationTranscriber | iOS 26+, hardware-gated; Dictation ≈ legacy dictation models | Yes | Already built | iPhone 11 can run iOS 26; X cannot ([Apple iOS 26 models](https://support.apple.com/en-us/123705); [Macworld compatibility](https://www.macworld.com/article/1811287/which-version-of-ios-can-my-iphone-run.html)) |
| SFSpeechRecognizer `requiresOnDeviceRecognition` | A9+, iOS 13+ | Yes if models installed | **M** | WWDC19 A9+ ([WWDC19-256](https://developer.apple.com/videos/play/wwdc2019/256/)); iPhone X *hardware*-capable on iOS 16 but needs separate deployment target |
| WhisperKit tiny/base | A12/A13 matrix | Yes | **M–L** | [Models.swift](https://github.com/argmaxinc/WhisperKit/blob/main/Sources/WhisperKit/Core/Models.swift); streaming SLA on A13 unverified |
| On-device CTC/GOP | Unproven on A13 | Desired | **H–XL** | GOPT head tiny; AM is the bottleneck ([GOPT](https://arxiv.org/pdf/2205.03432)) |

**Hard parts:** L2 accent WER on small on-device models; possible ~60s SFSpeech task limit (docs vs WWDC conflict — must measure); locale assets not installed → false “supported.”

---

## Product-fit

Format 1 is diagnostic closed-vocab read-aloud for fluent-on-paper / anxious-in-speech L2 (`docs/product-spec.md`). Live marks are the prototype’s reason to exist; privacy/on-device is load-bearing (BIPA + latency), not polish (`research/literature-review.md`).

Success metric for this spike: **non-zero spoken tokens + live skip/extra/substitute while speaking** on device, with `engineKind` visible.

---

## Market-fit

| App | OS floor (cited) | Processing | How |
|-----|------------------|------------|-----|
| **ELSA Speak** | iOS 14+; needs network | **Cloud** | Proprietary ASR/scoring on ELSA servers ([device reqs](https://elsanow.freshdesk.com/en/support/solutions/articles/31000177726-supported-devices-system-requirements); [tech FAQ](https://elsaschool-support.freshdesk.com/en/support/solutions/articles/31000177613-faq-about-elsa-s-speech-analysis-technology); [SLATE 2023](https://www.isca-archive.org/slate_2023/anguera23_slate.pdf)) |
| **BoldVoice** | iOS 15.5+ | **Cloud** | AI feedback; GCP/Render subprocessors ([App Store](https://apps.apple.com/us/app/boldvoice-accent-training/id1567841142); [subprocessors](https://boldvoice.com/subprocessors)) |
| **Duolingo speak** | iOS 17+ | **Hybrid / platform ASR** | Apple/Google Speech; audio may leave device ([support](https://support.duolingo.com/hc/en-us/articles/204642264-My-microphone-is-not-working-How-can-I-fix-it); [privacy](https://www.duolingo.com/privacy)). DET uses Whisper server-side ([whitepaper](http://duolingo-testcenter.s3.amazonaws.com/media/resources/speaking-whitepaper.pdf)) |
| **Google Read Along / Bolo** | Android 8.1+ (APKMirror); web also | **On-device** | Voice analyzed on device / in browser; offline after download ([Play](https://play.google.com/store/apps/details?id=com.google.android.apps.seekh); [Android eng blog](https://android-developers.googleblog.com/2020/06/on-device-ML-design-insights.html); [web blog](https://blog.google/products-and-platforms/products/education/read-along-web/)) |
| **MS Reading Progress** | Teams Education | **Cloud** | Azure Speech mispronunciation APIs ([Verge](https://www.theverge.com/2021/5/4/22418855/microsoft-teams-reading-progress-fluency-feature)) |
| **Speechling** | iOS 11+ | **Human upload**, not live CAPT | Coach feedback ~24h ([App Store](https://apps.apple.com/us/app/speechling-learn-any-language/id1239983313)) |
| **Yoodli / Orai** | Web / iOS 16.6+ | **Cloud** | Delivery coaching, not phoneme CAPT |

**Differentiation opportunity:** Read-Along-class on-device closed-vocab live marks + later GOP — **not** competing on ELSA’s cloud phoneme moat in v1.

Active share of iPhone 11 and older: **credible precise % not found** (TelemetryDeck / Affinco are weak proxies). Treat “large chunk” as directional, not quantified.

---

## Cost & economics

- On-device-first: eng + device QA matrix; near-zero ASR COGS.
- Cloud CAPT (ELSA path): lower client eng, ongoing GPU/bandwidth COGS + dataset moat — **out of MVP policy** unless product reverses privacy stance.
- Dual-target iOS 16 (X) + iOS 26: highest opportunity cost; Moderator recommends against unless X is a hard business requirement.

---

## Risks (ranked)

| Risk | Severity | Raised by | Mitigation |
|------|----------|-----------|------------|
| Misdiagnose wiring bug as SpeechAnalyzer HW failure | High | Staff | Retest after subscribe + auth fixes |
| Floor contradiction: “iPhone 10” vs iOS 26 | High | Staff, ML, PM | Lock **iPhone 11+**; treat X as separate product decision |
| Silent cloud SF fallback vs privacy claims | High | Security | `requiresOnDeviceRecognition`; fail UX; no silent retry |
| On-device ASR ≠ pronunciation quality | High | GTM, ML | Slice A = alignment marks only; GOP later with honesty |
| L2 WER → false skips on anxious users | High | PM, ML | Constrained decoding / known script; measure on L2 samples |
| SF ~60s task limit | Med | ML | Chunk passages; verify on-device |
| A13 streaming Whisper thermal | Med | ML | Prefer Apple ASR live; Whisper batch fallback |
| Over-claiming older-phone TAM | Low–Med | GTM, Moderator | Don’t gate MVP on unmeasured share |

---

## Blind spots & conflicts (Moderator)

### Unknown unknowns
1. **Dictation asset / locale install state on the failing phone** — even after wiring fix, missing dictation language can yield empty recognition (SF 1101 class failures; [Stack Overflow / forums](https://stackoverflow.com/questions/75511637/receiving-error-domain-kafassistanterrordomain-code-1101-while-setting-sfspeec)).
2. **“iPhone 10” often means XR/XS in casual speech** — those max at **iOS 18**, still no iOS 26 / SpeechAnalyzer ([Macworld table](https://www.macworld.com/article/1811287/which-version-of-ios-can-my-iphone-run.html)). Floor language must name exact models.
3. **What kills this in 6 months:** shipping “on-device” while SF default still hits Apple servers, then a privacy complaint — Security’s red line.
4. **Android majority in English-learning app revenue** (~52% vs iOS ~38–41%, [Dataintelo](https://dataintelo.com/report/global-english-learning-app-market)) — expanding old iPhones may matter less than eventual Android for “large chunk of users.”
5. **App Review / Personal Team 7-day expiry** is operational noise, not architecture — but can look like “app broke” mid-test.

### Conflicts (do not average away)
- **GTM** says market winners are cloud CAPT with low OS floors; **Security + product-spec** say on-device-first is non-negotiable for Format 1. **Resolution for MVP:** stay on-device; accept we are closer to Read Along than ELSA for v1 quality claims.
- **PM** wants iPhone 11+ as *sequenced* expansion after iPhone 15 reliability; **user ask** wants X/11 usable soon. **Resolution:** 11 is the stretch goal after fix; X requires iOS ≤16 dual-target (explicit yes/no from product).
- **Staff** says fix before pivot; **user** asked for older architecture if HW is the issue. **Resolution:** HW is **not yet proven** as the issue; pivot after retest fails for non-wiring reasons.

### Over-consensus / rabbit holes
- Panel unanimously YELLOW — healthy; risk of shared “fix wiring first” tunnel if we never retest on device (assumption that fix is complete until measured).
- GTM competitor table is deep; don’t let ELSA cloud architecture become the default “should copy” without revisiting privacy.

---

## Open questions before committing

1. After redeploy: do live marks appear? What does Availability + report `engineKind` show?
2. Is the hard product floor **iPhone 11 / iOS 26** or **iPhone X / iOS 16**?
3. Is any cloud ASR acceptable as labeled opt-in, or never?
4. Target passage length (≤45 s vs multi-minute) for SF task limits?
5. Will we validate on a physical A13 device before marketing iPhone 11+?

---

## Architecture recommendation (post-retest)

```
Mic → AVAudioEngine
     → LiveTranscriptionEngine
           prefer: DictationTranscriber (iOS 26, if assets ready)
           else:   SFSpeechRecognizer + requiresOnDeviceRecognition
           optional later: WhisperKit tiny/base (batch / locale miss)
     → TokenAligner → live marks
     → (Slice B later) GOP on PCM — not Apple transcript
```

Update `docs/architecture-format1-prototype.md` device lock from **A18-class** to **iPhone 11+ (A13) with SF on-device fallback** once device retest confirms the wiring fix.

---

## Sources (grouped)

- **Code:** `ReadingSession.swift`, `LiveTranscriptionEngine.swift`, `TokenAligner.swift`, `ios/project.yml`, `ios/DEVICE_VALIDATION.md`
- **Apple:** WWDC19-256, WWDC25-277, `requiresOnDeviceRecognition` / `supportsOnDeviceRecognition` docs, iOS 26 model support
- **Competitors:** ELSA / BoldVoice / Duolingo / Read Along / Reading Progress citations in Market-fit table
- **ML:** WhisperKit Models.swift + memory docs; GOPT arXiv
