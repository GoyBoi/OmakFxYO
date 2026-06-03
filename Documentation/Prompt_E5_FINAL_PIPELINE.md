# Prompt E5: Final Pipeline Consolidation + Telemetry

**Date:** 2026-06-03  
**Scope:** Source marker consolidation, telemetry integrity, script alignment  
**Constitutional Authority:** AGENTS.md §VIII (Canonical Marker Naming), §V (State Mutation), §XIII (Telemetry Integrity), §XVI (Four-Gate Hierarchy)

---

## 1. Executive Summary

Full consolidation audit of 37 canonical markers defined in AGENTS.md §VIII against actual source code emission and script tracking. Three categories of work performed:

| Category | Count | Resolution |
|----------|-------|------------|
| Correctly emitted markers | 20 | Verified intact |
| Name mismatches (wrong variant used) | 3 | Renamed to canonical form |
| Completely missing from source emission | 14 | Added where logic exists; 7 noted as unimplemented gates |
| Double-counting bugs in scripts | 1 | Fixed (`[EXEC_TRIGGER]` counted twice) |
| Missing from script tracking | 24 | Added to both forensic and clinical engines |

---

## 2. Name Mismatch Fixes (Source Code)

### 2.1 `[BIAS_ALIGN]` → `[BIAS_ALIGNED]`

| File | Lines | Context |
|------|-------|---------|
| `core/BiasResolver.mqh` | 261, 272, 283 | `IsBiasAligned()` — success/reject log lines |
| `core/ClosureEngine.mqh` | 3146 | Bias check in pipeline gate evaluation |

**Added `[BIAS_MISALIGNED]`** at `BiasResolver.mqh:270,281` for the two signal-vs-bias conflict reject paths (BEAR signal with BULLISH bias, BULL signal with BEARISH bias). The NEUTRAL/PENDING case retains `[BIAS_ALIGNED]` with REJECT status (no directional edge to align against).

### 2.2 `[CISD_FAIL]` → `[CISD_FAILED]`

| File | Lines | Context |
|------|-------|---------|
| `core/ClosureEngine.mqh` | 1343, 1350, 1357, 1364, 1412, 1472 | LTF CISD validation function — data fetch errors and swing detection failures |

### 2.3 `[GUID_DUPLICATE_BLOCK]` → `[GUID_DUPLICATE_BLOCKED]`

| File | Lines | Context |
|------|-------|---------|
| `OmakFxYO.mq5` | 3749, 3771, 4149, 4182 | Position map ticket-attachment duplicate guards |

Note: Line 1149 already emitted the canonical `[GUID_DUPLICATE_BLOCKED]` form. The 4 other occurrences used the non-canonical `[GUID_DUPLICATE_BLOCK]` (missing `ED` suffix). All now consistent.

---

## 3. Missing Canonical Markers Added (Where Logic Exists)

### 3.1 Wick Rule — `[WICK_RULE_PASS]` / `[WICK_RULE_BLOCK]`

**File:** `core/ClosureEngine.mqh:496-531` — `ApplyWickFilter()`

Added canonical marker emissions at each branch:
- `[WICK_RULE_PASS]` for `wick_ratio < 0.3` (clean candle) and 0.3-0.8 range (moderate wick)
- `[WICK_RULE_BLOCK]` for `wick_ratio > 0.8` (extreme wick, reversal signature)

Both are InpEnableTrace-gated at DEBUG level to prevent log spam on per-tick evaluation.

**Deviation noted:** AGENTS.md §XVI Gate 2 defines the Wick Rule threshold at 50% (`wickRatio > 0.5` → block). The actual implementation uses 0.3 and 0.8 thresholds with a "SIGNAL LIBERATION PATCH" comment. The canonical markers are correctly named; the threshold discrepancy is a separate architectural issue.

### 3.2 Risk 2R Violation — `[RISK_2R_VIOLATION]`

**File:** `OmakFxYO.mq5:4970-4974` — `ValidateRiskGate()`

