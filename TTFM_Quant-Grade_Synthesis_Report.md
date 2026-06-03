# TTFM Synthesis Report: Working Architecture, State Machine, and EA Specification

**Evidence-Traceable Technical Analysis | Deep Research Protocol 10+ Iteration Cycles | May 2026**

---

## 1. Executive Summary

The TTrades Fractal Model (TTFM) is a deterministic, candle-closure-based price action trading system. The model operates as a boolean engine: unless specific price-point and closure conditions are met, no state change occurs. This design philosophy systematically eliminates discretionary judgment, replacing subjective chart interpretation with a mechanical execution framework.

Rooted in Candle Range Theory (CRT), the TTFM extends traditional Accumulation-Manipulation-Distribution (AMD) cycles with five additional confluence layers: Change in State of Delivery (CISD) confirmation, Smart Money Technique (SMT) divergence, T-Spot equilibrium-based wick prediction, protected swing structural validation, and auto-bias higher-timeframe alignment.

**Architectural scope of this document:** This report reconstructs the TTFM as a working architecture for the OmakFxYO implementation. It distinguishes between closure families (C2, C3), continuation events (C4), and the narrative context that governs continuation windows. The model is fully fractal, mapping identically across specific timeframe hierarchies (e.g., Weekly/4H, Daily/1H).

**Evidence classification:** Claims in this document are tagged as either `[EVIDENCE-BACKED]` (supported by TTrades source material or verified implementation behavior) or `[INTERPRETIVE]` (reconstructed from available sources where original TTrades material is not present in the workspace). The TTrades source PDFs and blog posts referenced during development are not committed to this repository — the primary reconstruction source is the Quant-Grade synthesis process itself [INTERPRETIVE].

---

## 2. Canonical Model Reconstruction

### 2.1 Core Philosophy and Boolean Engine Design

The indicator functions strictly as a boolean engine. The core mechanical framework identifies three candle types (C1, C2, C3) with an optional fourth continuation candle (C4). The logic relies exclusively on price extremes; the color of the candles is irrelevant to structural identification.

**C3 Continuation Pathway (Single Source of Truth):**
C3 is not a "secondary" signal but an independent confirmation candle that tells a unique narrative of directional expansion. The EA treats C3 as a primary entry generator that strictly adheres to the Four-Gate Hierarchy, with special emphasis on Gate 4 (T-Spot POI Mapping) [EVIDENCE-BACKED — AGENTS.md §IV].

**C3 Zone Mapping (Constitutional Definition):**
The T-Spot zone for C3 follows the same boundaries as all signals:
- **Bullish C3 Zone:** HTF Equilibrium (50%) down to the HTF Low
- **Bearish C3 Zone:** HTF Equilibrium (50%) up to the HTF High

**Entry Rule:** Entry is set to the opening price of an Order Block (OB) or the 0.5 level of a Fair Value Gap (FVG) strictly mapped inside this zone. Falling back to a midpoint is a Constitutional Violation [AGENTS.md §XVII Gate 4].

**C3 Promotion Logic:**
A signal is NOT `STAGE_READY` simply because a candle closed. Promotion requires:
1. **Mechanical ITF CISD Gate:** Price must close beyond the opening price of the initiating candle of the opposing delivery series on the Structure TF
2. **Zone Validation:** Price must be inside the mapped POI when CISD is confirmed
3. Both conditions must be met simultaneously for `STAGE_READY` [EVIDENCE-BACKED — AGENTS.md §IV].

**C3 Telemetry Requirements:**
Every C3 signal must emit either `[TSPOT_POI_MAPPED]` or `[TSPOT_POI_MISSING]`. Defaulting to `CLOSURE_NONE` without explicit POI telemetry is prohibited [EVIDENCE-BACKED — AGENTS.md §IV].

**Closure family vs. continuation event distinction:**
- **C2 and C3** are closure families — distinct structural patterns that independently generate signals [EVIDENCE-BACKED — implementation: EvaluateC2Closure, EvaluateC3Closure].
- **C4** is a continuation/expansion event that may be tracked as a signal object (type CLOSURE_C4) for pipeline consistency [EVIDENCE-BACKED — implementation: EvaluateC4Closure comment: "C4 is NOT a rigid 'fourth candle.' It is a structural continuation event"].
- **Narrative** (continuationLineage) is the contextual state that governs whether continuation windows are open, deferred, or expired. Narrative is SOLELY owned by ClosureState via SLineage [EVIDENCE-BACKED — AGENTS.md §IV, ClosureState.mqh SLineage struct].

### 2.2 Candle Definitions: C1, C2, C3, C4

