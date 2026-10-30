# Orator — Reading iOS Prototype (Slice A)

**Reading** (alias Format 1) — see `docs/formats.md`.

Passage read-aloud prototype: live skip / extra / substitute marks, stall nudge, struggle-led next passages, report-only speech rate. **No GOP / phoneme scoring yet** (explicitly stubbed as not-assessed).

## Requirements

- Xcode 26+
- iOS 26 device or Simulator. Public floor is iOS 26 on iPhone 11 and newer. There is no iOS 25.
- Paid team `Q2Z32YFFGP` signed into Xcode. Sign in with Apple is on the app target.

## Open & run

```bash
cd ios
xcodegen generate   # regenerates SpeechApp.xcodeproj from project.yml
open SpeechApp.xcodeproj
```

1. Select **Ibbi’s iPhone** (or any Simulator) as the run destination.
2. Signing is team `Q2Z32YFFGP`. In Xcode → Settings → Accounts, that team has to be signed in. If Xcode asks, enable **Developer Mode** on the phone and trust the developer certificate under **Settings → General → VPN & Device Management**.
3. Hit **Run**.

### First launch flow

1. **Consent** — mic / on-device processing disclosure  
2. **Availability** — probes `DictationTranscriber`; downloads assets if needed; falls back to on-device `SFSpeechRecognizer` if unsupported  
3. **Reading** — karaoke cursor + occupancy marks; stall nudge after ~4.5s silence  
4. **Report** — match/skip/extra/swap counts + self-referential speech rate; GOP note says not assessed  

## Package tests (no device needed)

```bash
cd ios/Packages/SpeechAppKit
swift test
```

## Layout

- `App/` — SwiftUI shell  
- `Packages/SpeechAppKit/` — alignment, audio, stall, ledger, passages, session orchestration  
- `docs/architecture-format1-prototype.md` — locked architecture  

## Hardware note

`DictationTranscriber` is preferred. If `AssetInventory` reports unsupported on a given chip, the app uses **SFSpeechRecognizer on-device** and shows that on the Availability screen — same UI, older engine.
