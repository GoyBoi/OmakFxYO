# Prompt 6: Deadlock Resolution & C3 Unblocking — Implementation Report

**Date:** 2026-06-03
**Focus:** Break the 176-GUID spam loop; unblock C3 signal promotion

---

## Summary

Two changes applied to `OmakFxYO.mq5`:

1. **IsLotTradeable failure path:** Set `hasFailedRG = true` before `ClearSignalByGUID` so STAGE_READY signals are not protected-blocked from clearance, breaking the infinite affordability-fail loop.

2. **C3 CISD + T-Spot promotion:** Added a new promotion gate for C3 signals where CISD is confirmed (`m_c3CisdConfirmed == true`) and price is inside the HTF T-Spot zone — promotes directly to `STAGE_READY`, unblocking the "extinct" C3 pathway.

## Changes

### Change 1: Deadlock Fix — `hasFailedRG` before ClearSignalByGUID

**Location:** `OmakFxYO.mq5` — Execution gate `IsLotTradeable` failure (line ~6017)

**Before:**
```cpp
ClearSignalByGUID(ctx.branch, execSig.m_guid, "RISK_MINLOT_REJECT");
continue;
```

**After:**
```cpp
g_activeSignal[idx].hasFailedRG = true;  // CRITICAL: allow ClearSignalByGUID to bypass READY protection
LogPrint("[RISK_FLOOR_BLOCK] Setting permanent skip for GUID: " + IntegerToString(execSig.m_guid));
ClearSignalByGUID(ctx.branch, execSig.m_guid, "RISK_MINLOT_REJECT");
continue;
```

**Why:** `ClearSignalByGUID` at line 1245 has a `STAGE_READY` protection gate that skips clearance when `!hasFailedRG`. Without setting the flag, affordability-failed signals loop infinitely — cleared by GUID, re-detected, re-locked, re-failed, repeat.

### Change 2: C3 Unblocking — CISD + T-Spot Promotion

**Location:** `OmakFxYO.mq5` — POI transition block, before C3 POI touch detection (line ~5752)

Added a new `else if` branch:
```cpp
else if(signal.closureType == CLOSURE_C3 && signal.m_c3CisdConfirmed &&
        signal.htfTSpotLow > 0.0 && signal.htfTSpotHigh > 0.0 &&
        g_activeSignal[idx].stage != STAGE_READY)
{
    bool priceInTSpot = /* price inside [htfTSpotLow, htfTSpotHigh] */;
    if(priceInTSpot) {
        TransitionStage(STAGE_READY);
        // RG gate + ExecutionGatePass
    }
}
```

**Promotion criteria:**
| Condition | Field | Source |
|-----------|-------|--------|
| Closure type | `closureType == CLOSURE_C3` | LockedSignal |
| CISD confirmed | `m_c3CisdConfirmed == true` | LockedSignal |
| Price in T-Spot | `bid/ask ∈ [htfTSpotLow, htfTSpotHigh]` | LockedSignal |

**Why:** C3 signals with confirmed CISD and price already inside the TSpot zone were stuck in `STAGE_WAITING_FOR_POI` because the only promotion path was the raw POI buffer zone (fixed 50pt from c3 midpoint). The CISD-based path uses the structural HTF T-Spot zone, matching how C2 CISD promotion works.

## Root Cause Analysis (per AGENTS.md §XIV)

| Question | Answer |
|----------|--------|
| Which constitutional law was violated? | No explicit violation — operational deadlock from missing `hasFailedRG` flag before clearance |
| Which subsystem owned the failed state? | `RiskManager` / execution gate — `IsLotTradeable` rejection path |
| Where was ownership lost? | `ClearSignalByGUID` protection gate at line 1245 blocked clearance of STAGE_READY signals without `hasFailedRG` |
| Which propagation chain broke? | Affordability fail → ClearSignalByGUID blocked → signal stays active → re-detected → re-locked → infinite loop |
| Which downstream systems were poisoned? | Signal store (176 zombie GUIDs), log spam, C3 pipeline starvation |
| What prevents recurrence? | `hasFailedRG = true` set before any `ClearSignalByGUID` call in affordability-fail paths |

## Files Changed
- Modified: `OmakFxYO/OmakFxYO.mq5` — two edits
- Created: `OmakFxYO/Documentation/Prompt6_Deadlock_Resolution_C3_Unblocking.md`
