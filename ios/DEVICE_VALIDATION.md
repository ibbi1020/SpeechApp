# Device validation notes — Reading, Slice A

**Format name:** **Reading** (alias Format 1). See `docs/formats.md`.

**Date:** 2026-09-06 (final assignment check)  
**Device:** Ibbi’s iPhone (`00008120-001214821E680032`) — iPhone 15, free Personal Team signing  
**Bundle:** `com.speechapp.prototype.format1`

## Automated readiness (this pass)

| Check | Result |
|---|---|
| `swift test` in SpeechAppKit | **25/25 passed** |
| Device Debug build | **SUCCEEDED** |
| Install via `devicectl` | **SUCCEEDED** (reinstalled 2026-09-06) |
| App present on device | **Yes** (v0.1.0) |
| Launch via `devicectl` | Attempted — if blocked, trust Developer certificate (below) |

## Assignment plan todos

All plan todos are complete except the **human** half of live-mic QA (you must speak through one passage once). Code/build/install side of `device-validation` is done.

| Todo | Status |
|---|---|
| scaffold … ui-screens … fixtures | Done |
| device-availability-spike | Done (Availability screen + SFSpeech fallback) |
| device-validation (build/install) | Done |
| device-validation (manual live mic) | **You — ~2 min on phone** |

## DictationTranscriber availability (spike)

In-app **Availability** calls `LiveTranscriptionEngine.checkAvailability()` / `AssetInventory` for a `DictationTranscriber` probe.

| Outcome | Meaning |
|---|---|
| Ready / Needs download | Prefer SpeechAnalyzer + DictationTranscriber |
| Unsupported | Fall back to SFSpeechRecognizer `requiresOnDeviceRecognition = true` and surface that on-screen |

## If launch is blocked (free provisioning)

1. Open SpeechApp once (or Settings).
2. **Settings → General → VPN & Device Management** → trust your Apple ID.
3. Enable **Developer Mode** if prompted; reboot.
4. Re-open SpeechApp, or Run again from Xcode.

## Manual checklist (final human gate)

Pedagogy update: live UI is **karaoke / progress only** (“with you,” not graded); skip / extra / substitute appear on the **report**, not painted mid-read.

1. Consent → Continue  
2. Availability resolves (ready, downloading, or SFSpeech fallback)  
3. Start a passage; speak it — cursor / provisional highlight advances  
4. Stay silent ~5s → stall nudge; dismiss  
5. Stop → report shows matched / skipped / extra / swapped counts (not all-skipped if you spoke) + syll/min + GOP not-assessed  
6. **Share session log** on the report screen (AirDrop / Files) — JSONL under `Documents/SpeechAppLogs/`  
7. Read next → struggle-led pick if ledger has misses  

### Capturing a caret-lag log (for freeze / catch-up)

1. Pick a longer passage.  
2. Speak **continuously** without long pauses for ~20–40s.  
3. Stop. On **Your reading**, tap **Share session log**.  
4. Send the `.jsonl` file. Look for clusters of `caret_freeze` while speaking, then `asr_burst` after you pause — that pattern means pipeline backup, not “hardware can’t keep up.”  

## Known intentional gaps (not blockers for Slice A)

- GOP always `.notAssessed` (Slice B)
- Passage catalog is draft placeholders (10 passages)
- Free provisioning expires in 7 days — re-Run from Xcode to renew
- Live evaluative marks deferred to report (post literature/empathy lock)
