# OmakFxYO Constitutional Runtime Forensic Report v76

**Log**: 20260603.log (GOLDmicro, $100 equity, 2024.04.01–2024.04.25)
**EA Build**: 1.0.0.31
**Engine**: omak-forensic-v2.0.0
**Date**: 2026-06-03

---

## 0. CRITICAL FINDING — LOG SPAM DOMINATES RUNTIME

| Metric | Value |
|--------|-------|
| Total log lines | 66,089 |
| Unique timestamps | 2,451 |
| **Spam lines (duplicate evaluations)** | **63,638 (96.3%)** |
| Lines per unique timestamp | 27.0 |

**96.3% of all log output is repeated evaluation of the same signals on the same tick.**

The EA is not making sequential progress — it is burning CPU and log bandwidth re-evaluating the same signal states at every tick interval without advancing their lifecycle.

---

## 1. EXECUTIVE SUMMARY

### Execution Survival: **0.0%**
| Metric | Count |
|--------|------:|
| GUID Assigned | 1,445 |
| C2 Closures Detected | 194 |
| CISD Confirmed | 132 |
| RG Gate Pass | 454 |
| EXEC Gate Enter | 8 |
| EXEC Gate Pass | **0** |
| ORDER SENT | **0** |

**Zero trades executed. Zero orders sent. Zero fills.**

### Primary Execution Bottleneck

**RISK_FLOOR_BLOCK** dominates the death ledger:

| Block Reason | Count |
|-------------|------:|
| CALCULATE_LOT_SIZE_FAILED | 398 |
| LOT_BELOW_MINLOT_PRE_STAB | 8 |
| EARLY_MINLOT_GUARD | 4 |
| **Total** | **410** |

### Dead Pathways

| Pathway | Status |
|---------|--------|
| C2 → STAGE_READY → EXEC_GATE | **Extinct** — 0 executions from 194 closures |
| C3 | **Completely dead** — 0 C3 closures detected (all 369 are CLOSURE_NONE) |
| C4 | **Completely dead** — 0 C4 events |
| Branch B (Swing) | **Unknown** — No data (only Branch A active) |

---

## 2. RUNTIME TRUTH AUDIT

### 2.1 Signal Lifecycle Pipeline (Actual vs Expected)

```
Expected: GUID_ASSIGNED → SIGNAL_LOCKED → STAGE_READY → RG_GATE_PASS → EXEC_TRIGGER → ORDER_SENT
Actual:   GUID_ASSIGNED → SIGNAL_LOCKED → STAGE_WAITING_FOR_POI → [RISK_FLOOR_BLOCK] → C2_SETUP_EXPIRED → DEATH
```

### 2.2 Stage Transition Survival

| Stage | Entered | Survived | Survival Rate |
|-------|---------|----------|--------------|
| GUID_ASSIGNED | 1,445 | 1,445 | 100% |
| SIGNAL_LOCKED | 61 | 61 | 100% |
| STAGE_WAITING_FOR_POI | 1,917 | 1,917 | 100% |
| STAGE_READY | 152 | 152 | 100% |
| RG_GATE_PASS | 454 | 454 | 100% |
| EXEC_GATE_ENTER | 8 | 8 | 100% |
| EXEC_TRIGGER | 223 | 223 | 100% |
| **ORDER_SENT** | **0** | **0** | **0%** |

**The pipeline does not leak — it hard-blocks at ORDER_SENT.** Every signal that enters a stage survives to the next stage, but no signal ever completes the final step of order placement.

### 2.3 Telemetry vs Runtime Reality

| Claim (Log) | Runtime Truth | Verdict |
|-------------|--------------|---------|
| `[EXEC_TRIGGER]` 223 times | No order was ever sent | **FAKE TRIGGER** — trigger fires but lot=0 prevents execution |
| `[RG_GATE_PASS]` 454 times | Gate passes but no order follows | **HOLLOW GATE** — pass is meaningless without lot viability |
| `[SIGNAL_LOCKED]` 61 times | Only 152 reach STAGE_READY | **TRUE** (proportionally correct) |
| `[CISD_CONFIRMED]` 132 times | CISD confirms but no execution | **TRUE but orphaned** — CISD passes but risk kills the trade |

---

## 3. OWNERSHIP CORRUPTION AUDIT

### 3.1 Handover Ownership — MASSIVE VIOLATION