Added `[RISK_2R_VIOLATION]` alongside the existing `[RG_GATE_FAIL] INSUFFICIENT_RR` log line. Includes GUID, RR ratio, minRR, closure type, entry price, and stop loss.

### 3.3 State Mutation — `[STATE_MUTATION]`

**File:** `core/CoreTypes.mqh:556-567` — `SLockedSignal::Lock()`

Added `[STATE_MUTATION]` marker before each `executionMode` assignment. Logs: owner=LockedSignal, field=executionMode, old/new values, and reason (C2_ANTICIPATION / C3/C4_CONFIRMATION / UNKNOWN_CLOSURE).

AGENTS.md §V.3 requires `[STATE_MUTATION]` for every locked-field overwrite. This is the canonical mutation point. Further `[STATE_MUTATION]` sites can be added as needed.

---

## 4. Remaining Telemetry Gaps (Not Yet Implemented)

These 7 canonical markers correspond to **gate logic that does not yet exist** in the source code. They require feature implementation, not just marker emission:

| Marker | Missing Feature | AGENTS.md Reference |
|--------|----------------|---------------------|
| `[TSPOT_POI_MAPPED]` / `[TSPOT_POI_MISSING]` | Gate 4 T-Spot POI mapping engine | §XVI Gate 4, §XVII |
| `[TIME_FILTER_BLOCK]` / `[TIME_FILTER_PASS]` | HTF candle progress time-sensitivity filter | §XVII |
| `[SMT_DIVERGENCE_PASS]` / `[SMT_DIVERGENCE_FAIL]` | SMT Divergence detection for C2 | §XVII |
| `[HTF_TARGET_HIT]` / `[RESET_HTF_TARGET]` | HTF target hit monitoring during signal lifecycle | §XVIII |
| `[C3_DEMOTED_TO_C2]` | C3→C2 demotion path during Lock (demotion concept exists in AGENTS.md §V but `g_C3_RUNTIME_DISABLED` is not implemented) | §V |

**Status:** These markers are pre-registered in both the forensic engine PATTERNS dict (line 140-168) and backtest clinical extract (line 293-324). When the corresponding gate logic is implemented, markers will automatically be tracked without script changes.

---

## 5. Script Updates

### 5.1 `omak_forensic_engine.py`

| Change | Detail |
|--------|--------|
| Version bumped | `v1.0.0` → `v2.0.0` |
| PATTERNS dict | +24 new canonical marker regex patterns |
| `_funnel_stats` init | +24 new stat counters |
| `_process_line` | + V6 canonical marker batch loop (lines 1097-1115) |
| Double-count fix | Removed duplicate `execution_triggered` handler that incremented alongside `execution_trigger` — both matched the same `[EXEC_TRIGGER]` log line |

### 5.2 `backtest_clinical_extract.py`

| Change | Detail |
|--------|--------|
| Metrics dict | +24 new markers |
| `extract_metrics` | + V6 canonical marker detection block |
| Report section | Added "V6 Canonical Markers (AGENTS.md §VIII)" table |
| Telemetry version | `clinical-v1.0.0` → `clinical-v2.0.0` |

---

## 6. Telemetry Integrity (AGENTS.md §XIII)

All `[RISK_*]` and `[LOT_*]` markers verified against AGENTS.md §XIII:
- `[RISK_FLOOR_BLOCK]` — logs actual decision values (`minLot`, `slPts`, `equity`, `maxRiskPct`) with source label (`IsLotTradeable`)
- `[RISK_2R_VIOLATION]` — logs RR ratio, minRR, entry/sl prices used in comparison
- `[RG_GATE_FAIL] INSUFFICIENT_RR` — logs the actual RR value compared against the budget

No TELEMETRY_FRAUD violations detected.

---

## 7. Pipeline Consolidation Summary

### Signal Lifecycle: C2 Anticipation Path

