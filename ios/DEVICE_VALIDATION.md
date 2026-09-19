# Device validation notes — Reading, Slice A

**Format name:** **Reading** (alias Format 1). See `docs/formats.md`.

**Date:** 2026-09-19 (Pass 8 — stop drain + registration health)  
**Device:** Ibbi’s iPhone — build from `feat/reading-aurora-presence`  
**Bundle:** `com.speechapp.prototype.format1`

## Automated readiness (this pass)

| Check | Result |
|---|---|
| `swift test` in SpeechAppKit | **56/56 passed** |
| Device Debug build | Run from Xcode / `devicectl` after this pass |
| Live mic QA | **You — ~3 min on phone** (checklist below) |

## Manual checklist (Pass 8)

1. Start medium/full Harbor Morning. Aurora reacts to volume only.  
2. Speak continuously — caption should show **Keeping up with you** while occupancy advances.  
3. If you rush or ASR stalls, caption should switch to **I’m falling behind — slow a little or pause**.  
4. Read the full passage, then **Stop**. UI shows **Finishing recognition…** briefly (drain).  
5. Report match count should be much closer to a clean full read than the pre-drain ~25/94 failure (still not a pronunciation grade).  
6. Soft then loud speech — aurora amplitude changes; that still does **not** mean words matched.

## Known intentional gaps

- GOP always `.notAssessed` (Slice B)
- Live text place-markers stay retired (Pass 7)
- P95/P99 occupancy is a measured gate — keep sharing session logs after clean full reads
- SpanWalk / PassageSpan remain in kit but are not driven for UI