| State | Owner (Per AGENTS.md) | Actual Runtime Ownership | Verdict |
|-------|----------------------|------------------------|---------|
| handoverState | BranchEvaluator (sole) | **LockedSignal provides state, BranchEvaluator calls Acquire/Release every tick** | **OWNERSHIP_CORRUPTION** |

**Evidence**: Log shows 8,406 `[HANDOVER_ACQUIRED]` and 8,395 `[HANDOVER_RELEASED]` events across only **64 unique GUIDs**. Each GUID gets **~275 acquire/release pairs**.

The handover state machine (AGENTS.md §II) specifies:
```
HANDOVER_ACQUIRED ──TransferHandover()──> HANDOVER_TRANSFERRED
HANDOVER_ACQUIRED ──ReleaseHandover()──> HANDOVER_RELEASED
```

But runtime executes:
```
HANDOVER_ACQUIRED → [immediate check] → HANDOVER_RELEASED (every tick, per signal)
```

**Constitutional Violation**: The handover lifecycle specifies that `AcquireHandover()` should set HANDOVER_ACQUIRED and the state should persist until `TransferHandover()` or `ReleaseHandover()` completes downstream processing. Instead, the EA acquires and releases handover on every evaluation cycle, creating 16,801 handover log events for ZERO downstream processing.

**Root cause location**: `OmakFxYO.mq5` lines 5422-5430 and 5455-5462 — the C2 and C3 routers acquire handover, check a condition, then immediately release it.

### 3.2 Risk Percentage Ownership — DUAL AUTHORITY CONFLICT

| Parameter | Value | Used By | Purpose |
|-----------|-------|---------|---------|
| `InpRiskPercent` | 0.6 (runtime) / 1.0 (default source) | `CalculateRiskLot()` → `CalculateLotSize()` | Per-trade risk budget for lot sizing |
| `InpMaxMinLotRiskPercent` | 5.0 | `IsLotTradeable()` in `EARLY_MINLOT_GUARD` | Affordability check for minLot |

**Constitutional Violation**: Two different risk percentages are used for two different checks against the same trade. The affordability check uses 5% ($5.00 budget) and PASSES. The lot calculation uses 0.6% ($0.60 budget) and FAILS (raw lot 0.03 < minLot 0.1). These two gates contradict each other.

**Downstream poisoning**: Signals pass the EARLY_MINLOT_GUARD, proceed to CalculateLotSize, fail with CALCULATE_LOT_SIZE_FAILED, and get permanently skipped — all while the log claims they were "tradeable."

---

## 4. CONTINUATION NARRATIVE AUDIT

### 4.1 C3 — COMPLETE EXTINCTION

| Metric | Count |
|--------|-------|
| C3 Closures (PASS) | **0** |
| C3 Closures (any) | **0** |
| CLOSURE events total | 369 |
| CLOSURE type = CLOSURE_NONE | 369 |
| CLOSURE type = CLOSURE_C2 | 194 (counted via engine pipeline_entries) |
| CLOSURE type = CLOSURE_C3 | **0** |

**All 369 closure events have type CLOSURE_NONE. C3 never produces a valid CLOSURE_C3.**

The closure engine (`ClosureEngine.mqh`) never detects a C3 setup. Every `[CLOSURE]` marker in the log says `C2=PASS | type=CLOSURE_NONE` — meaning the C2 passes but the closure type is NOT SET to CLOSURE_C2 or CLOSURE_C3.

This is likely because:
1. C3 detection conditions are never met (the narrative state never reaches C3 readiness)
2. OR the closure type assignment is incorrectly defaulting to CLOSURE_NONE

### 4.2 C4 — COMPLETE EXTINCTION

Zero C4 events. C4 requires either C3 or C2 as a structural reference. Since C3 is dead and C2 never executes, C4 has no foundation.

### 4.3 Continuation Narrative Status: **COLLAPSED**

The narrative chain C2 → C3 → C4 is completely broken at C2 execution. No C2 executes, so no continuation can mature.

---

## 5. PIPELINE SURVIVAL AUDIT

### 5.1 Stage-by-Stage Death Map

```
GUID_ASSIGNED (1445)
  │
  ├──→ SIGNAL_LOCKED (61) → STAGE_WAITING_FOR_POI → C2_SETUP_EXPIRED → DEATH
  │
  └──→ STAGE_WAITING_FOR_POI (1917 events across all signals)
         │
         ├──→ CISD_CONFIRMED (132) → STAGE_READY (152)
         │                              │
         │                              ├──→ RG_GATE_PASS (454) → EXEC_TRIGGER (223) 
         │                              │                            │
         │                              │                            └──→ RISK_FLOOR_BLOCK (410) → DEATH
         │                              │
         │                              └──→ READY_CLEARED_BLOCKED (107) → PERPETUAL LOOP
         │
         └──→ C2_SETUP_EXPIRED (123 unique, thousands of spam repeats)
```

