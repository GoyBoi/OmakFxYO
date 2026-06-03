# Prompt E3 — Store Initialization + Macro Self-Assignment Fix

## Summary
Resolved lifespan globals (defaulted to 0) and store hygiene. Fixed UniversalConfig macro self-assignment by moving all input-to-global assignments before the `#include <UniversalConfig.mqh>` where `Inp*` names still reference the original `input` variables.

---

## Root Cause

`UniversalConfig.mqh` defines macros like `#define InpBranch g_InpBranch`. Post-include code doing `g_InpBranch = InpBranch;` expands to `g_InpBranch = g_InpBranch;` — a silent no-op. All 26 UC-mapped globals remained at their default value (0/null) throughout the session.

Secondary: The store init used `ZeroMemory()` / `ArrayInitialize()` instead of `SLockedSignal::Reset()`, leaving internal struct state (GUID, handover state, stage) incompletely cleared across EA re-initializations.

---

## Exact Changes

### File: `OmakFxYO.mq5`

#### Change 1 — New SEQUENCE 3.5: Pre-Macro Input Assignments

**Location:** Lines 250–300 (inserted between global declarations and `#include <UniversalConfig.mqh>`)

All 37 `g_Inp* = Inp*` assignments moved to BEFORE the macro include. At this point `InpBranch` (etc.) refers to the original `input` variable, so the assignment actually copies the user's parameter value into the global.

```
SEQUENCE 3: GLOBALS          ← g_InpBranch declared, value = 0
  ...
SEQUENCE 3.5: ASSIGNMENTS    ← g_InpBranch = InpBranch  (reads input param)
  ...
SEQUENCE 4: #include UC      ← #define InpBranch g_InpBranch
  (code after this uses InpBranch to mean g_InpBranch — value is already correct)
```

#### Change 2 — Removed Redundant Post-Macro Block

**Location:** Formerly lines 3109–3155 in OnInit (now deleted).

The entire block of duplicate `g_InpX = InpX` assignments that had become self-assignments via macro expansion is removed. Limit-order routing (`InpUseLimitOrders`, `InpA/B_LimitExpirationBars`) and tradeability state init (`g_lastTradeabilityCheckBar`, `g_symbolUntradeable`) remain in OnInit.

#### Change 3 — Store Reset via Reset() + [STORE_INIT] Marker

**Location:** Lines 3328–3334 in OnInit (replaces `ZeroMemory` + `ArrayInitialize`).

```cpp
// Full store reset (Prompt_E3): Reset() + clear flags for every slot
for(int i = 0; i < ArraySize(g_activeSignal); i++)
{
    g_activeSignal[i].Reset();
    g_hasActiveSignal[i] = false;
}
LogPrint("[STORE_INIT] All slots reset on OnInit", LOG_LEVEL_INFO);
```

This replaces the previous approach that only zeroed memory without calling `SLockedSignal::Reset()`, which left handover state, GUID, and stage metadata uncleared.

---

## Verification

| Check | Expected | Status |
|-------|----------|--------|
| `g_InpBranch` after OnInit | User's `InpBranch` value (not 0) | Fixed via pre-macro assignment |
| `g_InpSetupLifespanBars_Intraday` | User's 24 (not 0 -> maxBars=0) | Fixed (was already correct, now confirmed pre-macro) |
| `g_hasActiveSignal[]` post-init | All `false` | Fixed |
| `g_activeSignal[i].m_guid` post-init | 0 | Fixed via `Reset()` |
| `g_activeSignal[i].handoverState` post-init | `HANDOVER_NONE` | Fixed via `Reset()` |
| `g_activeSignal[i].stage` post-init | `STAGE_NONE` | Fixed via `Reset()` |
| Log output | `[STORE_INIT] All slots reset on OnInit` | Added |
