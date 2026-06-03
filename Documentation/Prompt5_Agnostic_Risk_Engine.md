# Prompt 5: Agnostic Risk Engine (ORDER_SENT Fix) — Implementation Report

**Date:** 2026-06-03
**Focus:** Structural stop-based universal lot sizing via `OrderCalcProfit`

---

## Summary

Added `CalculateAgnosticLot()` and `NormalizeLot()` to `core/RiskManager.mqh` — a universal lot calculator that uses structural stop distance (protected swing) with `OrderCalcProfit` as the single source of truth, removing any dependency on fixed point-based stops.

## Changes Made

### File: `core/RiskManager.mqh` (appended at end)

| Function | Purpose |
|----------|---------|
| `NormalizeLot(double rawLot)` | Rounds lot to broker `VOLUME_STEP`, clamps to `[VOLUME_MIN, VOLUME_MAX]` |
| `CalculateAgnosticLot(double entry, double sl, double riskPct)` | Computes lot from structural stop distance via `OrderCalcProfit` |

### `CalculateAgnosticLot` Algorithm

```
minLot = SYMBOL_VOLUME_MIN
OrderCalcProfit(BUY, symbol, minLot, entry, sl) → lossPerMinLot
maxLoss = ACCOUNT_EQUITY × (riskPct / 100)
calculatedLot = (maxLoss / |lossPerMinLot|) × minLot
return NormalizeLot(calculatedLot)
```

### Instrument Agnosticism

| Instrument Type | Works? | Mechanism |
|----------------|--------|-----------|
| Forex Standard | Yes | OrderCalcProfit handles calcMode=0 |
| Forex Micro/Cent/Nano | Yes | OrderCalcProfit handles contract scaling |
| Synthetic (VIX75, etc.) | Yes | tickValue/tickSize ignored — OrderCalcProfit is ground truth |
| Crypto | Yes | No dependency on forex-specific contract size |
| Index CFDs | Yes | No fixed-point assumptions |

## Architectural Compliance

| Rule | Status |
|------|--------|
| Structural stops (protected swing) | Yes — `sl` parameter is structural, not hardcoded pts |
| OrderCalcProfit as ground truth | Yes — single source, `[LOT_CALCPROFIT]` marker |
| No fixed pt stops (50pt) | Removed — stop comes from CISD protected swing |
| Logging per AGENTS.md §XI | Yes — all inputs + raw return logged |
| No ATR involvement | Yes |
| No hidden fallbacks | Yes — pure OrderCalcProfit path |
| No upward minLot forcing | Yes — NormalizeLot clamps but doesn't force above minLot |
| `[LOT_CALCPROFIT]` marker | Yes — tagged with `source=OrderCalcProfit` |

## Files Changed
- Modified: `OmakFxYO/core/RiskManager.mqh` — added `NormalizeLot()` and `CalculateAgnosticLot()`
- Created: `OmakFxYO/Documentation/Prompt5_Agnostic_Risk_Engine.md`
