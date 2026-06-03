OmakFxYO — Backtest Log Forensic Analysis v06 (Model‑Aligned)

Pipeline Health, Execution Audit, Blind‑Spot Detection & Code‑to‑Log Root‑Cause Tracing
Aligned to TTrades Fractal Model + CRT + Dow Theory

---

CONTEXT (Read‑Only)

You are auditing the OmakFxYO EA — an MT5 Expert Advisor that trades the TTrades Fractal Model + Dow Theory + Candle Range Theory (CRT). The architecture is defined in the project's AGENTS.md and Risk Dossier. Key rules (model‑aligned):

· Stop‑loss = C2 candle extreme (protected swing) for both C2 and C3 closures. No ATR‑based stops.
· Take profit is not a fixed multiple; 2R is a minimum gate check, not the TP price. Orders may be sent with TP=0 when no structural target is computable, but the EA now also applies CRT full target (C1 opposite extreme) as a primary exit.
· C3 closure (Confirmation Mode) MUST align with D1 bias; C2 closure (Anticipation Mode) does NOT.
· C2 closure and C3 closure pipelines are independent (separate slots, evaluation, bias gating), but C3 closure is a fallback when C2 candle fails reversal.
· C1 must be at an HTF Point of Interest (swing, FVG, OB) for both C2 and C3 closures to be valid.
· Top‑down context: D1 bias → HTF confirmation (CISD or C2/C3 closure on HTF) → LTF CISD → execution.
· Trailing stop uses Protected Swing Lows/Highs on the entry timeframe, not fixed points.
· Exits: 1) CRT full target, 2) CISD reversal, 3) Dow BOS, 4) Protected swing breach (trailing SL).
· Pyramiding only at new protected swings, not on every C3 closure.
· Account Guard: daily loss blocks new entries only; catastrophic floor closes positions and allows recovery.

Critical Terminology (model‑exact):

Term Meaning
C2 candle The second bar in C1→C2→C3 sequence; sweeps C1’s extreme.
C2 closure Reversal signal: C2 candle sweeps C1 extreme AND closes back inside C1’s high‑low range. (Anticipation Mode)
C3 candle The third bar.
C3 closure Fallback signal: C3 candle engulfs C2’s body without sweeping C2’s extreme. (Confirmation Mode) Must align with D1 bias.
C2 wick filter If C2 candle has large wick (>60%), wait for C3 candle (not a closure). Not a signal type.
Protected Swing A confirmed swing low (PSL) or swing high (PSH) used for trailing stop.
C1‑at‑POI C1 must overlap an HTF structural level (swing/FVG/OB).
CISD Change in State of Delivery — reversal confirmation on a timeframe.
CRT full target Opposite extreme of C1 range (C1 high for buys, C1 low for sells).

---

PARAMETERS 
```
TARGET_LOG:       20260524.log
LOG_PATH:         /home/zoro/.var/app/com.usebottles.bottles/data/bottles/bottles/MetaTrader-5/drive_c/Program Files/MetaTrader 5/Tester/Agent-127.0.0.1-3000/logs/

PARSER_SCRIPT:    OmakFxYO/scripts/omak_forensic_engine.py

REPORT_PATH:      OmakFxYO/Quant_Backtest_Reports/OmakFxYO_Quant_Forensic_Report_41.md

DECODED_LOG:      /tmp/omak_decoded.log
```

Rules:

· Go directly to LOG_PATH — it is an absolute path.
· Decode the entire log using the parser script. No sampling.
· Every claim must cite a log line (timestamp + excerpt) and a code location (file:line).
· The report must use the model‑aligned terminology exactly as defined above.

---

STAGE 0 — DECODE THE LOG

```bash
python3 OmakFxYO/scripts/omak_forensic_engine.py \
  --input "LOG_PATH/20260524.log" \
  --output "/tmp/omak_decoded.log"
```

Verify: wc -l /tmp/omak_decoded.log. Capture the EA_BUILD line if present.

---

STAGE 1 — PRE‑AUDIT: Marker Verification & Runtime Parameters

1.1 Core Pipeline Markers