```
C2 Closure Detected
  → [WICK_RULE_PASS/BLOCK]         (Gate 2 — ApplyWickFilter, InpEnableTrace-gated)
  → [ENTRY_CANDIDATE_SET]           (EvaluateC2Closure — T-Spot entry)
  → [C2_ACCEPTED]                   (EvaluateC2Closure)
  → [SIGNAL_LOCKED]                 (LockedSignal::Lock)
  → [STATE_MUTATION]                (executionMode = MODE_ANTICIPATION)
  → [GUID_ASSIGNED]                 (LockedSignal::Lock — sole authority)
  → STAGE_WAITING_FOR_POI
    → [CISD_CONFIRMED] / [CISD_FAILED]   (Gate 3 — POI touch detection)
    → [RG_GATE_PASS] / [RG_GATE_FAIL]    (ValidateRiskGate)
      → [RISK_2R_VIOLATION] if RR < minRR
      → [EXEC_TRIGGER]
        → [RISK_FLOOR_BLOCK] if lot calc fails
        → [ORDER_SENT]
```

### Signal Lifecycle: C3 Confirmation Path

```
C3 Closure Detected
  → [ENTRY_CANDIDATE_SET]           (EvaluateC3Closure — T-Spot entry)
  → [C3_ACCEPTED]                   (EvaluateC3Closure)
  → [SIGNAL_LOCKED]                 (LockedSignal::Lock)
  → [STATE_MUTATION]                (executionMode = MODE_CONFIRMATION)
  → [GUID_ASSIGNED]                 (LockedSignal::Lock — sole authority)
  → STAGE_WAITING_FOR_POI
    → [CISD_CONFIRMED]               (Gate 3)
    → [BIAS_ALIGNED] / [BIAS_MISALIGNED]   (Gate 1 — BiasResolver)
    → [RG_GATE_PASS] / [RG_GATE_FAIL]
      → [RISK_2R_VIOLATION] if RR < minRR
      → [EXEC_TRIGGER]
        → [ORDER_SENT]
```

---

## 8. Files Modified

| File | Changes |
|------|---------|
| `core/BiasResolver.mqh` | `[BIAS_ALIGN]`→`[BIAS_ALIGNED]` (3x), added `[BIAS_MISALIGNED]` (2x) |
| `core/ClosureEngine.mqh` | `[CISD_FAIL]`→`[CISD_FAILED]` (6x), `[BIAS_ALIGN]`→`[BIAS_ALIGNED]` (1x), added `[WICK_RULE_PASS]`/`[WICK_RULE_BLOCK]` (ApplyWickFilter) |
| `core/CoreTypes.mqh` | Added `[STATE_MUTATION]` markers to Lock() executionMode assignment |
| `OmakFxYO.mq5` | `[GUID_DUPLICATE_BLOCK]`→`[GUID_DUPLICATE_BLOCKED]` (4x), added `[RISK_2R_VIOLATION]` |
| `scripts/omak_forensic_engine.py` | +24 canonical marker patterns, stats, process-line handlers, version bump, EXEC_TRIGGER double-count fix |
| `scripts/backtest_clinical_extract.py` | +24 canonical markers in metrics, extract, and report sections, version bump |
| `Documentation/Prompt_E5_FINAL_PIPELINE.md` | This report |

---

## 9. Open Issues

1. **Wick Rule threshold mismatch**: AGENTS.md §XVI defines 50% threshold; code uses 0.3/0.8 thresholds with LIBERATION PATCH. Requires constitutional amendment or code alignment.
2. **Seven unimplemented gates** (T-Spot POI, Time Filter, SMT Divergence, HTF Target) — pre-registered in scripts, pending feature implementation.
3. **C3 Demotion path** (`g_C3_RUNTIME_DISABLED`) does not exist in source code — only in AGENTS.md §V as a constitutional concept.
4. **`[CISD_VALID]`** (ClosureEngine.mqh:1458,1466) is an active non-canonical marker. Consider renaming to `[CISD_CONFIRMED]` or documenting as a diagnostic extension.
5. **Script telemetry version** must be propagated into the MT5 EA's telemetry header line for automated version matching during forensic analysis.