### 5.2 The RISK_FLOOR_BLOCK Death Spiral

The execution sequence for a signal at STAGE_READY:

1. `ExecutionGatePass()` is called (line 6462 in OmakFxYO.mq5)
2. EARLY_MINLOT_GUARD check passes (5% risk, $2.00 < $5.00)
3. `CalculateRiskLot()` calls `CalculateLotSize()` with 0.6% risk
4. `CalculateLotSize()` computes rawLot = $0.60 / ($2.00 / 0.1) = 0.03
5. rawLot (0.03) < minLot (0.1) → returns 0.0
6. Main code logs `[RISK_FLOOR_BLOCK] CALCULATE_LOT_SIZE_FAILED`
7. Signal is permanently skipped via `ClearSignalByGUID`

**Critical**: The EARLY_MINLOT_GUARD (uses 5%) passes, creating a false sense of tradeability. Then the actual lot calculation (uses 0.6%) fails. The guard and the calculator are desynchronized.

---

## 6. DEAD PATHWAY AUDIT

### 6.1 Extinct Pathways

| Pathway | Status | Root Cause |
|---------|--------|------------|
| C2 → ORDER_SENT | **Extinct** | Risk floor block (lot=0) |
| C3 → any | **Extinct** | Closure engine never detects C3 |
| C4 → any | **Extinct** | No C3 foundation |
| Branch B (Swing) | **Extinct** | Only Branch A has data |

### 6.2 Dormant Pathways

| Pathway | Status |
|---------|--------|
| Confirmation Mode | **Dormant** — no C3/C4 to enable it |
| SMT Divergence | **Dormant** — 0 SMT markers found |
| WICK_RULE_BLOCK | **Active but irrelevant** — 422 blocks but wick is not the bottleneck |

---

## 7. CONSTITUTIONAL VIOLATIONS

### Violation 1: Handover State Machine Subversion

| Field | Detail |
|-------|--------|
| **Violated law** | AGENTS.md §II — Handover Ownership State Machine |
| **Owning subsystem** | `BranchEvaluator` via `OmakFxYO.mq5` (lines 5422-5430, 5455-5462) |
| **Root cause** | Handover acquired and released on every tick check instead of held through execution lifecycle |
| **Downstream poisoning** | 16,801 log events = 25% of all log output. CPU wasted on handover state transitions. |
| **Repair priority** | **HIGH** — reduces log volume by 25% and eliminates deadlocked handover checking |

### Violation 2: Dual Risk Authority

| Field | Detail |
|-------|--------|
| **Violated law** | AGENTS.md §VI — Risk Constitution (single risk authority) + §XIII — Telemetry Integrity |
| **Owning subsystem** | `RiskManager.mqh` + `OmakFxYO.mq5` |
| **Root cause** | `InpRiskPercent` (0.6%) used for lot calculation produces rawLot below minLot; `InpMaxMinLotRiskPercent` (5.0%) used for affordability check passes. Two contradicting risk thresholds. |
| **Downstream poisoning** | Signals pass the guard, fail the calculator, get permanently skipped. 398 CALCULATE_LOT_SIZE_FAILED events. |
| **Repair priority** | **CRITICAL** — no trade can execute while this contradiction exists |

### Violation 3: Perpetual Re-evaluation Loop

| Field | Detail |
|-------|--------|
| **Violated law** | AGENTS.md §VII — Hidden fallback execution + Dead continuation branches |
| **Owning subsystem** | `OmakFxYO.mq5` OnTick pipeline |
| **Root cause** | Same signals evaluated on every tick without state advancement. 96.3% of log lines are repeats. |
| **Downstream poisoning** | 27x log amplification. No CPU left for actual execution. |
| **Repair priority** | **HIGH** — eliminates 96% of log spam |

### Violation 4: C3 Closure Extinction

| Field | Detail |
|-------|--------|
| **Violated law** | AGENTS.md §III — Standalone Closure Preservation (C3 standalone evaluation required) |
| **Owning subsystem** | `ClosureEngine.mqh` |
| **Root cause** | All 369 closures report CLOSURE_NONE type. C3 never detected. |
| **Downstream poisoning** | No confirmation-mode trades possible. No C4 foundation. |
| **Repair priority** | **MEDIUM** — C3 alone would not fix execution; lot calculation must be fixed first |

