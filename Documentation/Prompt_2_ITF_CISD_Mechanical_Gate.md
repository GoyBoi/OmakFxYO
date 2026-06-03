# Prompt 2 — ITF CISD (Mechanical Structure Gate)

**Focus:** Implement the Mechanical CISD check to confirm the HTF bias, replacing the swing-extreme-based algorithm with the initiating-candle-opening-price trigger.

**Constitutional Authority:** AGENTS.md §XVI Gate 3, §XVII Mechanical CISD

---

## File Modified

`OmakFxYO/core/StructuralStateEngine.mqh` — `SSE_DetectCISD()` (lines 733–875)

---

## Algorithm Change

| Aspect | Old (removed) | New (installed) |
|--------|---------------|-----------------|
| Trigger level | Swing extreme (low/high) | Opening price of the **initiating candle** of the consecutive same-direction close series |
| Check scope | Any bar after swing extreme | Current bar only (bar 0) |
| Series logic | Single extreme search | Walks backward from swing extreme through consecutive same-direction closes to find the first (oldest) candle in the series |

---

## Logic Detail

### Bullish (DIRECTION_BUY)
1. Find swing low (lowest low in `[1..maxBars-1]`)
2. Walk backward from `swingIdx` while `close < open` (consecutive down-closes); the farthest-back down-close is the **initiating candle**
3. `seriesOpen = rates[firstDownIdx].open`
4. CISD confirmed if `rates[0].close > seriesOpen` → `[CISD_CONFIRMED]`

### Bearish (DIRECTION_SELL)
1. Find swing high (highest high in `[1..maxBars-1]`)
2. Walk backward from `swingIdx` while `close > open` (consecutive up-closes); the farthest-back up-close is the **initiating candle**
3. `seriesOpen = rates[firstUpIdx].open`
4. CISD confirmed if `rates[0].close < seriesOpen` → `[CISD_CONFIRMED]`

---

## Canonical Markers

| Marker | When | Logged Data |
|--------|------|-------------|
| `[CISD_CONFIRMED]` | CISD trigger condition met | direction, seriesOpen, close, swingIdx, firstDownIdx/firstUpIdx |
| `[CISD_FAILED]` | CISD trigger condition not met | direction, seriesOpen, close (or reason if no swing found) |
| `[CISD_DETECT]` (no marker prefix) | Insufficient bars | tf, copied count (LOG_LEVEL_DEBUG only) |

---

## Diff Summary

- Removed: swing-extreme-based CISD (comparing close against swing low/high across any subsequent bar)
- Added: mechanical CISD (comparing current close against opening price of the initiating candle of the consecutive same-direction close series)
- Comment block updated to document the mechanical CISD rule per AGENTS.md §XVI Gate 3

---

## Verification

- No new files created — existing `SSE_DetectCISD` function signature preserved
- All callers continue to work with same signature
- Compilation and backtest deferred to manual user action per Rule 8