| Element | Bullish (Swing Low) Condition | Bearish (Swing High) Condition | Structural Role |
| :--- | :--- | :--- | :--- |
| **C1** | Reference candle establishing the range | Reference candle establishing the range | Defines the key level that price will interact with; provides liquidity target for sweep |
| **C2** | `C2 Low < C1 Low AND C2 Low < C3 Low` | `C2 High > C1 High AND C2 High > C3 High` | Definitive structural anchor and invalidation point; performs the liquidity sweep |
| **C3** | Closes back above C2 Low/inside C1 range | Closes back below C2 High/inside C1 range | Confirms C2 is the extreme; validates the reversal pattern |
| **C4** | Expands out of upper half of C3 range | Expands out of lower half of C3 range | Continuation event; secondary expansion with minimal retracement |

**Relationship notes:**
- C2 and C3 are sibling closure families. Neither is a prerequisite for the other in all cases [EVIDENCE-BACKED — AGENTS.md §III, ClosureEngine.mqh IsValidC2Standalone()].
- C4 is a continuation/expansion event. When C3 is enabled, C4 expands from C3 range data. When C3 is runtime-disabled, C4 may expand from C2 extremes directly [EVIDENCE-BACKED — Continuation_Family_Realignment.md:15, EvaluateC4Closure() C2 reference path].
- The state machine supports both standalone C2 lock (without C3) and standalone C3 detection (without a prior C2 trade) [EVIDENCE-BACKED — ClosureEngine.mqh standalone paths]. A common pattern is the C1→C2→C3 sequence where C3 confirms the C2 sweep reversal, but this is a common pattern, not a universal requirement.
- **The 50% Wick Rule** is a volitility filter applied on the Structure TF candle. If `longestWick / totalRange > 0.5`, the candle is classified as a reversal signature and does NOT support expansion trades (C3/C4). The EA must switch to Reversal Mode (target = HTF Open) or stand aside [EVIDENCE-BACKED — AGENTS.md §XVII Gate 2, §XVIII].

### 2.3 Change in State of Delivery (CISD) — Mechanical Definition

The CISD is a boolean trigger representing a definitive shift in institutional order flow and serves as the primary entry gate (Gate 3 in the Four-Gate Hierarchy). A CISD occurs when price closes through the series of candles that created a swing high or swing low.

**Mechanical rule:** For a bullish swing, price must close **above the opening price** of the series of down-close candles that formed the swing low. For a bearish swing, price must close **below the opening price** of the series of up-close candles that formed the swing high. The "series of candles" refers to consecutive closes in the same direction that established the swing point. A single close beyond the opening price of the initiating candle of the series constitutes a mechanical CISD [EVIDENCE-BACKED — AGENTS.md §XVII Gate 3].

CISD must be evaluated on the Structure TF (H1 for Branch A, H4 for Branch B). CISD confirmation on the Structure TF unlocks the signal for Entry TF evaluation. The opening price of the initiating candle is the single most important reference level for CISD confirmation — if price closes beyond this level, the structural shift is confirmed regardless of other technical factors.

### 2.4 T-Spot POI Mapping (Zone-Based)

The T-Spot identifies the anticipated area where higher-timeframe candle wicks are expected to form during expansion phases. In the Boolean Engine framework, the T-Spot is a **zone** — NOT a fixed midpoint — and serves as Gate 4 (LTF Execution).

**Zone definition (Gate 4):**
| Direction | Zone Range |
|-----------|------------|
| Buy (Bullish) | Equilibrium (50%) to HTF Low |
| Sell (Bearish) | Equilibrium (50%) to HTF High |

**POI selection rules:**
- `entry_price` is NOT set to a fixed midpoint. The EA scans the T-Spot zone for a PD Array (Order Block or Fair Value Gap) on the Entry TF.
- `entry_price` is set to the PD Array's open or 0.5 Fibonacci level within the zone.
- PD Array priority: Breaker Block > FVG > Order Block > Inversion FVG.
- If multiple PD Arrays exist, select the one closest to Equilibrium.
- If no PD Array exists in the T-Spot zone, the signal must wait (STAGE_WAITING_FOR_POI) — it must not use a fixed midpoint as fallback.
- Stop loss is always placed beyond the Protected Swing (c2_low for buys, c2_high for sells).

**Equilibrium formula:** `TSpot_Midpoint = (CandleHigh + CandleLow) / 2` — used for zone boundary only, not as entry price [EVIDENCE-BACKED — AGENTS.md §XVI Gate 4, §XVII].

### 2.5 Protected Swings and Continuation Order Blocks

Protected swings provide the structural backbone for stop placement, invalidation logic, and continuation entry identification. They form either from fair value gaps or from sweeping highs/lows, validated by a closure through the opposing candles.

