OmakFxYO — Backtest Log Forensic Analysis v07 (Model-Aligned)

Pipeline Health, Execution Audit, Blind-Spot Detection & Code-to-Log Root-Cause Tracing
Aligned to TTrades Fractal Model + CRT + Dow Theory

---

CONTEXT (Read-Only)

You are auditing the OmakFxYO EA — an MT5 Expert Advisor that trades the TTrades Fractal Model + Dow Theory + Candle Range Theory (CRT). The architecture is defined in the project's AGENTS.md and Risk Dossier. Key rules (model-aligned):

· Stop-loss = C2 candle extreme (protected swing) for both C2 and C3 closures. No ATR-based stops.
· Take profit is not a fixed multiple; 2R is a minimum gate check, not the TP price. Orders may be sent with TP=0 when no structural target is computable, but the EA now also applies CRT full target (C1 opposite extreme) as a primary exit.
· C3 closure (Confirmation Mode) MUST align with D1 bias; C2 closure (Anticipation Mode) does NOT.
· C2 closure and C3 closure pipelines are independent (separate slots, evaluation, bias gating), but C3 closure is a fallback when C2 candle fails reversal.
· C1 must be at an HTF Point of Interest (swing, FVG, OB) for both C2 and C3 closures to be valid.
· Top-down context: D1 bias → HTF confirmation (CISD or C2/C3 closure on HTF) → LTF CISD → execution.
· Trailing stop uses Protected Swing Lows/Highs on the entry timeframe, not fixed points.
· Exits: 1) CRT full target, 2) CISD reversal, 3) Dow BOS, 4) Protected swing breach (trailing SL).
· Pyramiding only at new protected swings, not on every C3 closure.
· Account Guard: daily loss blocks new entries only; catastrophic floor closes positions and allows recovery.

Critical Terminology (model-exact):

Term | Meaning
-----|--------
C2 candle | The second bar in C1→C2→C3 sequence; sweeps C1's extreme.
C2 closure | Reversal signal: C2 candle sweeps C1 extreme AND closes back inside C1's high-low range. (Anticipation Mode)
C3 candle | The third bar.
C3 closure | Fallback signal: C3 candle engulfs C2's body without sweeping C2's extreme. (Confirmation Mode). Must align with D1 bias.
C2 wick filter | If C2 candle has large wick (>60%), wait for C3 candle (not a signal type).
Protected Swing | A confirmed swing low (PSL) or swing high (PSH) used for trailing stop.
C1-at-POI | C1 must overlap an HTF structural level (swing/FVG/OB).
CISD | Change in State of Delivery — reversal confirmation on a timeframe.
CRT full target | Opposite extreme of C1 range (C1 high for buys, C1 low for sells).

---

## Current Analysis Scripts

| Script | Purpose | Markers Tracked |
|--------|---------|----------------|
| `omak_cli.py` | CLI entry point | All markers via engine |
| `omak_forensic_engine.py` | Full forensic analysis with pipeline tracking | All patterns in PATTERNS dict (including model-aligned) |
| `backtest_clinical_extract.py` | Clinical backtest extraction, leak detection | Core pipeline markers |

## Parameters

```
TARGET_LOG:       20260528.log
LOG_PATH:         /home/zoro/.var/app/com.usebottles.bottles/data/bottles/bottles/MetaTrader-5/drive_c/Program Files/MetaTrader 5/Tester/Agent-127.0.0.1-3000/logs/

REPORT_PATH:      OmakFxYO/Quant_Backtest_Reports/OmakFxYO_Quant_Forensic_Report_61.md
DECODED_LOG:      /tmp/omak_decoded.log
```

## Running Analysis

### Using CLI (Recommended)
```bash
python3 OmakFxYO/scripts/omak_cli.py analyze "<LOG_PATH>/20260528.log"
python3 OmakFxYO/scripts/omak_cli.py analyze "<LOG_PATH>/20260528.log" --clinical
```

---

STAGE 0 — DECODE THE LOG

```bash
python3 OmakFxYO/scripts/omak_cli.py analyze "<LOG_PATH>/20260528.log"
```

Verify: wc -l on output. Capture the EA_BUILD line if present.

---

STAGE 1 — PRE-AUDIT: Marker Verification

### Core Pipeline Markers

| Marker | File | Purpose |
|--------|------|---------|
| `[GUID_ASSIGNED]` | LockedSignal.mqh:282 | Signal ID generation |
| `[SIGNAL_LOCKED]` | ClosureEngine.mqh:2171 | Closure locked |
| `STAGE_READY` | ClosureEngine.mqh:2633 | FSM ready state |
| `[RG_GATE_PASS]` | RiskGate.mqh:996 | Risk gate approval |
| `[EXEC_TRIGGERED]` | OrderManager.mqh:1493 | Execution triggered |
| `[ORDER_SENT]` | OrderManager.mqh:1500 | Order dispatched |
| `[ORDER_FAIL]` | RiskGate.mqh:1058 | Order failure |
| `[BIAS_ALIGN]` | BiasResolver.mqh | D1 bias check |
| `[C2_REJECT]` | ClosureEngine.mqh | C2 rejection |
| `[MODAL_UPGRADE]` | BranchEvaluator.mqh:816 | Anticipation→Confirmation upgrade |
| `[ACCOUNT_GUARD_DAILY_LOSS]` | OmakFxYO.mq5:4044 | Daily loss block |
| `[ACCOUNT_GUARD_EMERGENCY]` | OmakFxYO.mq5 | Emergency mode |

