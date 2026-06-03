# Prompt E1: Signal Formation & T-Spot Entry Price (Core Layer Fix)

**Date:** 2026-06-03  
**File Modified:** `core/ClosureEngine.mqh`  
**Scope:** `EvaluateC2Closure`, `EvaluateC3Closure`, `DetectClosureSignal` (all fallback paths)  
**Constitutional Authority:** AGENTS.md §V (Execution Truth Separation), §XVI Gate 4 (T-Spot Zone), §XVII (T-Spot POI Mapping)

---

## Problem

Every signal (C2 Anticipation, C3 Confirmation) was forming with `entry_price` derived from the *most recent candle open* (`c4_open`) or *C3 close price*, rather than from the **T-Spot equilibrium** of the Structural TF candle. This violated:

1. **AGENTS.md §V** — `candidateEntryPrice` must be the entry price at signal detection, set from T-Spot or LTF structural level.
2. **AGENTS.md §XVI Gate 4** — The T-Spot is a **zone** anchored to Equilibrium (50% of structural range). Entry must derive from this zone.
3. **LockedSignal::Lock()** (`CoreTypes.mqh:477`) — Rejects lock with `[ENTRY_CANDIDATE_INVALID]` when `signal.entry_price <= 0`.

The `c4_open` fallback produced prices disconnected from structural logic, and flat `c3_close` entries ignored the T-Spot zone definition.

---

## Changes

### 1. `EvaluateC2Closure` — T-Spot Entry for Anticipation

**Location:** `ClosureEngine.mqh:1730-1737`

Added after `signal.c2_wick_ratio` assignment, before logging:

```
double tSpotC2 = (c2_high + c2_low) / 2.0;       // C2 Equilibrium
double currentPriceC2 = (signal.is_bullish)
    ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
    : SymbolInfoDouble(_Symbol, SYMBOL_BID);
signal.entry_price = (tSpotC2 > 0.0) ? tSpotC2 : currentPriceC2;

LogPrint("[ENTRY_CANDIDATE_SET] C2 T-Spot | GUID_pre=... entry=... tspot=...");
```

**Rationale:** C2 Equilibrium = midpoint of the C2 structural candle. This is the canonical T-Spot anchor for Anticipation mode (sweep + close-inside entry). Dynamic fallback to current broker price ensures a valid price is always available.

### 2. `EvaluateC3Closure` — T-Spot Entry for Confirmation

**Location:** `ClosureEngine.mqh:1860-1876`

Replaced:
```
signal.entry_price = (c3_close > 0) ? c3_close : (c3_open > 0 ? c3_open : 0.0);
```
With:
```
double tSpotC3 = (c3_high + c3_low) / 2.0;       // C3 Equilibrium
double currentPriceC3 = (signal.is_bullish)
    ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
    : SymbolInfoDouble(_Symbol, SYMBOL_BID);
signal.entry_price = (tSpotC3 > 0.0) ? tSpotC3 : currentPriceC3;
```

Guard updated to log `tSpotC3` and `currentPriceC3` instead of `c3_close`/`c3_open`.

**Rationale:** C3 Equilibrium = midpoint of the C3 continuation candle. Per Continuations PDF: expansions enter within the T-Spot zone anchored to the continuation candle's range. The flat `c3_close` was a proxy — now replaced with the true equilibrium anchor.

### 3. `DetectClosureSignal` — All Fallback Paths Updated

All 5 hardcoded entry-price overrides converted to T-Spot equilibrium:

| Path | Location | Old | New |
|------|----------|-----|-----|
| C2 primary | `:2318-2319` | `signal_c2.entry_price = c4_open` | Fallback only if `entry_price <= 0.0` (T-Spot set in EvaluateC2Closure) |
| C3 displacement | `:2393-2399` | `(c3_close > 0) ? c3_close : (c3_open > 0 ? c3_open : 0.0)` | `tSpotC3_disp = (c3_high + c3_low) / 2.0` with broker fallback |
| C3 classic fallback | `:2438-2444` | Same C3 close/open fallback | `tSpotC3_cf = (c3_high + c3_low) / 2.0` with broker fallback |
| C2 classic fallback | `:2478-2484` | `signal_c2.entry_price = c4_open` | `tSpotC2_cf = (c2_high + c2_low) / 2.0` with broker fallback |
| C3 delayed continuation | `:2654-2661` | `signal_c3.entry_price = scan_open` | `tSpotC3_dc = (scan_high + scan_low) / 2.0` with broker fallback |

### 4. C4 Entry — Explicitly Not Changed

`EvaluateC4Closure` (`:1986`) uses `signal.entry_price = c4_open`. This is correct by design: C4 is a continuation/expansion event entering on the *open* of the expansion candle, not at an equilibrium level. Per AGENTS.md §III: "C4 always maps to MODE_CONFIRMATION" — C4 entry at candle open is principled and distinct from C2/C3 T-Spot entries.

---

## Verification

### Canonical Markers

All new markers use the canonical `[DOMAIN_VERB]` form per AGENTS.md §VIII:

- `[ENTRY_CANDIDATE_SET]` — used in all 7 edit sites (C2 T-Spot, C3 T-Spot, C3 displacement, C3 classic fallback, C2 classic fallback, C3 delayed continuation, C2 primary guard)

### No Prohibited Behaviors (AGENTS.md §VII)

| Rule | Status |
|------|--------|
| No silent mode substitution | PASS — executionMode assigned in Lock(), unchanged |
| No hidden fallback execution | PASS — fallback to broker `SYMBOL_ASK`/`SYMBOL_BID` is documented and logged |
| No invisible state mutation | PASS — all `entry_price` changes emit `[ENTRY_CANDIDATE_SET]` with values |
| No ATR-based logic | PASS — T-Spot is structural (candle high/low), not ATR-derived |
| No fixed midpoint as final entry | PASS — constitutionally, this sets the *candidate*, not the final POI-mapped entry (POI scanning in Gate 4 refines it) |
| No locking before all four gates | PASS — Lock() still requires `[TSPOT_POI_MAPPED]` or `[TSPOT_POI_MISSING]` via pipeline |
| No locking with entry_price=0 | PASS — T-Spot + broker fallback guarantees valid price |

### Downstream Dependency Pass-Through

The `SClosureSignal.entry_price` set here flows through to `SLockedSignal.candidateEntryPrice` at `CoreTypes.mqh:530`:
```
candidateEntryPrice = signal.entry_price;
```

No downstream consumer needs modification. The POI scanning subsystem (Gate 4) will refine `entry_price` into `requestedEntryPrice` at execution time per AGENTS.md §V.

### Unchanged Contracts

- `IsValidC3Setup` (`CoreTypes.mqh:398-413`) — validates `entry_price > 0.0`, which now passes because T-Spot + broker fallback guarantees non-zero.
- `SLockedSignal::Lock` (`CoreTypes.mqh:418`) — checks `signal.entry_price <= 0` at line 477, now guaranteed to pass.
- C4 entry remains at `c4_open` — distinct architectural treatment per AGENTS.md §III.

---

## Summary

Every C2 and C3 signal path now forms with a **valid, non-zero `candidateEntryPrice`** derived from the **T-Spot equilibrium** of its structural candle (`(high + low) / 2`), with a **dynamic broker-price fallback** (`SYMBOL_ASK`/`SYMBOL_BID`). The `[ENTRY_CANDIDATE_INVALID]` deadlock is resolved at the formation layer.