### Violation 5: Telemetry Fraud (EXEC_TRIGGER)

| Field | Detail |
|-------|--------|
| **Violated law** | AGENTS.md §XIII — Telemetry Integrity |
| **Owning subsystem** | `OmakFxYO.mq5` execution loop |
| **Root cause** | `EXEC_TRIGGER` is emitted (223 times) but no order is ever sent. The trigger fires into a RISK_FLOOR_BLOCK. |
| **Repair priority** | **MEDIUM** — fix after primary risk block is resolved |

---

## 8. ARCHITECTURAL REPAIR DIRECTIVES

### Directive 1: Unify Risk Percentage (CRITICAL — PREREQUISITE FOR ALL TRADES)

**Problem**: Two risk percentages (0.6% for lot calc vs 5% for affordability) create contradictory gates.

**Fix**: Align `CalculateRiskLot()` to use the same risk percentage as the affordability check. Either:
- **Option A** — Raise `InpRiskPercent` to match `InpMaxMinLotRiskPercent` (5%) so lot calculation produces lots >= minLot
- **Option B** — Lower `InpMaxMinLotRiskPercent` to match or be <= `InpRiskPercent` so affordability check fails early
- **Option C** — Change CalculateLotSize to use `MathMin(InpRiskPercent, InpMaxMinLotRiskPercent)` so the more conservative value is used consistently

**Recommended**: Option C — make `CalculateLotSize` aware of the minLot affordability constraint so it uses `min(InpRiskPercent, InpMaxMinLotRiskPercent)` when computing the raw lot, OR change it to use `InpMaxMinLotRiskPercent` directly when the computed raw lot falls below minLot.

### Directive 2: Eliminate Per-Tick Handover (HIGH)

**Problem**: Handover acquired and released on every tick.

**Fix**: In `OmakFxYO.mq5` lines 5422-5430 and 5455-5462, remove `AcquireHandover()`/`ReleaseHandover()` calls from the per-tick check loops. Handover should only be acquired when:
- A signal transitions to a new stage that requires exclusive access
- A signal is about to execute

For the tick-level `lockTime >= ctxBarTime` check, no handover is needed — the signal is simply not ready yet.

### Directive 3: Add Tick-Level Idempotency Gate (HIGH)

**Problem**: Same signal states evaluated 27 times per unique timestamp.

**Fix**: Add a signal-level "last evaluated tick" timestamp. If `signal.lastEvaluatedTick == currentTick`, skip re-evaluation. Only process signals when their stage or the bar has actually changed.

```mql
if(g_activeSignal[idx].lastEvaluatedTick == g_tickCounter)
    continue;  // Already processed this tick
g_activeSignal[idx].lastEvaluatedTick = g_tickCounter;
```

### Directive 4: Fix C3 Detection (MEDIUM)

**Problem**: ClosureEngine never produces CLOSURE_C3.

**Investigation needed**: Trace why `ClosureEngine.mqh` emits `type=CLOSURE_NONE` for all closures. The closure detection code should be producing `CLOSURE_C2` or `CLOSURE_C3` types. Check:
1. `ClosureEngine.mqh` line 330 where `type = CLOSURE_C3` is set
2. Line 402 where `type = CLOSURE_NONE` is set
3. Check if C3 conditions are reachable at all
4. Check if `g_C3_RUNTIME_DISABLED` is true

### Directive 5: Remove EXEC_TRIGGER Before Lot Validation (MEDIUM)

**Problem**: EXEC_TRIGGER fires before lot is confirmed valid.

**Fix**: Move `EXEC_TRIGGER` emission to AFTER successful lot calculation and order placement, not before.

---

## 9. VERIFICATION COMMANDS

To verify repairs:

```bash
# Run forensic analysis on new log
python3 OmakFxYO/scripts/omak_cli.py analyze "<log_path>/<new_log>.log"

# Check for specific metrics post-fix:
# - HANDOVER events should drop from 16,801 to < 100
# - CALCULATE_LOT_SIZE_FAILED should be 0
# - LOT_BELOW_MINLOT_PRE_STAB should be 0
# - ORDER_SENT should be > 0
# - Unique timestamps / total lines ratio should be closer to 1:1 (not 27:1)
```

---

*Generated by OmakFxYO Constitutional Runtime Auditor v08*
*Forensic evidence: 66,089 log lines from 20260603.log (GOLDmicro, $100 equity)*