Marker Expected File Found in Log?
[GUID_ASSIGNED] LockedSignal.mqh:282 
[SIGNAL_LOCKED] ClosureEngine.mqh:2171 
STAGE_READY (in FSM) ClosureEngine.mqh:2633 
[RG_GATE_PASS] RiskGate.mqh:996 
[EXEC_TRIGGER] OrderManager.mqh:1493 
[ORDER_SENT] OrderManager.mqh:1500 
[ORDER_FAIL] RiskGate.mqh:1058 
[BIAS_ALIGN] BiasResolver.mqh 
[C2_REJECT] ClosureEngine.mqh 
[C2_CLOSURE_DETECTED] ClosureEngine.mqh 
[C2_LOCK_ATTEMPT] ClosureEngine.mqh 
[MODAL_UPGRADE] BranchEvaluator.mqh:816 
[ACCOUNT_GUARD_DAILY_LOSS] OmakFxYO.mq5:4044 
[ACCOUNT_GUARD_EMERGENCY] OmakFxYO.mq5 
[EMERGENCY_CLOSE] OmakFxYO.mq5 

1.2 New Model‑Faithful Markers (Post‑Fix Verification)

Marker Expected File Purpose Found in Log?
[C1_POI_VALID] ClosureEngine.mqh C1 overlaps HTF POI 
[C1_POI_MISS] ClosureEngine.mqh C1 not at POI → rejection 
[C3_FALLBACK] ClosureEngine.mqh C3 closure detected as fallback (C2 failed reversal) 
[CONTEXT] D1_BIAS=... HTF_CISD=... LTF_CISD=... BranchEvaluator.mqh Top‑down context gate 
[TRAIL_PSL] / [TRAIL_PSH] PositionManager.mqh Structural trailing stop modification 
[C2_WICK_FILTER] C2WickFilter.mqh C2 candle large wick → wait for C3 candle 
[PYRAMID_ADD] CampaignManager.mqh Pyramid layer added at new protected swing 

1.3 Exit Markers

| Marker | Expected File | Purpose |
|--------|--------------|---------|
| [EXIT_CRT_TARGET] | OmakFxYO.mq5 | CRT full target: price hit C1 opposite extreme |
| [EXIT_CISD_REVERSAL] | OmakFxYO.mq5 | Opposite-direction CISD on entry TF |
| [EXIT_DOW_BOS] | OmakFxYO.mq5 | HTF Dow break of structure |
| [EXIT_TRAIL_STOP] | OmakFxYO.mq5 | Structural protected swing trail hit |
| [EXIT_SL_HIT] | OmakFxYO.mq5 | Initial stop loss hit |
| [EXIT_EMERGENCY_CLOSE] | OmakFxYO.mq5 | Account guard emergency close |

1.3 Blind‑Spot Detection Markers

Marker Expected File Purpose
[SL_CALC] ClosureEngine.mqh Stop‑loss calculation
[SL_PROTECTED_SWING] ClosureEngine.mqh C2 protected swing stop
[TP_CALC] OmakFxYO.mq5 Take‑profit calculation
[RG_TP_DEFERRED] RiskGate.mqh TP deferred when tpPrice=0
[RG_GATE_FAIL] RiskGate.mqh All gate failure reasons
[EXEC_GATE_BLOCKED] OmakFxYO.mq5 Post‑trigger gate block
[COMMIT_REJECT] ClosureEngine.mqh Pre‑lock bias reject
[SL_TRACE] various Stop‑loss propagation trace
[RISK_GATE] OmakFxYO.mq5 Min‑lot risk gate
[ENTRY_DISTANCE_GATE] RiskGate.mqh Entry proximity gate
[PYRAMID_BLOCKED] OmakFxYO.mq5 Pyramid heat cap
[ENTRY_BLOCKED] OmakFxYO.mq5 Daily loss entry block

1.4 Runtime Parameter Consistency Check

Search the log for: InpMaxDailyLossPercent=, InpCatastrophicFloorPercent=, InpDynamicFloorPercent=, InpRiskRewardRatio=, InpConfirmationRR=, InpTrailingStart=, InpTrailingStep=, InpMaxC2WickPercent=, etc.

Compare each to the declared default in OmakFxYO.mq5. Flag any mismatch — this indicates Strategy Tester cached old parameters.

Note: InpTrailingStart and InpTrailingStep may now be irrelevant if structural trailing is active; however they still exist as inputs. Report if they appear and their values. If structural trailing logs ([TRAIL_PSL]) are absent while these parameters are non‑zero, the EA is still using the old fixed‑point trail → P0 regression.