### Model-Aligned Markers (Tracked in omak_forensic_engine.py)

| Marker | File | Purpose |
|--------|------|---------|
| `[C1_POI_VALID]` | ClosureEngine.mqh | C1 overlaps HTF POI |
| `[C1_POI_MISS]` | ClosureEngine.mqh | C1 not at POI → rejection |
| `[C3_FALLBACK]` | ClosureEngine.mqh | C3 closure as fallback |
| `[TRAIL_PSL]` | PositionManager.mqh | Protected swing low trail |
| `[TRAIL_PSH]` | PositionManager.mqh | Protected swing high trail |
| `[EXIT_CRT_TARGET]` | OmakFxYO.mq5 | CRT full target exit |
| `[EXIT_CISD_REVERSAL]` | OmakFxYO.mq5 | CISD reversal exit |
| `[EXIT_DOW_BOS]` | OmakFxYO.mq5 | Dow BOS exit |
| `[C2_WICK_FILTER]` | C2WickFilter.mqh | C2 large wick filter |
| `[PYRAMID_ADD]` | CampaignManager.mqh | Layer added at protected swing |
| `[C2_ACCEPTED]` | ClosureEngine.mqh | C2 closure accepted |
| `[C2_LOCKED]` | ClosureEngine.mqh | C2 locked |
| `[STATE_TRANSITION_OK]` | LockedSignal.mqh | State transition success |
| `[STATE_ILLEGAL]` | LockedSignal.mqh | Illegal state detected |
| `[STATE_GHOST_BLOCKED]` | LockedSignal.mqh | Ghost state blocked |
| `[STATE_RECOVERED]` | LockedSignal.mqh | State recovered |
| `[SIGNAL_CORRUPT]` | LockedSignal.mqh | Signal corruption detected |
| `[LOCKED_SIGNAL_REJECTED]` | LockedSignal.mqh | Locked signal rejected |
| `[LOCKED_SIGNAL_COMPLETE]` | LockedSignal.mqh | Locked signal complete |
| `[COMMIT_REJECT]` | BranchEvaluator.mqh | Commit rejection |
| `[STRUCTURE_REJECT]` | ClosureEngine.mqh | Structure rejection |
| `[ENTRY_REJECT]` | OrderManager.mqh | Entry rejection |
| `[ENTRY_CANDIDATE_INVALID]` | OrderManager.mqh | Invalid entry candidate |
| `[ENTRY_CANDIDATE_SET]` | OrderManager.mqh | Entry candidate set |
| `[C2_LOCK_DIAG]` | ClosureEngine.mqh | C2 lock diagnostics |
| `[C3_CONTEXT]` | BranchEvaluator.mqh | C3 context check |
| `[C3_RUNTIME_DISABLED]` | BranchEvaluator.mqh | C3 runtime disabled |
| `[STATE_CLEARED]` | LockedSignal.mqh | State cleared |
| `[CONTEXT_EXPIRED]` | BranchEvaluator.mqh | Context expired |
| `[DISPLACEMENT]` | ClosureEngine.mqh | Displacement event |
| `[SL_CALC]` | PositionManager.mqh | Stop loss calculation |
| `[FLOOR_CALC]` | RiskGate.mqh | Risk floor calculation |
| `[SYM_CLASSIFIED]` | SymbolClassifier.mqh | Symbol classification |

---

STAGE 2 — PIPELINE HEALTH SNAPSHOT

The engine automatically produces funnel statistics. Key transitions:

1. GUID_ASSIGNED → SIGNAL_LOCKED (closure → lock)
2. SIGNAL_LOCKED → RG_GATE_PASS (bias/structure validation)
3. RG_GATE_PASS → ORDER_SENT (execution gate)
4. ORDER_SENT → DEAL_PERFORMED (actual fill)

---

STAGE 3 — DEEP SIGNAL DEATH INVESTIGATION

Trace lifecycle of failed signals using gap analysis output. Report:

1. Closure type (C2/C3)
2. Rejection marker
3. Code location
4. Root cause

---

STAGE 4 — CONFIGURATION CONSISTENCY AUDIT

Extract runtime values and compare to OmakFxYO.mq5 defaults.

---

STAGE 5 — POST-FIX VERIFICATION

- Why is EA flat-lining?
- Risk management failures?
- Stop loss working correctly?
- TP working correctly?
- Remaining blind spots?

---

STAGE 6 — BLIND-SPOT INVENTORY

Code paths that discard signals without visible markers.

---

STAGE 7 — C2 vs C3 PERFORMANCE

Breakdown by closure type with rejection reasons.

---

STAGE 8 — EXECUTION BOTTLENECK TRACE

Gap analysis between RG_GATE_PASS and ORDER_SENT.

---

STAGE 9 — ROOT-CAUSE SUMMARY

Prioritized fix table:

| Priority | Death Category | Root Cause (file:line) | Fix |
|----------|---------------|------------------------|-----|
| P0 | Fixed-point trailing kills trades | PositionManager.mqh | Replace with structural trail |
| P0 | C2 pipeline dead (C1_POI_MISS) | ClosureEngine.mqh | Implement IsC1AtHTFPointOfInterest() |

---

OUTPUT RULES

· Executive Summary: trades count, win rate, P&L, most fatal check, leak rate
· Every claim cites log line and code location
· End with "Next Actions" section
