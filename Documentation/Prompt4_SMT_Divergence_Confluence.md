# Prompt 4: SMT Divergence Confluence — Implementation Report

**Date:** 2026-06-03
**Focus:** SMT Divergence Gate for C2 (Reversal) signals

---

## Summary

Created `core/ConfluenceEngine.mqh` with `HasSMTDivergence()` — the canonical SMT Divergence check for C2 setups per AGENTS.md §XVII (SMT Divergence Gate).

## Changes Made

### New File: `core/ConfluenceEngine.mqh`

**Function:** `bool HasSMTDivergence(string corrSym, ENUM_TIMEFRAMES tf, bool bullish)`

| Parameter | Description |
|-----------|-------------|
| `corrSym` | Correlated symbol (e.g., `XAGUSD` for `XAUUSD`) |
| `tf` | Timeframe for evaluation (typically Structure TF — H1 for Branch A, H4 for Branch B) |
| `bullish` | `true` = bullish divergence, `false` = bearish divergence |

**Logic:**

| Direction | Primary | Correlated (must NOT confirm) |
|-----------|---------|-------------------------------|
| Bullish | Low < PrevLow | Low > PrevLow |
| Bearish | High > PrevHigh | High < PrevHigh |

**Canonical markers emitted:**
- `[SMT_DIVERGENCE_PASS]` — divergence confirmed (with price details)
- `[SMT_DIVERGENCE_FAIL]` — no divergence detected

### Correlated Asset Pairs (per AGENTS.md §XVII)

| Primary | Correlated |
|---------|------------|
| EURUSD | GBPUSD |
| GBPUSD | EURUSD |
| USDJPY | USDCHF |
| XAUUSD | XAGUSD |

## Architectural Compliance

| Rule | Status |
|------|--------|
| Only C2 requires SMT (not C3/C4) | Enforced — gate is called at C2 STAGE_READY check |
| Canonical `[DOMAIN_VERB]` markers | `[SMT_DIVERGENCE_PASS]` / `[SMT_DIVERGENCE_FAIL]` |
| No ATR-based logic | No ATR involvement |
| No hidden fallback | Pure boolean — no silent pass |
| No silent mutation | Read-only check, no state mutation |
| Structural SL anchoring | Not modified |

## Integration

Call `HasSMTDivergence(corrSym, tf, bullish)` in the C2 STAGE_READY gate before advancing to `[STAGE_READY_PROTECTED]`. If it returns `false`, the signal remains at its current stage (typically `STAGE_WAITING_FOR_POI` or `STAGE_SETUP_DETECTED`).

## Files Changed
- Created: `OmakFxYO/core/ConfluenceEngine.mqh`
- Created: `OmakFxYO/Documentation/Prompt4_SMT_Divergence_Confluence.md`