---

STAGE 2 — PIPELINE HEALTH SNAPSHOT

Run counts:

```bash
grep -c "\[GUID_ASSIGNED\]" /tmp/omak_decoded.log
grep -c "\[SIGNAL_LOCKED\]" /tmp/omak_decoded.log
grep -c "STAGE_READY" /tmp/omak_decoded.log
grep -c "\[RG_GATE_PASS\]" /tmp/omak_decoded.log
grep -c "\[EXEC_TRIGGER\]" /tmp/omak_decoded.log
grep -c "\[ORDER_SENT\]" /tmp/omak_decoded.log
grep -c "deal performed\|DEAL_ENTRY\|\[DEAL_TRACK\]" /tmp/omak_decoded.log
grep -c "\[ORDER_FAIL\]" /tmp/omak_decoded.log
grep -c "\[C2_CLOSURE_DETECTED\]" /tmp/omak_decoded.log
grep -c "\[C1_POI_VALID\]" /tmp/omak_decoded.log
grep -c "\[C1_POI_MISS\]" /tmp/omak_decoded.log
grep -c "\[C3_FALLBACK\]" /tmp/omak_decoded.log
grep -c "\[CONTEXT\]" /tmp/omak_decoded.log
```

Produce a survival table. For each drop‑off >5%, extract examples and state the exact rejection marker. Pay special attention to:

· GUID_ASSIGNED vs SIGNAL_LOCKED: how many failed due to [C1_POI_MISS]?
· SIGNAL_LOCKED vs STAGE_READY: how many are waiting for LTF CISD (context)?
· RG_GATE_PASS vs EXEC_TRIGGER: any killed by [PYRAMID_BLOCKED]?
· ORDER_SENT vs actual deals: any [ORDER_FAIL] or untracked closures?

---

STAGE 3 — DEEP SIGNAL DEATH INVESTIGATION

Trace the full lifecycle of at least 5 individual signals (first 5 GUIDs, and 5 from mid‑test). Build a timeline for each:

1. Closure type (C2 closure or C3 closure)
2. Entry price, stop loss, take profit at each stage (snapshot)
3. If it died, at what stage and exact rejection marker
4. If it passed the gate but didn’t execute, what post‑trigger check killed it (e.g., heat cap, context missing)
5. For executed trades:
   · Was the trailing stop modified? Show [TRAIL_PSL] or [TRAIL_PSH] logs.
   · How did the trade exit? [EXIT_CRT_TARGET], [EXIT_CISD_REVERSAL], [EXIT_DOW_BOS], [STOP_LOSS], [EMERGENCY_CLOSE]?
6. If a trade was stopped out by a fixed‑point trail ([TRAIL] with profit points but no TRAIL_PSL), flag as P0 regression — the structural trail is not active.

For each GUID, reference the [SNAPSHOT_SL] and [SL_PROTECTED_SWING] lines and verify they match. If the SL changes later without a TRAIL_PSL marker, identify the code path responsible.

---

STAGE 4 — CONFIGURATION CONSISTENCY AUDIT

Extract runtime values from the log and compare to source defaults:

Parameter Log Value Code Default Match? Notes
InpConfirmationRR    
InpRiskRewardRatio    RR gate now uses ≥ 2.0?
InpTrailingStart    Should be 0 if structural trail active
InpTrailingStep    Should be 0 if structural trail active
InpMaxC2WickPercent    Must be 0.6 (60%) after fix
InpCatastrophicFloorPercent    Should use initial deposit now
InpDynamicFloorPercent    
InpMaxDailyLossPercent    Only blocks entries, not closes
InpEnablePyramiding    
InpMaxPyramidOrders    Added only at new protected swings?

Flag any mismatches and state which line in OmakFxYO.mq5 holds the declaration.

---

STAGE 5 — POST‑FIX VERIFICATION (Model‑Aligned)

Verify these model‑aligned fixes are active:

Fix Expected Log Marker Found? If not, implication
C1‑at‑POI validation [C1_POI_VALID] or [C1_POI_MISS]  C2/C3 closures may still be using sweep‑targeting
C3 fallback (C2 failed) [C3_FALLBACK] with specific reason  C3 pipeline still treating as independent
Top‑down context gate [CONTEXT] with tiers  Trades executed without HTF/LTF confirmation
Structural trailing stop [TRAIL_PSL] / [TRAIL_PSH]  EA still using fixed‑point trail (P0)
CRT full target exit [EXIT_CRT_TARGET]  Profits not taken at C1 opposite extreme
CISD reversal exit [EXIT_CISD_REVERSAL]  No early exit on reversal CISD
Dow BOS exit [EXIT_DOW_BOS]  Trades held through structural breaks
C2 wick filter fixed [C2_WICK_FILTER] (rare)  Large‑wick C2 candles still passing
RR gate accepts ≥2.0 [RG_GATE_FAIL] with R:R=2.00 absent  Exactly‑2.0 signals still rejected
Daily loss blocks entries only [ENTRY_BLOCKED] without position closure  Guard still force‑closing positions on daily loss
Account Guard recovery [ACCOUNT_GUARD] Recovery... after halt  PERMANENT still permanent

---

STAGE 6 — BLIND‑SPOT INVENTORY

List every code path that could discard a signal or mismanage a trade without a visible log marker. Search the source for:

· return false; inside EvaluateC2Closure(), EvaluateC3Closure(), ValidateDisplacement(), etc., that are not preceded by a LogInfo with a specific reason.
· continue; in signal loops without logging.
· Any if condition that gates execution and does not log when failing (e.g., heat cap without [PYRAMID_BLOCKED]).
· Missing logs for CISD detection failures, HTF confirmation failures, etc.

For each blind spot, provide file:line, condition, and the number of signals likely affected based on pipeline drop‑offs.

---

STAGE 7 — C2 vs C3 PERFORMANCE (Model‑Aligned)

Break down by closure type:

· C2 closure (Anticipation): GUIDs, lock rate, rejection reasons (NO_REVERSAL_CLOSURE, NO_SWEEP, DISPLACEMENT_FAIL, C1_POI_MISS). For rejections with near‑miss sweeps, compute the actual distance to the C1 extreme and compare to any sweep tolerance.
· C3 closure (Confirmation): GUIDs, fallback success rate (C3_FALLBACK vs independent), alignment with D1 bias, CISD confirmation wait time.
· C2 wick filter activations: how many C2 candles triggered the filter? Did the EA then wait for the C3 candle?

For C2 closure rejections that pass the sweep and close‑back but fail C1_POI_MISS, log the C1 high/low and the nearest HTF POI distances. This determines if the POI detection is working or too strict.

---

STAGE 8 — EXECUTION BOTTLENECK TRACE

If RG_GATE_PASS > 0 but orders not sent, extract the log lines between the pass and the next GUID event. Cross‑reference with OmakFxYO.mq5 lines ~4474‑4769 and any new context/exit checks. Build a flowchart showing which check passes/fails.

---

STAGE 9 — CODE‑TO‑LOG TRACEABILITY MATRIX (Expanded)

For every marker listed, state whether it appears in the log. If missing, determine if the code path is cold (never called) or filtered by log level. For new model‑faithful markers, absence likely means the feature isn’t implemented yet → report as missing.

---

STAGE 10 — ROOT‑CAUSE SUMMARY

Produce a single table mapping every signal death category to its root‑cause code location and the exact fix required. Prioritize by impact:

Priority Death Category Root Cause (file:line) Fix Signals Affected
P0 Fixed‑point trailing kills trades PositionManager.mqh:411‑451 Replace with structural trail (Prompt 4) All executed trades
P0 C2 pipeline dead (C1_POI_MISS) ClosureEngine.mqh C1‑POI check Implement IsC1AtHTFPointOfInterest() correctly 83 C2 rejections
... ... ... ... ...

---

OUTPUT RULES

· Executive Summary must answer:
  1. Did the EA execute trades? How many, win rate, P&L?
  2. What was the most fatal check that killed the most signals or mismanaged trades?
  3. How many signals reached each stage?
  4. Which model‑faithful fixes are active vs. still missing?
  5. Which blind spots exist and how many signals do they affect?
· Every claim must cite a log line and a code location.
· The report must end with a "Next Actions" section: exact code changes required, in order, to get the EA trading as the model expects.

---
