# OMAK FXYO — Backtest Log Forensic Analysis
## Lightweight Pipeline Health & Execution Audit

---

### CONTEXT (Read-Only)

You are auditing OmakFxYO EA backtest logs. The EA uses TTrades Fractal Model + Dow Theory.
- Branch A: Intraday (D1→H1→M5) — **ACTIVE on this backtest**
- Branch B: Swing (D1→H4→M15) — **INTENTIONALLY OFF**
- C2 = Anticipation Mode (standalone reversal)
- C3 = Confirmation Mode (standalone or modal upgrade from C2)

### [PARAMETERS]
- **TARGET_LOG:** "20260513.log"
- **LOG_PATH:** "/home/zoro/.var/app/com.usebottles.bottles/data/bottles/bottles/MetaTrader-5/drive_c/Program Files/MetaTrader 5/Tester/Agent-127.0.0.1-3000/logs/" - (relative path) --- [Go straight to this specific path, don't deviate.]

**Log format:** MT5 encoded format with spaces between characters.
**Parser script:** `@OmakFxYO/scripts/omak_forensic_engine.py` (use to decode logs)

**Save report to:** `OmakFxYO/Quant_Backtest_Reports/OmakFxYO_Quant_Forensic_Report_v11.md`

---

### PRE-AUDIT: READ THESE FILES FIRST

Before analyzing logs, read these files to understand the code that produces the log markers:

1. `OmakFxYO/core/ATREngine.mqh` — ATR_Get(), InitATRHandles(), manual fallback
2. `OmakFxYO/core/RiskGate.mqh` — ExecuteMarketOrder(), PreTradeReadinessGate()
3. `OmakFxYO/OmakFxYO.mq5` — OnTick() signal loop, MODE_RESOLVE_LOCKED, CheckSignalExpiry()
4. `OmakFxYO/core/ClosureEngine.mqh` — C2/C3 locking logic

**Rule:** Every claim must cite a log line OR a code location (file:function:line). No guesses.

---

## I. PIPELINE HEALTH SNAPSHOT (7 Metrics)

Count these log markers in the backtest log. Report count and survival rate.

| # | Metric | Log Marker | Count | Survival % |
|---|--------|-----------|-------|------------|
| 1 | Signals Generated | `[GUID_ASSIGNED]` | | 100% |
| 2 | Signals Locked | `[SIGNAL_LOCKED]` | | |
| 3 | POI Resolved → Ready | `[FSM] → STAGE_READY` | | |
| 4 | Risk Gate Passed | `[RG_GATE_PASS]` | | |
| 5 | Execution Triggered | `[EXEC_TRIGGER]` | | |
| 6 | Order Sent | `[ORDER_SENT]` | | |
| 7 | Position Opened / Confirmed | `[DEAL]` or `[ORDER_DONE]` | | |

**Critical Question:** Where does the pipeline die? Report the exact stage and the drop-off percentage.

---

## II. EXECUTION BOTTLENECK (The 0-Execution Problem)

This is the **most important section**. The prior forensic report found 1,077 RG Gate Passes → 0 Executions.

**Count and analyze:**

1. `[RG_GATE_PASS]` vs `[EXEC_TRIGGER]` — if RG passes but execution never triggers, the bottleneck is between RG and execution loop
2. `[EXEC_TRIGGER]` vs `[ORDER_SENT]` — if execution triggers but no order sent, bottleneck is in ExecuteMarketOrder() or OrderSend()
3. `[ORDER_FAIL]` — count these. Extract `err=XXXX` codes. Common codes:
   - 10014 = invalid volume
   - 10016 = invalid stops
   - 10027 = auto-trading disabled
   - 4756 = general rejection (filling mode, stops, etc.)
4. `[ORDER_FAIL]` with negative distance — `dist=-[0-9]` means SL/TP on wrong side of price

**Report:**
- Exact error code distribution (table: code | count | meaning)
- Most frequent failure reason
- Whether the bottleneck is pre-send (execution gate) or post-send (broker rejection)

---

## III. ATR & POI SYSTEM

**Count these markers:**

| Marker | Count | Meaning |
|--------|-------|---------|
| `[ATR_INIT]` per TF | | Did ATR handles initialize? |
| `[ATR_FALLBACK]` | | Did ATR_Get() use manual fallback? |
| `[EMERGENCY_ATR]` | | Emergency ATR value used? |
| `[POI_BUFFER_EMERGENCY]` | | POI buffer used emergency fallback? |
| `[POI_SANITY_FAIL]` | | POI buffer sanity check failed |
| `[POI_SANITY_FIX]` | | POI buffer was auto-fixed |

**Questions:**
1. Which timeframes failed ATR init? (extract `TF=PERIOD_X` from logs)
2. If `[POI_SANITY_FAIL]` > 0, what was the actual buffer value vs expected?
3. Did any signal log `[POI_WARNING]` at 75% timeout? If 0, flag as dead code.

---

## IV. SIGNAL LIFECYCLE & DEATH REASONS

**Count `[SIGNAL_EXPIRED_ENHANCED]` and extract `reason=XXXX`:**

| Reason | Count | % of Total Expired |
|--------|-------|-------------------|
| (list top 5 reasons) | | |

**Also count:**
- `[COOLDOWN_BLOCK]` / `[COOLDOWN_SKIP]` — is cooldown working?
- `[SIGNAL_EXPIRED]` with `bars=` vs `max=` — off-by-one check (bars=49, max=48?)

**Question:** Are signals dying mostly from expiry (POI never touched) or from execution failure?

---

## V. C2 vs C3 PERFORMANCE

**Count by closure type and mode:**

| Type | Generated | Ready | RG Pass | Executed | Success |
|------|-----------|-------|---------|----------|---------|
| C2 (Anticipation) | | | | | |
| C3 (Confirmation) | | | | | |
| C3 Modal Upgrade | | | | | |

**Question:** Does C3 standalone execute, or is it blocked waiting for C2? (This validates whether the slot fix from Prompt 1 is needed.)

---

## VI. CODE-TO-LOG TRACEABILITY

For each log marker below, report: ✅ (count > 0) | ⚠️ (count = 0, code exists) | ❌ (not found in code)

| Log Marker | Expected Code Location | Count | Verdict |
|------------|----------------------|-------|---------|
| `[GUID_ASSIGNED]` | OmakFxYO.mq5 | | |
| `[SIGNAL_LOCKED]` | ClosureEngine.mqh | | |
| `[FSM] → STAGE_READY` | OmakFxYO.mq5 | | |
| `[RG_GATE_PASS]` | RiskGate.mqh | | |
| `[EXEC_TRIGGER]` | OmakFxYO.mq5 | | |
| `[ORDER_SENT]` | RiskGate.mqh | | |
| `[ORDER_FAIL]` | RiskGate.mqh | | |
| `[ATR_FALLBACK]` | ATREngine.mqh | | |
| `[POI_SANITY_FAIL]` | OmakFxYO.mq5 | | |
| `[COOLDOWN_BLOCK]` | OmakFxYO.mq5 | | |
| `[EXEC_SUMMARY]` | OmakFxYO.mq5:OnDeinit() | | |

**For every ⚠️ (count = 0):** Explain WHY. Is the upstream stage blocking it? Is the code dead?

---

## VII. SHELL COMMANDS (Run These, Append Output)

Run these against the log file. Paste raw output in the report appendix.

```bash
# 1. Pipeline counts
grep -cE "GUID_ASSIGNED|SIGNAL_LOCKED|STAGE_READY|RG_GATE_PASS|EXEC_TRIGGER|ORDER_SENT|ORDER_FAIL|SIGNAL_EXPIRED" 20260510.log

# 2. FSM state distribution
grep -oE "stage=[A-Z_]+" 20260510.log | sort | uniq -c | sort -rn

# 3. Death reasons
grep "SIGNAL_EXPIRED_ENHANCED" 20260510.log | grep -oE "reason=[A-Z_]+" | sort | uniq -c | sort -rn

# 4. ATR init per TF
grep "ATR_INIT" 20260510.log | grep -oE "TF=PERIOD_[A-Z0-9]+" | sort | uniq -c

# 5. ATR/POI emergency usage
grep -cE "ATR_FALLBACK|EMERGENCY_ATR|POI_BUFFER_EMERGENCY" 20260510.log

# 6. Order fail details (first 20)
grep "ORDER_FAIL" 20260510.log | head -n 20

# 7. SL/TP wrong side (negative dist)
grep "ORDER_FAIL" 20260510.log | grep -E "dist=-[0-9]" | head -n 10

# 8. Error code distribution
grep "ORDER_FAIL" 20260510.log | grep -oE "err=[0-9]+" | sort | uniq -c | sort -rn

# 9. Branch & mode distribution (first 20)
grep -E "BRANCH_|mode=ANTICIPATION|mode=CONFIRMATION|closure=CLOSURE_C[23]" 20260510.log | head -n 20

# 10. Final summary
grep "EXEC_SUMMARY" 20260510.log

# 11. POI sanity count
grep -c "POI_SANITY_FAIL" 20260510.log
```

---

## VIII. PRIORITIZED FIX ROADMAP

Based on your findings, deliver a 3-tier roadmap:

### 🔴 P0 — Critical (Production Blocking)
| Issue | Evidence | Fix | Expected Impact |
|-------|----------|-----|-----------------|
| (fill from findings) | | | |

### 🟡 P1 — High Impact
| Issue | Evidence | Fix | Expected Impact |
|-------|----------|-----|-----------------|
| (fill from findings) | | | |

### 🟢 P2 — Polish
| Issue | Evidence | Fix | Expected Impact |
|-------|----------|-----|-----------------|
| (fill from findings) | | | |

---

## OUTPUT REQUIREMENTS

- **Format:** Professional markdown
- **Code:** All snippets in fenced `mql5` blocks
- **Severity:** 🔴 P0 | 🟡 P1 | 🟢 P2
- **Tone:** Data-driven, no speculation
- **Appendix:** Raw shell command output in `<details>` block
- **End with:** Executive Summary (3 bullets) + Recommended Next Backtest Protocol

---

### Golden Rule

> The pipeline is now alive. Prioritize turning good signal generation into consistent, robust, profitable execution while preserving TTrades Fractal + Dow Theory integrity.

---

*This is a simplified forensic prompt. Focus on counts, bottlenecks, and evidence. Do not generate speculative fixes without log proof.*
