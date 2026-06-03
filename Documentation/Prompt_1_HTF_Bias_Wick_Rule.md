# Prompt 1 — HTF Bias Engine & Agnostic Wick Rule

**Date:** 2026-06-03
**Scope:** Gate 1 (HTF Bias) + Gate 2 (50% Wick Rule) implementation
**Files changed:** `CoreTypes.mqh`, `ClosureEngine.mqh`

---

## Summary

Implemented the Agnostic (Direction-Aware) 50% Wick Rule as a hard Gate 2 in both `EvaluateC2Closure` and `EvaluateC3Closure`. Added the `expansionMode` boolean flag to `SClosureSignal` that downstream target logic reads to determine whether the candle supports expansion (target = HTF liquidity) or signals reversal (target = HTF Open).

HTF Bias Engine (Gate 1) is already handled by `BiasResolver.mqh` via `BranchContext.bias` — no structural changes were required there.

---

## Changes

### 1. `CoreTypes.mqh:310` — `SClosureSignal::expansionMode`

Added field `bool expansionMode` with `Reset()` initialization to `false`.

**Truth:** This is a structural truth owned by `ClosureEngine` (set during closure evaluation, immutable after signal lock).

### 2. `ClosureEngine.mqh` — Agnostic Wick Rule in `EvaluateC2Closure`

Inserted after sweep detection, before reversal closure check. Logic:

1. **Zero-range rejection:** `c2_high - c2_low <= 0.0` → `[WICK_RULE_BLOCK] C2_ZERO_RANGE`
2. **Doji rejection:** body < 10% of total range → `[WICK_RULE_BLOCK] C2_DOJI`
3. **Dominant wick computation:** For bullish sweep → `lowerWick` is dominant. For bearish sweep → `upperWick` is dominant.
4. **Expansion assignment:** `expansionMode = (dominantWick < totalRange * 0.5)`
5. **Canonical markers:** `[WICK_RULE_PASS] C2_EXPANSION` or `[WICK_RULE_BLOCK] C2_REVERSAL`

### 3. `ClosureEngine.mqh` — Agnostic Wick Rule in `EvaluateC3Closure`

Inserted after direction confirmation (bullish/bearish), before signal struct population. Uses same logic as C2 but reads direction from the `bullish` boolean.

**Canonical markers:** `[WICK_RULE_PASS] C3_EXPANSION` or `[WICK_RULE_BLOCK] C3_REVERSAL`

---

## Gate 2: Decision Tree

```
                     ┌─────────────────────┐
                     │  Structure TF Candle │
                     │  (H1 / H4)           │
                     └──────────┬──────────┘
                                │
                    ┌───────────┴───────────┐
                    │   totalRange > 0 ?    │
                    └───────────┬───────────┘
                    NO          │          YES
              ┌─────────────────┘                  
              │                                    
    ┌─────────┴──────────┐                ┌────────┴────────┐
    │ [WICK_RULE_BLOCK]  │                │ body >= 10%     │
    │ C2/C3_ZERO_RANGE   │                │ of totalRange?  │
    └────────────────────┘                └────────┬────────┘
                                    NO             │          YES
                              ┌─────────────────────┘
                              │                       
                    ┌─────────┴──────────┐    ┌────────┴────────┐
                    │ [WICK_RULE_BLOCK]  │    │ Compute         │
                    │ C2/C3_DOJI         │    │ dominantWick    │
                    └────────────────────┘    │ (direction-     │
                                              │  aware)         │
                                              └────────┬────────┘
                                                        │
                                            ┌───────────┴───────────┐
                                            │ dominantWick < 50%   │
                                            │ of totalRange?       │
                                            └───────────┬───────────┘
                                              YES       │        NO
                                        ┌───────────────┘  ┌───────────────┐
                                        │ expansionMode    │ expansionMode │
                                        │ = true           │ = false       │
                                        │ [WICK_RULE_PASS] │ [WICK_RULE_   │
                                        │ C2/C3_EXPANSION  │ BLOCK]        │
                                        └──────────────────┘ C2/C3_REVERSAL│
                                                             └───────────────┘
```

---

## Expansion Mode Semantics

| `expansionMode` | Meaning | Downstream Effect |
|----------------|---------|-------------------|
| `true` | Dominant wick < 50% — candle supports expansion | Target = HTF liquidity zone. Normal TP projection. |
| `false` | Dominant wick >= 50% — reversal signature | Target = HTF Open. Reversal-mode trading. |

---

## Marker Inventory

| Marker | Source | Condition |
|--------|--------|-----------|
| `[WICK_RULE_BLOCK] C2_ZERO_RANGE` | EvaluateC2Closure | `c2_high - c2_low <= 0` |
| `[WICK_RULE_BLOCK] C2_DOJI` | EvaluateC2Closure | Body < 10% of range |
| `[WICK_RULE_PASS] C2_EXPANSION` | EvaluateC2Closure | Dominant wick < 50% |
| `[WICK_RULE_BLOCK] C2_REVERSAL` | EvaluateC2Closure | Dominant wick >= 50% |
| `[WICK_RULE_BLOCK] C3_ZERO_RANGE` | EvaluateC3Closure | `c3_high - c3_low <= 0` |
| `[WICK_RULE_BLOCK] C3_DOJI` | EvaluateC3Closure | Body < 10% of range |
| `[WICK_RULE_PASS] C3_EXPANSION` | EvaluateC3Closure | Dominant wick < 50% |
| `[WICK_RULE_BLOCK] C3_REVERSAL` | EvaluateC3Closure | Dominant wick >= 50% |

---

## Governance Compliance

| Rule | Status |
|------|--------|
| §VII: No ATR-based execution | Compliant — wick rule uses raw price, not ATR |
| §VII: No silent mode substitution | Compliant — `expansionMode` is structural, not executionMode |
| §VIII: Canonical marker naming | All markers use `[DOMAIN_VERB]` form |
| §XVI Gate 2: 50% Wick Rule | Implemented with direction-aware dominant wick |
| §XVII: Wick rule applies independently per candle | Compliant — computed per candle in each `EvaluateC*Closure` |
| §IX-3: Report on mismatch | No file mismatches encountered |

---

## Files Modified

| File | Lines | Change |
|------|-------|--------|
| `core/CoreTypes.mqh` | 319, 357 | Added `expansionMode` field + Reset initialization |
| `core/ClosureEngine.mqh` | ~1566–1599 | Agnostic Wick Rule block in `EvaluateC2Closure` |
| `core/ClosureEngine.mqh` | ~1843–1884 | Agnostic Wick Rule block in `EvaluateC3Closure` |

---

## Unresolved / Future

- `expansionMode` downstream consumption (target selection in `TargetEngine.mqh`) is NOT yet implemented. The flag is set and logged but not read by any downstream logic.
- `BiasResolver.mqh` already handles Gate 1 bias. No changes needed here unless the Next Day/Week Model implementation is revised.
