# DEEP FORENSIC AUDIT REPORT — OmakFxYO

**Date:** 2026-06-03  
**Session:** June 03 Backtest — GOLDmicro, $100 equity  
**Survival Rate:** 0.0% (1,613 C3 locked, 0 reached STAGE_READY → EXEC_TRIGGER → ORDER_SENT)

---

## TABLE OF CONTENTS

1. [Block 1: Affordability Blocker — The $100 GOLDmicro Death Spiral](#block-1-affordability-blocker)
2. [Block 2: C3/C4 Pathway Extinction](#block-2-c3c4-pathway-extinction)
3. [Block 3: READY_PROTECTED Deadlock + PERMANENT_SKIP Unreachable](#block-3-ready_protected-deadlock)
4. [Block 4: TTrades Mechanical Rule Violations](#block-4-ttrades-mechanical-rule-violations)
5. [Summary of Structural Death Points](#summary-of-structural-death-points)

---

## BLOCK 1: Affordability Blocker

### 1.1 Init-Time Risk Floor Underestimates Actual SL

**File:** `core/RiskManager.mqh:105`  
**Death Point:** `DetectSymbolRiskFloor(testSLPoints = 100)` — hardcoded default

The function tests affordability at **100 points** of SL distance:
```
testSL = testPrice - (testSLPoints * spFloor.point);  // line 132
```

But actual structural SL distance from C2 anchor (c2_low for buys, c2_high for sells) averages **~235 points** for GOLDmicro. The init-time check uses 100 points, passes, and the EA initializes. When execution tries the real 235-point SL, risk exceeds budget.

**Constitutional Violation:** AGENTS.md §XII — `minRequiredFactor` computed from an unrealistically low testSL (100pt vs 235pt actual) produces a false sense of affordability.

### 1.2 g_minSLPoints Default Mismatch

**File:** `OmakFxYO.mq5:351`  
**Death Point:** `double g_minSLPoints = 50.0`

Default is 50 points. The test in `DetectSymbolRiskFloor` uses 100 points. The actual structural SL is ~235 points. Three different SL distances for three different purposes. None match.

### 1.3 EARLY_MINLOT_GUARD Path — hasFailedRG Set But PERMANENT_SKIP Never Reached

**File:** `OmakFxYO.mq5:6048-6063`  
**Death Point:** IsLotTradeable() fails for minLot=0.10 at $100 equity

```cpp
Line 6048: if(InpMaxMinLotRiskPercent > 0.0 && checkMinLot > 0.0 &&
Line 6049:    !IsLotTradeable(slDistancePoints, tickValue, checkMinLot,
...
Line 6060:    g_activeSignal[idx].hasFailedRG = true;    // ← Set correctly
Line 6062:    ClearSignalByGUID(ctx.branch, execSig.m_guid, "RISK_MINLOT_REJECT");
```

`hasFailedRG` IS set at line 6060. `ClearSignalByGUID` IS called at line 6062.  

**But ClearSignalByGUID's ZOMBIE bypass (line 1225-1226) catches this signal FIRST:**

```cpp
Line 1225: if(g_activeSignal[i].executionAttempts > 8 ||
Line 1226:    (g_activeSignal[i].stage == STAGE_READY && g_activeSignal[i].hasFailedRG))
Line 1228:    LogPrint("[ZOMBIE_CLEARED] ...");
Line 1238:    g_hasActiveSignal[i] = false;
Line 1239:    g_activeSignal[i].Reset();
Line 1243:    return;   // ← RETURNS BEFORE PERMANENT_SKIP CODE
```

The ZOMBIE_CLEARED path (lines 1225-1243) processes the signal and **returns** before the PERMANENT_SKIP check at lines 1259-1264. The PERMANENT_SKIP code is **structurally unreachable** from affordability failures.

**Effect:** Signal is cleared, slot freed. New signal is detected → locked → promoted → fails → ZOMBIE_CLEARED → repeat. Infinite loop with slot reassignment.

**Log Evidence:** Same GUID pattern (2714, 2713) cycling through EXEC_TRIGGER → RISK_FLOOR_BLOCK repeatedly for 30+ minutes.

### 1.4 CALCULATE_LOT_SIZE_FAILED Path — No ClearSignalByGUID At All

**File:** `OmakFxYO.mq5:6071-6083`  
**Death Point:** `rawLot = 0.0` after `CalculateRiskLot` returns 0

```cpp
Line 6071: if(rawLot <= 0.0)
Line 6073:    LogPrint("[RISK_FLOOR_BLOCK] ... reason=CALCULATE_LOT_SIZE_FAILED ...");
Line 6079:    LogPrint("[EXEC_GATE] Lot=0 ...");
Line 6083:    continue;   // ← NO ClearSignalByGUID, NO hasFailedRG set
```

No `hasFailedRG = true` is set. No `ClearSignalByGUID` is called. The signal stays in `STAGE_READY` indefinitely. Every tick the PERSISTENT EXECUTION SCAN finds this signal, tries ExecutionGatePass, fails at `CalculateRiskLot` returning 0, and hits `continue` again.

**Log Evidence:** 33,431+ `[RISK_FLOOR_BLOCK] reason=CALCULATE_LOT_SIZE_FAILED` markers for the same two GUIDs over 30+ minutes.

### 1.5 Log Sample Analysis

From `Raw_log_sample.md`:

```
[RISK_FLOOR_BLOCK] GUID=1719612000002714 | projectedRisk=1.20 | exceedsBudget=0.60 | ratio=2.00 | desiredLot=0.1000 | source=OrderCalcProfit
[RISK_FLOOR_BLOCK] GUID=1719612000002714 | reason=CALCULATE_LOT_SIZE_FAILED | rawLot=0.000000 | riskPct=0.6000 | equity=100.00 | entry=2325.63 | sl=2325.51
```

**Key numbers:**
- Equity: $100.00
- minLot: 0.10 (GOLDmicro standard)
- SL distance: 12 points (2325.63 − 2325.51 = 0.12, point=0.01)
- Projected risk at minLot: $1.20
- Risk budget: $0.60 (0.6%) / $1.00 (1.0%)
- `desiredLot=0.1000` — broker minimum lot applied as forced lot size
- `rawLot=0.000000` — lot calculation returned 0

**Root Cause:** On $100 equity with minLot=0.10 and SL=235pt (structural), `OrderCalcProfit` projects ~$23.50 risk, far exceeding the 0.6-1.0% budget ($0.60-$1.00). `CalculateRiskLot` computes `riskAmount / (slPoints * tickValue)` = `$0.60 / (235 * tickValue)` ≈ 0.005 lot. This is below minLot=0.10. `StabiliseLot` (LotStabiliser.mqh:8) rounds 0.005 → 0.0 (line 23-27). Zero lot, CALCULATE_LOT_SIZE_FAILED.

---

## BLOCK 2: C3/C4 Pathway Extinction

### 2.1 C3 Entry Price Uses Fixed Midpoint, Not Zone-Scanned PD Array

**File:** `core/ClosureEngine.mqh:1941-1943`

```cpp
double tSpotC3 = (c3_high + c3_low) / 2.0;
signal.entry_price = (tSpotC3 > 0.0) ? tSpotC3 : currentPriceC3;
```

**Death Point:** C3 entry_price is set to the T-Spot midpoint (fixed), NOT scanned from a PD Array within the T-Spot zone per Gate 4.

**Constitutional Violation:** AGENTS.md §XVI Gate 4: "Entry price is NOT set to a fixed midpoint. The T-Spot is a zone... If no PD Array exists, the signal must wait (STAGE_WAITING_FOR_POI) — it must not use a fixed midpoint as fallback."

The `EE_MapPOI()` function exists in `ExecutionEngine.mqh:287` and scans the T-Spot zone for PD Arrays (Breaker Block, FVG, Order Block, Inversion FVG). It is never called for C3 signals at detection time. The C3 entry price is set directly in `EvaluateC3Closure` to the midpoint, bypassing Gate 4 entirely.

**Effect:** C3 signals lock with an entry price that is structurally independent of PD Array analysis. This means:
- Entry may be outside the valid T-Spot zone defined by Gate 4
- NO `[TSPOT_POI_MAPPED]` or `[TSPOT_POI_MISSING]` marker is ever emitted for C3 signals
- The SL distance is computed from this midpoint, which may be extremely close to the C2 anchor (as seen in the log: 12 points)

### 2.2 C4 Requires C3 Reference Data But C3 Pipeline Is Broken

**File:** `core/ClosureEngine.mqh:2001-2107`

`EvaluateC4Closure` at line 2001 requires c3_high/c3_low > 0.0 (lines 2022-2023) and checks continuous expansion from C3 range (lines 2032-2043).

**Death Point:** Since C3 signals are locked with a midpoint entry price that fails affordability, C3 never executes. Without executed C3 trades, there is no position to manage with C4 continuation. The C4 pathway traces back to a C3 base that never materializes.

**Constitutional Note:** AGENTS.md §III allows C4 from C2 extremes when C3 is disabled (`g_C3_RUNTIME_DISABLED`). However, the code at `EvaluateC4Closure:2029-2030` uses C3 as the hard reference:
```cpp
double refHigh = c3_high;
double refLow  = c3_low;
```
The C2 fallback path for C4 is not implemented in `EvaluateC4Closure`.

### 2.3 C3 Wick Rule Logs Block But Does Not Reject Signal

**File:** `core/ClosureEngine.mqh:1904-1918`

```cpp
signal.expansionMode = (c3_dominantWick < c3_wickTR * 0.5);

if(signal.expansionMode)
   LogPrint("[WICK_RULE_PASS] ...");
else
   LogPrint("[WICK_RULE_BLOCK] ...");   // ← LOGS BLOCK BUT FALLS THROUGH
```

**Death Point:** The wick rule evaluates `expansionMode` and logs `[WICK_RULE_BLOCK]` when dominant wick ≥ 50%, but execution falls through to line 1921+ where `signal.valid = true` is set and the signal is accepted.

**Constitutional Violation:** AGENTS.md §XVI Gate 2: "If wickRatio > 0.5: the candle is a reversal signature. It does NOT support expansion." The gate fails to reject the signal.

**Expected behavior:** `return false` when `!signal.expansionMode`.

---

## BLOCK 3: READY_PROTECTED Deadlock

### 3.1 PERMANENT_SKIP Structurally Unreachable

**File:** `OmakFxYO.mq5:1259-1264`  
**Death Point:** ClearSignalByGUID's PERMANENT_SKIP check

```cpp
Line 1259: // PROMPT_E4: PERMANENT_SKIP for affordability failures
Line 1260: if(StringFind(reason, "AFFORDABILITY") >= 0 ||
Line 1261:    StringFind(reason, "LOT_NOT_TRADEABLE") >= 0 ||
Line 1262:    StringFind(reason, "MINLOT") >= 0)
Line 1264:    AddPermanentSkip(_Symbol, reason + " | GUID=" + IntegerToString(guid));
```

This code IS correctly implemented. But it is **structurally unreachable** from all affordability failure paths:

| Path | Reason String | Reachable? | Why |
|------|--------------|------------|-----|
| EARLY_MINLOT_GUARD (line 6062) | `"RISK_MINLOT_REJECT"` | **NO** | ZOMBIE_CLEARED at line 1225-1243 catches hasFailedRG=true before PERMANENT_SKIP code |
| CALCULATE_LOT_SIZE_FAILED (line 6083) | N/A | **NO** | `continue` at line 6083 — no ClearSignalByGUID called at all |
| LOT_ZERO_POST_STABILISATION (line 6116) | `"LOT_ZERO_POST_STABILISATION"` | **NO** | Contains "LOT" but not "MINLOT" — StringFind check fails |

**Log Evidence:** 0 `[PERMANENT_SKIP]` markers across the entire 30+ minute backtest session, despite thousands of affordability failures.

### 3.2 ZOMBIE_CLEARED Priority Over PERMANENT_SKIP

**File:** `OmakFxYO.mq5:1225-1243` vs `OmakFxYO.mq5:1259-1264`

The ZOMBIE detection at line 1225-1226:
```cpp
(g_activeSignal[i].stage == STAGE_READY && g_activeSignal[i].hasFailedRG)
```
catches ANY signal with `hasFailedRG=true` while in `STAGE_READY`, processes it, and returns at line 1243. The PERMANENT_SKIP check at line 1259 is never executed.

**Solution:** PERMANENT_SKIP check must be moved to BEFORE the ZOMBIE check, or the ZOMBIE path must call AddPermanentSkip before clearing.

### 3.3 CALCULATE_LOT_SIZE_FAILED Infinite Loop

**File:** `OmakFxYO.mq5:6071-6083`

No hasFailedRG, no ClearSignalByGUID. Signal lives in STAGE_READY forever. Every tick:

1. PERSISTENT EXECUTION SCAN (line 6366) finds signal at STAGE_READY
2. ZOMBIE check (line 6376): `executionAttempts=0, hasFailedRG=false` → no
3. RG retry check (line 6400): hasFailedRG=false → skipped
4. Tradeability gate (line 6411): g_symbolUntradeable=false (or not checked)
5. RG evaluate (line 6440): hasFailedRG=false → runs RG_EvaluateAndGate → fails
6. hasFailedRG = true (line 6444) — NOW the signal is marked
7. Next tick: ZOMBIE check catches hasFailedRG=true → clears signal → slot freed
8. New signal detected → re-locked → re-promoted → re-fails → infinite loop

**This creates ~33,431 log lines for 2 signals over 30 minutes.**

---

## BLOCK 4: TTrades Mechanical Rule Violations

### 4.1 Wick Rule Threshold Mismatch (Liberation Patch)

**File:** `core/ClosureEngine.mqh:497-534` — ApplyWickFilter

| AGENTS.md §XVI Gate 2 | Code Implementation |
|------------------------|-------------------|
| Wick threshold: **0.5 (50%)** | `ApplyWickFilter` uses `0.3` and `0.8` thresholds |
| `wickRatio > 0.5` → BLOCK | `wickRatio < 0.3` → PASS (clean) |
| | `wickRatio > 0.8` → BLOCK (extreme) |
| | `0.3 < wickRatio < 0.8` → PASS with penalty |

**Constitutional Violation:** The "SIGNAL LIBERATION PATCH" (line 502 comment) relaxes the 50% threshold to 80% for the upper bound. Signals with wicks between 50-80% that should be reversal-blocked are passed as "moderate wick, allowed with penalty."

**File:** `core/C2WickFilter.mqh:78-113` — ValidateC2ForAnticipation  
**Config:** `CoreTypes.mqh:703` — `g_trueTTradesConfig.maxC2WickPercent = 0.6`

C2 wick validation uses `maxC2WickPercent = 0.6` (60%), not the constitutionally defined 50%.

### 4.2 Gate 4 Bypass for C3 (No PD Array Scan)

**File:** `core/ClosureEngine.mqh:1941-1943` vs `core/ExecutionEngine.mqh:287-346`

C3 entry price is set to `(c3_high + c3_low) / 2.0` (midpoint) at detection time. The `EE_MapPOI()` function in ExecutionEngine.mqh scans the T-Spot zone for PD Arrays (Breaker Block, FVG, Order Block, Inversion FVG) with the preferred PD Array `entry_price` — but it is only called for C2 signals, not for C3.

**Effect:** C3 bypasses Gate 4 entirely. The `[TSPOT_POI_MAPPED]` or `[TSPOT_POI_MISSING]` marker is never emitted for C3. The signal proceeds to STAGE_WAITING_FOR_POI with a midpoint entry price, then to STAGE_READY when price touches the T-Spot buffer zone, without ever having a PD Array as the entry trigger.

### 4.3 C3 Entry Price and SL Distance Inconsistency

The log shows `entry=2325.63` and `sl=2325.51` — only 12 points of SL distance. For GOLDmicro with point=0.01, 12 points is extremely tight.

GOLDmicro at ~$2325:
- 12pt = $0.12 price movement
- minLot=0.10 × $0.12 × tickValue ≈ $1.20 projected risk
- At $100 equity, 1% budget = $1.00, 0.6% = $0.60
- $1.20 > $0.60 → blocked

But the structural C2 anchor (c2_low for buys) should be much further — the C2 extreme of an H1 swing on GOLDmicro would typically be 200-300 points away. An entry at T-Spot midpoint at 2325.63 with SL at c2_low (perhaps 2323.28, ~235pt distance) would project:
- 235pt × 0.10 lot × tickValue ≈ $23.50 risk
- Budget $0.60-$1.00 → $23.50 >> budget

**Root Cause:** The structural SL anchor (c2_low) produces an SL distance proportional to H1 market structure. At $100 equity with minLot=0.10, ANY structural SL distance on GOLDmicro exceeds the 0.6-1.0% risk budget. The 12-point SL seen in the log is the CALCULATE_LOT_SIZE_FAILED path (rawLot=0) — not the actual structural SL.

### 4.4 No SMT Divergence Gate for C2

**File:** `OmakFxYO.mq5:5568-5604` (C2 POI transition to STAGE_READY)

**Death Point:** C2 signals transition to STAGE_READY via CISD confirmation (line 5578) or T-Spot touch (line 5734) without an SMT Divergence check.

**Constitutional Violation:** AGENTS.md §XVII: "For C2 setups, the signal is only STAGE_READY if SMT Divergence is detected with a correlated asset." The SMT gate is not implemented in the C2 POI → STAGE_READY transition logic.

---

## SUMMARY OF STRUCTURAL DEATH POINTS

| # | Death Point | File | Line(s) | Type | Severity |
|---|-------------|------|---------|------|----------|
| 1 | `DetectSymbolRiskFloor` uses hardcoded 100pt testSL | `RiskManager.mqh` | 105 | Init-time affordability under-estimate | HIGH |
| 2 | `g_minSLPoints=50` but actual structural SL averages 235pt | `OmakFxYO.mq5` | 351 | SL distance mismatch | HIGH |
| 3 | `CALCULATE_LOT_SIZE_FAILED`: no ClearSignalByGUID, no hasFailedRG | `OmakFxYO.mq5` | 6071-6083 | Infinite loop (33K+ spam) | **CRITICAL** |
| 4 | `EARLY_MINLOT_GUARD`: ZOMBIE_CLEARED intercepts before PERMANENT_SKIP | `OmakFxYO.mq5` | 1225-1243 → 1259-1264 | PERMANENT_SKIP unreachable | **CRITICAL** |
| 5 | PERMANENT_SKIP code unreachable from all affordability paths | `OmakFxYO.mq5` | 1259-1264 | Constitutional Violation (§XII) | **CRITICAL** |
| 6 | C3 entry price uses fixed midpoint, not PD Array zone scan | `ClosureEngine.mqh` | 1941-1943 | Gate 4 bypass | HIGH |
| 7 | C3 Wick Rule logs `WICK_RULE_BLOCK` but does not reject signal | `ClosureEngine.mqh` | 1908-1918 | Gate 2 bypass | HIGH |
| 8 | `ApplyWickFilter` uses Liberation Patch (0.3/0.8 not 0.5) | `ClosureEngine.mqh` | 502-534 | Wick Rule threshold violation | MEDIUM |
| 9 | C2WickFilter uses 0.6 threshold not 0.5 | `CoreTypes.mqh` | 703 | Wick Rule threshold violation | MEDIUM |
| 10 | C4 requires C3 reference; C3 never executes | `ClosureEngine.mqh` | 2001-2107 | C4 pathway extinction | HIGH |
| 11 | No SMT Divergence check before C2 STAGE_READY | `OmakFxYO.mq5` | 5578-5604 | Gate violation for C2 | HIGH |
| 12 | Init-time affordability gate (`minRequiredFactor > InpMaxMinLotRiskPercent`) may not block early enough | `OmakFxYO.mq5` | 3138-3147 | Pre-condition failure | MEDIUM |
| 13 | `StabiliseLot` returns 0.0 when rounded below minLot | `LotStabiliser.mqh` | 23-27 | Lot floor violation | HIGH |

---

## EXECUTION PROPAGATION CHAIN (0% Survival)

```
Signal Detection (C2/C3/C4)
  → Lock + GUID Assignment
    → STAGE_WAITING_FOR_POI or STAGE_LOCKED
      → POI touch / CISD confirmed
        → STAGE_READY (Gate 4 passed with midpoint entry, no PD Array)
          → PERSISTENT EXECUTION SCAN (line 6366)
            → ExecutionGatePass pipeline (line 6462)
              → CalculateClosureTypeSL → SL: ~12pt (not structural 235pt)
              → CalculateProjectionTPs → passes
              → FinalExecutionGuard → passes
              → **IsLotTradeable → FAIL** ($1.20 > $0.60 budget)
                → EARLY_MINLOT_GUARD (line 6048): hasFailedRG=true, ClearSignalByGUID
                  → ZOMBIE_CLEARED priority (line 1225): clears signal
                  → PERMANENT_SKIP NEVER REACHED (line 1259)
                  → Slot freed → new signal detected → **INFINITE LOOP**
              → **OR:** CalculateRiskLot → 0.0 rawLot → CALCULATE_LOT_SIZE_FAILED
                → NO ClearSignalByGUID (line 6083): signal stays READY
                → Next tick: hasFailedRG set by PERSISTENT SCAN (line 6444)
                → Next tick: ZOMBIE_CLEARED → slot freed → **INFINITE LOOP**
```

**Result:** 0 trades executed. 0% survival. 33,431+ log spam lines. 2 structural death points that prevent any trade from reaching ORDER_SENT.

---

## CONSTITUTIONAL VIOLATIONS INDEX

| § | Violation | Location |
|---|-----------|----------|
| §XII | PERMANENT_SKIP structurally unreachable from affordability failures | `OmakFxYO.mq5:1259-1264`, `1225-1243` |
| §XII | Init-time affordability gate uses unrealistic testSL (100pt vs 235pt) | `RiskManager.mqh:105` |
| §XII | Affordability failure produces unbroken infinite loop | `OmakFxYO.mq5:6071-6083` |
| §XVI Gate 2 | Wick Rule threshold is 0.3/0.8 (Liberation Patch), not 0.5 | `ClosureEngine.mqh:502-534` |
| §XVI Gate 2 | C3 Wick Rule logs block but does not reject | `ClosureEngine.mqh:1908-1918` |
| §XVI Gate 4 | C3 entry price is fixed midpoint, not zone-scanned PD Array | `ClosureEngine.mqh:1941-1943` |
| §XVII | SMT Divergence not checked before C2 STAGE_READY | `OmakFxYO.mq5:5578-5604` |
| §VI | SL distance at execution (12pt) not structural (C2 anchor) | `OmakFxYO.mq5:5999` |
| §XI | OrderCalcProfit inputs/outputs logged, but TELEMETRY_FRAUD from retry loop | `OmakFxYO.mq5:6071-6083` |

---

## TELEMETRY ANALYSIS

| Marker | Expected | Actual | Discrepancy |
|--------|----------|--------|-------------|
| `[PERMANENT_SKIP]` | Thousands (one per affordability fail) | **0** | §XII mechanism unreachable |
| `[READY_CLEARED_BLOCKED]` | Should appear if hasFailedRG=false | **0 in log sample** | Either never triggered or not in sample |
| `[TSPOT_POI_MAPPED]` | Should appear for C3 | **0** | C3 bypasses Gate 4 |
| `[TSPOT_POI_MISSING]` | Should appear for C3 if no PD Array | **0** | C3 bypasses Gate 4 |
| `[ZOMBIE_CLEARED]` | Should appear | **Not in sample** | May be suppressed or truncated |
| `[SMT_DIVERGENCE_PASS]` | Should appear before C2 READY | **0** | SMT gate not implemented |
| `[C4_ACCEPTED]` | Should appear if C4 detected | **0** | C4 requires C3 reference |

---

## FORENSIC INVESTIGATION TEMPLATE

Per AGENTS.md §XIV:

1. **Which constitutional law was violated?**
   - §XII (PERMANENT_SKIP unreachable) — CRITICAL
   - §XVI Gate 2 (Wick Rule threshold + non-rejection) — HIGH
   - §XVI Gate 4 (C3 bypasses PD Array scan) — HIGH
   - §XVII (SMT Divergence not implemented) — HIGH

2. **Which subsystem owned the failed state?**
   - `ClearSignalByGUID` (OmakFxYO.mq5:1211) owns signal clearance
   - `RiskManager::CalculateLotSize` (RiskManager.mqh:166) owns lot calculation
   - `ClosureEngine::EvaluateC3Closure` (ClosureEngine.mqh:1837) owns C3 detection
   - `ExecutionEngine::EE_MapPOI` (ExecutionEngine.mqh:287) owns Gate 4

3. **Where was ownership lost?**
   - hasFailedRG flag ownership: set in pipeline but intercepted by ZOMBIE before PERMANENT_SKIP
   - C3 entry price ownership: set by ClosureEngine instead of ExecutionEngine
   - Wick Rule ownership: set by EvaluateC3Closure but not enforced

4. **Which propagation chain broke?**
   - Affordability fail → PERMANENT_SKIP → infinite loop
   - C3 lock → midpoint entry → no PD Array → affordability fail
   - C3 lock → never executes → C4 has no reference

5. **Which downstream systems were poisoned?**
   - C3 store slots consumed by infinite loop signals
   - PERSISTENT EXECUTION SCAN flooded by retry signals
   - C4 pathway dead from missing C3 execution

6. **What prevents recurrence?**
   - See §XII: PERMANENT_SKIP must be reachable from all affordability fail paths
   - See §XVI Gate 4: C3 must use EE_MapPOI for entry price
   - See §XVI Gate 2: Wick Rule must reject (return false) not just log