Continuation order blocks act as stepping stones for additional entries. When building pyramiding execution models around these continuation blocks, the logic must rely entirely on standalone closure confirmation for each independent addition.

### 2.6 Reversal Sequence Entry Models

The recommended primary trigger for EA implementation is the CISD, as it is highly objective and computationally verifiable.

| Entry Model | Confirmation Level | Description | Risk Level |
| :--- | :--- | :--- | :--- |
| **Purge / Turtle Soup** | Lowest | Sweep of liquidity at a high or low | Highest |
| **Inversion** | Low-Medium | Price reclaims a fair value gap that was previously unfilled | High |
| **CISD** | Medium | Candle closes through opposing candles' open | Medium (Baseline) |
| **Fair Value Gap** | Medium-High | Three-candle pattern leaving an imbalance | Medium |
| **Breaker Block** | Highest | Final piece of structure before expansion | Lowest |

### 2.7 Standard Deviation Projections

Projections are mechanical target levels derived from the manipulation leg (C2's sweep) using Fibonacci levels (1, 0, -1, -2, -2.5, -4). The -2 to -2.5 levels act as the primary reaction area, while -4 represents maximum expansion.

### 2.8 SMT Divergence as Gate (Mandatory for C2)

SMT divergence is a mandatory gate for C2 setups. The signal is only STAGE_READY if SMT Divergence is detected with a correlated asset. SMT Divergence: The correlated asset makes a lower low (for bullish setups) or higher high (for bearish setups) while the primary asset does not confirm.

**Correlated asset pairs:**
| Primary | Correlated |
|---------|------------|
| EURUSD | GBPUSD |
| GBPUSD | EURUSD |
| USDJPY | USDCHF |
| XAUUSD | XAGUSD |

SMT Divergence is NOT required for C3 or C4 setups. Marker: `[SMT_DIVERGENCE_PASS]` or `[SMT_DIVERGENCE_FAIL]` [EVIDENCE-BACKED — AGENTS.md §XIX].

### 2.9 Time-Sensitivity Filter

Before advancing to STAGE_READY, the EA must calculate HTF candle progress:
```
elapsed = currentTime - candleOpenTime
duration = nextCandleOpenTime - candleOpenTime
progress = elapsed / duration
```
If `progress > 0.80` (80% of HTF candle duration has elapsed), the signal is invalidated. The rationale: there must be "enough time in the candle to continue expansion." The signal may re-evaluate on the next HTF candle open. Marker: `[TIME_FILTER_PASS]` or `[TIME_FILTER_BLOCK]` with progress value [EVIDENCE-BACKED — AGENTS.md §XIX].

### 2.10 The Four-Gate Boolean Hierarchy

The EA is a Boolean Engine. Every trade must pass through four mandatory hierarchy gates in sequence [EVIDENCE-BACKED — AGENTS.md §XVII]:

1. **Gate 1 — HTF Bias Identification:** D1 for Branch A, W1 for Branch B. Bias determined by the Next Day/Week Model (opening price range relative to previous close). Marker: `[BIAS_ALIGNED]` or `[BIAS_MISALIGNED]`.

2. **Gate 2 — Volatility Filter (50% Wick Rule):** Structure TF candle (H1/H4). If `wickRatio > 0.5`, the candle is a reversal signature — no expansion trades. Marker: `[WICK_RULE_PASS]` or `[WICK_RULE_BLOCK]`.

3. **Gate 3 — ITF Structural Confirmation (Mechanical CISD):** Price must close beyond the opening price of the initiating candle of the opposing delivery series. Marker: `[CISD_CONFIRMED]` or `[CISD_FAILED]`.

4. **Gate 4 — LTF Execution (T-Spot POI Mapping):** Zone-based entry from Equilibrium to HTF High/Low. Scan for PD Array. Marker: `[TSPOT_POI_MAPPED]` or `[TSPOT_POI_MISSING]`.

**Gate Failure Behavior:** Any gate failure returns the signal to the previous gate's evaluation cycle. A signal may not be Locked until all four gates have passed.

### 2.11 Lineage and Metadata

Lineage fields (`m_upgradedFromC2`, `m_c3ParentC2Guid`, `SSequenceLineage`) are descriptive metadata only [EVIDENCE-BACKED — AGENTS.md §IV]. They serve forensic tracing, backtest analytics, and relationship mapping. They must NOT be used for:
- Mode assignment (executionMode is determined by closureType)
- Risk profile selection (riskProfileLineage is owned by ModeResolver)
- Stage transitions (lifecycleStage is owned by LockedSignal)
- Branch routing (branchOwnership is owned by BranchEvaluator)

---

## 3. Branch-by-Branch Behavior

The EA operates in strictly isolated branches [EVIDENCE-BACKED — AGENTS.md §I, BranchEvaluator.mqh isolation]. The entry timeframe is always appropriately matched to the structural timeframe, maintaining necessary fractal alignment. Branches are structural execution domains, NOT mode containers — both Anticipation and Confirmation modes exist inside both branches.

### 3.1 Intraday Branch: D1 — H1 — M5
* **Daily (D1):** Establishes directional bias (Next Day Model).
* **Hourly (H1):** Provides structural confirmation (C1-C2-C3) and CISD.
* **5-Minute (M5):** Entry refinement and execution within the H1 T-Spot zone.

### 3.2 Swing Branch: W1 — H4 — M15
* **Weekly (W1):** Establishes directional bias (Next Week Model) and liquidity targets. Branch B targets are projected from Weekly liquidity zones [EVIDENCE-BACKED — AGENTS.md §I Anchor TF Notes].
* **4-Hour (H4):** Structural confirmation and sequence detection.
* **15-Minute (M15):** Precise entry refinement and execution within the H4 T-Spot zone.

### 3.3 Branch Isolation Rules
- Branch A and Branch B are fully isolated. No signal, state, or resource from one branch may influence the other [EVIDENCE-BACKED — AGENTS.md §I, Branch Isolation Rules].
- Each branch owns its own signal store slots, narrative objects, and context tracker.
- Mode resolution is per-branch: branchA.mode and branchB.mode are independent.

---

## 4. State Machine and Trade Lifecycle

The model utilizes deterministic state-machine logic to ensure phases are never skipped. The lifecycle applies independently per signal, with C2 and C3 each having full pipeline paths.

| State | Responsibility | Transition Trigger (Next State) | Failure Handler |
| :--- | :--- | :--- | :--- |
| **WAIT** | Monitor for closure formation (C2 sweep+close, C3 engulf, or C4 expansion) | Valid closure detected → `SETUP_DETECTION` | Continue monitoring |
| **SETUP_DETECTION** | Validate closure extreme & HTF bias | HTF bias aligns + closure confirmed → `VALIDATION` | Return to `WAIT` |
| **VALIDATION** | Confirm CISD present & T-Spot | CISD confirmed in T-Spot → `STAGING` | Return to `WAIT` |
| **STAGING** | Calc position size & check margin | Margin OK + Spread OK → `ENTRY` | Return to `VALIDATION` |
| **ENTRY** | Execute OrderSend; verify fill | OrderSend success → `POSITION` | Return to `STAGING` (max 3 retries) |
| **POSITION** | Monitor SL/TP; trail stop | TP/SL hit or structure invalidated → `EXIT` | N/A |
| **EXIT** | Close position; reset state | Position closed → `WAIT` | Emergency close alert |

**Gate-to-State Mapping:**
| State | Gate Evaluated | Description |
|-------|---------------|-------------|
| WAIT / SETUP_DETECTION | Gate 1 — HTF Bias ID | Branch bias aligned |
| SETUP_DETECTION → VALIDATION | Gate 2 — Wick Rule | Structure TF wick ratio ≤ 0.5 |
| VALIDATION | Gate 3 — CISD | Mechanical CISD confirmed on Structure TF |
| STAGING / STAGE_READY | Gate 4 — T-Spot POI | PD Array found inside T-Spot zone |

No signal may advance beyond its current state until its corresponding gate passes. A gate failure returns the signal to the prior state's evaluation cycle [EVIDENCE-BACKED — AGENTS.md §XVI].

**Closure-type specific behavior:**
- **C2** locks with MODE_ANTICIPATION, transitions to STAGE_WAITING_FOR_POI after commit, and awaits T-Spot zone entry for release to STAGE_READY [EVIDENCE-BACKED — AGENTS.md §III, ClosureEngine.mqh C2 path].
- **C3** locks with MODE_CONFIRMATION (or MODE_ANTICIPATION if demoted via g_C3_RUNTIME_DISABLED), requires CISD confirmation and D1 alignment, and transitions through STAGE_READY → RG_GATE → EXEC_TRIGGER.
- **C4** is always MODE_CONFIRMATION. It flows through the C3 pipeline (`signal_c3 = signal_c4` in implementation) and requires C3 alignment (structural range reference) when C3 is enabled, or may expand from C2 extremes when C3 is disabled.

### 4.1 Standalone Pipeline Paths
- **Standalone C2:** C2 may lock, commit, and execute without C3 involvement. C2 validates itself via sweep of C1 extreme + close back inside C1 range + protected swing anchoring + POI [EVIDENCE-BACKED — ClosureEngine.mqh IsValidC2Standalone()].
- **Standalone C3:** C3 may be detected, evaluated, and locked from a narrative without a prior C2 signal object [EVIDENCE-BACKED — ClosureEngine.mqh C3 fallback path].
- **Standalone C4:** Not defined. C4 requires either C3 (when enabled) or C2 (when C3 disabled) as a structural reference.

---

## 5. Data Model and Metadata Requirements

### 5.1 Signal Truth Separation

Every signal carries three distinct truths [EVIDENCE-BACKED — AGENTS.md §V, LockedSignal.mqh]:

| Truth | Field | Meaning |
|-------|-------|---------|
| Entry | candidateEntryPrice | Entry price at signal detection |
| Request | requestedEntryPrice | Price sent to broker (0 until sent) |
| Fill | actualFillPrice | Confirmed fill from DEAL_PRICE |

### 5.2 Data Fields

| Stage | Field | Description | Source |
| :--- | :--- | :--- | :--- |
| **Setup** | `setup_id` | Unique GUID for the setup, assigned once at Lock, immutable | Generated by LockedSignal::Lock() |
| | `direction` | Long or Short | Derived from C2/C3 structure |
| | `c1_high`, `c1_low`| Reference candle extremes | Historical price data |
| | `protected_swing`| Protected high/low for stop | Derived from FVG/sweep |
| | `continuationLineage` | Narrative state at time of lock (descriptive metadata) | ClosureState SLineage |
| | `m_upgradedFromC2` | Descriptive flag indicating C3 was derived from C2 context | [INTERPRETIVE — lineage field] |
| | `m_c3ParentC2Guid` | Descriptive reference GUID for forensic tracing | [INTERPRETIVE — lineage field] |
| **Fill** | `actual_entry` | Broker-reported fill price | OrderSend / OnTrade |
| | `position_ticket`| Broker-assigned position ticket | OrderSend result |
| **Post-Fill** | `stop_loss_price`| Actual stop loss level | PositionGetDouble |
| | `closure_reason` | TP, SL, Invalidation, Manual | Exit condition detector |

### 5.3 GUID Ownership Rules

- GUID is assigned once at Lock and is immutable for the life of the signal [EVIDENCE-BACKED — AGENTS.md §II].
- GUID is SOLELY owned by LockedSignal. No other subsystem may reassign, reuse, or clear a GUID.
- GUID reuse across signals is a constitutional violation (`[GUID_DUPLICATE_BLOCKED]`).

---

## 6. Risk, Stops, and Trade Management

* **Position Sizing:** `Position Size = Risk Amount / Stop Distance`. Risk is typically 0.5% to 2% of account equity per trade.
* **Stop Loss Placement:** Stops are placed structurally beyond the most recent protected swing. SL anchoring uses c2_low for buys, c2_high for sells [EVIDENCE-BACKED — AGENTS.md §VI]. ATR is used for volatility context only — it NEVER defines SL/TP/trailing levels [EVIDENCE-BACKED — AGENTS.md §VI: "ATR Usage: VOLATILITY CONTEXT ONLY — NEVER defines SL/TP/trailing"].
* **Trailing Stops:** Implements a "ratchet" effect — trailing the stop beyond newly formed protected swings strictly in the favorable direction.
* **Exits:** Minimum TP is 2R. The 2R gate is a viability gate, not a TP target [EVIDENCE-BACKED — AGENTS.md §VI]. Breakeven triggers at 1R. Structural invalidation overrides all profit metrics, triggering an immediate exit.
* **Risk Floor:** Lot calculation failure must emit `[RISK_FLOOR_BLOCK]` with explicit reason.

---

## 7. MQL5 Execution Architecture

The execution environment demands rigorous architectural discipline separated by event handlers (`OnTick`, `OnTrade`).

**Crucial Development Constraints:**
To guarantee seamless compilation in MetaEditor and prevent execution anomalies, the codebase must operate strictly within standard MQL5 parameters. The use of advanced C++ syntax, STL patterns, or C++ style references is strictly forbidden.

Furthermore, if graphical interfaces or dashboards are integrated for trade monitoring, they must utilize standard chart objects (e.g., `OBJ_LABEL`, `OBJ_BITMAP_LABEL`). Development must avoid `CCanvas`-based implementations to ensure maximum platform compatibility and resource efficiency during high-frequency execution.

### State Machine Implementation Example
```cpp
enum ENUM_TTFM_STATE {
    STATE_WAIT = 0,
    STATE_SETUP_DETECTED = 1,
    STATE_VALIDATED = 2,
    STATE_STAGED = 3,
    STATE_ENTRY_PENDING = 4,
    STATE_IN_POSITION = 5,
    STATE_EXITING = 6
};

ENUM_TTFM_STATE current_state = STATE_WAIT;

void OnTick() {
    if (!IsSpreadAcceptable() || !IsWithinKillZone()) return;
    
    switch(current_state) {
        case STATE_WAIT: CheckForSetup(); break;
        case STATE_SETUP_DETECTED: ValidateSetup(); break;
        case STATE_VALIDATED: StageEntry(); break;
        case STATE_STAGED: ExecuteEntry(); break;
        case STATE_IN_POSITION: ManagePosition(); break;
        case STATE_EXITING: CompleteExit(); break;
    }
}
```

### Architectural Governance
All runtime markers must use `[DOMAIN_VERB]` form with no version suffixes [EVIDENCE-BACKED — AGENTS.md §VIII]:
- `[SIGNAL_LOCKED]`, `[STATE_TRANSITION_OK]`, `[ENTRY_CANDIDATE_SET]`
- `[EXEC_TRIGGER]`, `[ORDER_SENT]`, `[RISK_FLOOR_BLOCK]`
- `[STATE_MUTATION]`, `[GUID_DUPLICATE_BLOCKED]`, `[HANDOVER_TIMEOUT]`
- `[C2_ACCEPTED]`, `[C3_ACCEPTED]`, `[C4_ACCEPTED]`
- `[C3_DEMOTED_TO_C2]`, `[C4_BLOCKED]`

---

## 8. Failure Modes and Common Implementation Traps

| Trap | Impact | Mitigation |
|------|--------|------------|
| **Entering Too Early** | High false signal rate | Wait for definitive closure of the triggering candle (C2 sweep+close or C3 engulf) before SETUP_DETECTION. Do not assume C3 must validate C2 — validate each closure type independently. |
| **Stage Pollution (C3→C2)** | C2 lock blocked because C3's stage leaked into shared lockedSignal | Use separate local SLockedSignal instances for C3/C4 and C2 paths. Each closure type must have its own lifecycle stage. [EVIDENCE-BACKED — PostFix Investigation, C3 Resurrection fix] |
| **GUID Duplication** | Signal rejected at commit with `[GUID_DUPLICATE_BLOCKED]` | Ensure SLockedSignal::Reset() is called before each Lock() to clear stale GUID values. Generate GUID once at Lock via LockedSignal. [EVIDENCE-BACKED — PostFix Investigation, GUID root cause] |
| **Entry Price Zero** | Signal blocked at `[ENTRY_CANDIDATE_INVALID]` | entry_price must be explicitly assigned from c4_open or LTF intersection after detection. EvaluateC2Closure and EvaluateC3Closure set entry_price=0.0 — downstream assignment must follow. [EVIDENCE-BACKED — PostFix Investigation, Comprehensive Investigation §B] |
| **Timeframe Misalignment** | Trades against broader flow | Demand triple-alignment (Bias + Structure + Entry) boolean gate. |
| **Phantom Setups** | Entries based on stale data | Validate closures continuously; discard setups if structural justification vanishes. |
| **Ignoring Kill Zones** | Low liquidity/high spread | Time filters enforcing London & NY AM sessions. |
| **Handover Deadlock** | Signal slot stuck with `[STATE_GHOST_BLOCKED]` | Handover lock is temporary (≤5s). If exceeded, force-clear with `[HANDOVER_TIMEOUT]`. No subsystem may clear a slot under active handover. [EVIDENCE-BACKED — PostFix Investigation, LockedSignal.mqh handover guard] |

---

## 9. What a Correct EA Should Do Differently

 1. Validate each closure type independently — C2 does not require C3, and C3 does not require a prior C2 trade.
 2. Validate CISD on every bar during the setup phase.
 3. Demands triple timeframe alignment (Anchor + Structure + Entry).
 4. Anchors stops structurally beyond identified protected swings. ATR is volatility context only — never defines SL/TP/trailing.
 5. Calculates R-based targets strictly from actual broker fill prices.
 6. Executes immediate structural invalidation closures.
 7. Enforces Kill Zone trading.
 8. Strict margin validation and risk bounding.
 9. Maintains persistent GUID-based tracking — GUID assigned once at Lock, immutable, sole-owned by LockedSignal.
 10. Generates detailed CSV forensic logs of all transitions and state variables.
 11. Uses separate SLockedSignal instances per closure type to prevent stage pollution.
 12. Preserves standalone C2 and standalone C3 evaluation paths as constitutionally valid.
 13. Enforces the Boolean Engine Four-Gate Hierarchy — no signal is Locked until all gates pass.
 14. Applies the 50% Wick Rule on the Structure TF before attempting expansion trades.
 15. Maps T-Spot as a zone (not fixed midpoint) and requires a PD Array for entry_price assignment.
 16. Checks HTF candle progress (time-sensitivity) before advancing to STAGE_READY.
 17. Requires SMT Divergence for C2 STAGE_READY.

---

## 10. Personas

### The Logic Guard
- **Responsibility:** Reject any setup that lacks a mechanical CISD or violates the 50% Wick Rule.
- **Authority:** Gate 2 (Wick Rule) and Gate 3 (CISD) enforcement. No signal may pass these gates without explicit `[WICK_RULE_PASS]` and `[CISD_CONFIRMED]` markers.
- **Scope:** Both branches, all closure types.
- **Failure mode:** A signal that bypasses the Logic Guard results in a CONSTITUTIONAL_FAILURE.

### The Risk Architect
- **Responsibility:** Enforce the 2R Viability Gate.
- **Method:** After T-Spot POI is mapped (Gate 4), calculate:
  ```
  riskDistance = abs(entry_price - protectedSwingPrice)
  rewardDistance = abs(htfTarget - entry_price)
  rMultiple = rewardDistance / riskDistance
  ```
- If `rMultiple < 2.0`, the trade is discarded.
- **Authority:** Final viability check before `STAGE_READY`.
- **Scope:** Both branches, all closure types.
- **Tools:** Uses `OrderCalcProfit()` with minLot to verify broker-projected risk vs. budget.
- **Failure mode:** If 2R viability fails, emit `[RISK_2R_VIOLATION]` with computed R value.

### The Broker Detailer
- **Responsibility:** Ensure `OrderCalcProfit()` and `SYMBOL_TRADE_TICK_VALUE` are leveraged to support micro-lot assets (e.g., GOLDmicro) on small equity.
- **Method:**
  1. Always use `OrderCalcProfit()` for risk projection, not simplified formulas.
  2. Cross-reference `SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE)` for accurate monetary conversion.
  3. Verify minLot affordability through `IsLotTradeable()` before execution.
- **Authority:** Risk calculation integrity. All risk numbers used in decision-making must come from broker API calls, not derived formulas.
- **Scope:** Pre-execution risk validation, order sizing.
- **Failure mode:** If `OrderCalcProfit()` returns inconsistent results, fall back to formula but log both values and label the decision value explicitly.

---

## 11. Open Questions and Unresolved Ambiguities

The following areas remain ambiguous based on available source material. They are labeled as [INTERPRETIVE] or [UNKNOWN / OPERATIONAL DECISION] to distinguish them from evidence-backed claims.

| Question | Classification | Why It Matters |
|----------|---------------|----------------|
| Does TTrades itself require C3 closure before C2 structural validation? | [INTERPRETIVE] | The Quant-Grade reconstruction asserted this as a strict rule, but the OmakFxYO implementation permits standalone C2. The original TTrades PDFs are not in the workspace to verify. |
| Does TTrades define C4 as a distinct signal type or as a continuation event tracked within C3 narrative? | [INTERPRETIVE] | The current implementation represents C4 as CLOSURE_C4 for pipeline consistency. Whether TTrades treats C4 as a peer signal or purely as an event is unresolved. |
| What is the exact TTrades definition of "C3 alignment" in the context of C4 validation? | [INTERPRETIVE] | The current architecture interprets this as structural range reference (C4 expands from C3 range). The original TTrades framing may differ. |
| The exact proprietary underlying formula for certain nuanced T-Spot edge cases. | [UNKNOWN / OPERATIONAL DECISION] | The T-Spot midpoint formula `(high + low) / 2` is implemented. Edge case refinement is an operational decision. |
| The proprietary weights driving "Auto Bias 1 and 2". | [UNKNOWN / OPERATIONAL DECISION] | These weights are not present in available material. The EA uses a simpler D1 Next Day Model for bias. |
| Formal re-entry handling logic for C4 continuation properties. | [INTERPRETIVE] | C4 re-entry is handled by scanning for additional C4 events (c4EventCount < 3). Whether TTrades specifies distinct re-entry rules is unknown. |
| Handling of weekend gaps and major fundamental news embargoes. | [UNKNOWN / OPERATIONAL DECISION] | No TTrades material on gap/news handling is available. This is an operational decision for the EA. |
| Does TTrades specify the 50% Wick Rule as a hard gate, or is it an operational interpretation? | [INTERPRETIVE] | The 50% Wick Rule is documented as a hard gate in AGENTS.md §XVI. Whether TTrades sources define it as a mandatory filter or a discretionary guideline is unresolved. |
| What is the exact TTrades definition of "series of candles" for mechanical CISD confirmation? | [INTERPRETIVE] | The mechanical CISD rule requires closing beyond the opening price of the initiating candle of a consecutive close series. The exact number of candles constituting a "series" in TTrades doctrine is an operational decision. |
| Does TTrades define a time-sensitivity filter (80% HTF candle rule)? | [INTERPRETIVE] | The 80% rule is documented as a hard gate in AGENTS.md §XVII to ensure sufficient expansion time. Whether this originates from TTrades or is an operational decision is unclear. |

---

## 12. Implementation Checklist for Code Review

 * [ ] Daily bias correctly extracted via the Next Day Model.
 * [ ] Closure detection correctly identifies C2 (sweep+close-inside) and C3 (engulf/displacement) as independent paths.
 * [ ] C4 evaluated as continuation/expansion event from C3 range (or C2 extremes when C3 disabled).
 * [ ] Multi-timeframe CISD triggers accurately modeled.
 * [ ] Entry TF validations inside computed T-Spot ranges.
 * [ ] MQL5 Strict Mode adhered to (No STL, No C++ refs).
 * [ ] UI rendered with standard chart objects (OBJ_LABEL / OBJ_BITMAP_LABEL).
 * [ ] Asynchronous OrderSend execution with 3-attempt retry blocks.
 * [ ] GUID-based tracking active in position comment properties — GUID immutable after Lock.
 * [ ] Immediate execution halts upon structural invalidation criteria.
 * [ ] Standalone C2 path preserved (IsValidC2Standalone).
 * [ ] Standalone C3 path preserved (C3 fallback block).
 * [ ] Stage pollution prevented (separate SLockedSignal per closure type).
 * [ ] Handover lock ≤5s with timeout force-clear.
 * [ ] Lineage fields used for forensics only, not authoritative state decisions.
 * [ ] Four-Gate Hierarchy enforced — no signal Locked until all gates pass.
 * [ ] Wick Rule applied on Structure TF — reversal candles blocked from expansion.
 * [ ] Mechanical CISD — price must close beyond opening price of initiating candle of series.
 * [ ] T-Spot treated as zone (Equilibrium to HTF High/Low), not fixed midpoint.
 * [ ] PD Array scanned inside T-Spot zone — fixed midpoint fallback prohibited.
 * [ ] Time-Sensitivity Filter — signals invalidated if >80% of HTF candle elapsed.
 * [ ] SMT Divergence gate enforced for C2 STAGE_READY.
 * [ ] 2R Viability Gate — measured from T-Spot POI to Protected Swing.

---

## 13. References

 1. TTrades Fractal Model PDF Series (Understanding T-Spot, Continuations, Reversals, Alignment) — not in workspace [INTERPRETIVE].
 2. TTrades Blog: Change in State of Delivery, Using Equilibrium, Protected Swings, Standard Deviation Projections — not in workspace [INTERPRETIVE].
 3. Inner Circle Trader (ICT) Concept Repository (CISD, IPDA).
 4. TradingWyckoff / Candle Range Theory (CRT) Explanatory Documentation.
 5. TTFM Pro Fractal Indicator Logic Guide (Scribd) — not in workspace [INTERPRETIVE].
 6. AGENTS.md — OmakFxYO Constitutional Runtime Governance [EVIDENCE-BACKED — project constitution].
 7. TTFM_Ground_Truth_Alignment.md — Source-grounding audit of claims vs evidence [EVIDENCE-BACKED — audit report].
 8. OmakFxYO_PostFix_Deep_Investigation.md — Root-cause analysis of runtime failures [EVIDENCE-BACKED — investigation report].
 9. ClosureEngine.mqh, LockedSignal.mqh, CoreTypes.mqh — Implementation source [EVIDENCE-BACKED — executable behavior].
10. AGENTS.md §XVI — Boolean Engine Four-Gate Hierarchy [EVIDENCE-BACKED].
11. AGENTS.md §XVII — Hard Logic Parameters (Wick Rule, Mechanical CISD, T-Spot POI, Time Filter, SMT Divergence) [EVIDENCE-BACKED].
12. AGENTS.md §XVIII — Personas (Logic Guard, Risk Architect, Broker Detailer) [EVIDENCE-BACKED].

---

*This document is a working architecture reconstruction. Claims are classified as [EVIDENCE-BACKED] where supported by workspace sources or verified implementation behavior, and [INTERPRETIVE] where reconstructed without original TTrades source material. No source code was modified in the production of this revision.*
