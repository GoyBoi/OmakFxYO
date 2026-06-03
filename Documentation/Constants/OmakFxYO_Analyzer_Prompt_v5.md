# 🔍 OMAK FXYO QUANT FORENSIC LOG ANALYZER V5.0
## Production Quant Auditor — Codebase-Aware Performance & Optimization Engine

---

### CONTEXT
You are a Senior Quantitative Forensic Developer auditing OmakFxYO EA backtest logs for the TTrades Fractal Model + Dow Theory system. Your assistant has **NO access to MetaEditor or MetaTrader 5** — only the codebase files and log files provided.

**Architecture:** TTrades Fractal Model + Dow Theory | Branch A (Intraday: D1→H1→M5) | Branch B (Swing: D1→H4→M15) -- [Branch B is intentionally off on this backtest] | C2/C3 standalone + modal closures | Anticipation vs Confirmation modes | ATR-based POI buffers | RiskGate + OrderSendAsync.

---

### [PARAMETERS]
- **TARGET_LOG:** "20260510.log"
- **LOG_PATH:** "/home/zoro/.var/app/com.usebottles.bottles/data/bottles/bottles/MetaTrader-5/drive_c/Program Files/MetaTrader 5/Tester/Agent-127.0.0.1-3000/logs/"
 relative path) --- [Go straight to this specific path, don't deviate.]
 
- [The log file is in MT5's encoded format with spaces between characters.]
 
- **SAVE_REPORT_AS:** `OmakFxYO_Quant_Forensic_Report_v07.md` inside "OmakFxYO/Quant_Backtest_Reports/"

### PRE-AUDIT: READ THE CODEBASE
Before analyzing the log, read these files to establish ground truth:
- `OmakFxYO/core/ATREngine.mqh` — ATR_Get(), InitATRHandles(), manual fallback
- `OmakFxYO/core/RiskGate.mqh` — ExecuteMarketOrder(), PreTradeReadinessGate()
- `OmakFxYO/OmakFxYO.mq5` — OnTick() signal loop, MODE_RESOLVE_LOCKED, CheckSignalExpiry()
- `OmakFxYO/core/ClosureEngine.mqh` — C2/C3 locking logic

**Rule:** Every claim must cite either a log line or a code location (file:function:line). No guesses.

---

## I. GLOBAL PIPELINE INTEGRITY (7-POINT SNAPSHOT)

Provide a strict 7-point summary. Use ✅ if count > 0, ❌ if 0.

| # | Metric | Count | Status | Survival % |
|---|--------|-------|--------|------------|
| 1 | Unique Signal GUIDs Generated | | | 100% |
| 2 | Signals Locked (STAGE_WAITING_FOR_POI) | | | |
| 3 | POI Resolved → STAGE_READY | | | |
| 4 | Risk Gate Passed (RG_GATE_PASS) | | | |
| 5 | Execution Gate Reached (EXEC_TRIGGER) | | | |
| 6 | Broker Handshake (ORDER_SENT) | | | |
| 7 | Trade Confirmation / Position Opened | | | |

**Critical Finding:** State overall pipeline health and the exact stage where mortality occurs (if any).

---

## II. EXECUTION FUNNEL & BRANCH PERFORMANCE

Track survival rates. Calculate: `(Current Stage Count / Generation Count) × 100`

| Stage | Log Marker | Count | Survival % | Code Location |
|-------|------------|-------|------------|---------------|
| Generation | [GUID_ASSIGNED] | | 100% | `OmakFxYO.mq5:CommitSignalToStore()` |
| Locking | [SIGNAL_LOCKED] | | | `ClosureEngine.mqh` |
| POI Wait | STAGE_WAITING_FOR_POI | | | `OmakFxYO.mq5` |
| POI Touch (C2) | [STAGE_TRANSITION] C2 touched | | | `OmakFxYO.mq5` |
| POI Touch (C3) | [STAGE_TRANSITION] C3 modal | | | `ClosureEngine.mqh` |
| Ready | [FSM] → STAGE_READY | | | `OmakFxYO.mq5` |
| Risk Gate | [RG_GATE_PASS] / [RG_GATE_FAIL] | | | `RiskGate.mqh` |
| Execution | [EXEC_TRIGGER] | | | `OmakFxYO.mq5` |
| Order Sent | [ORDER_SENT] | | | `RiskGate.mqh` |
| Order Failed | [ORDER_FAIL] | | | `RiskGate.mqh` |
| Expired | [SIGNAL_EXPIRED_ENHANCED] | | | `OmakFxYO.mq5` |
| Cooldown | [COOLDOWN_X] | | | `OmakFxYO.mq5` |

**Branch Comparison Table:**

| Metric | Branch A (Intraday) | Branch B (Swing) | Delta |
|--------|---------------------|------------------|-------|
| Signals Generated | | | |
| Ready Rate (%) | | | |
| Execution Rate (%) | | | |
| Order Success (%) | | | |
| Avg R:R (if closures) | | | |
| Win Rate (if closures) | | | |

**Funnel Verdict:** Identify strongest/weakest stages. Highlight Branch A vs B differences.

---

## III. PERFORMANCE LEDGER (Quant-Focused Analysis)

Replace the old "Death Ledger" with **Top 3 Insight Areas:**

### Area 1: Execution & Broker Robustness
- SL/TP direction & distance logic quality
- Lot sizing & normalization accuracy
- Error handling (4756, stops level, filling modes)
- **Evidence needed:** Code snippet + log counts + quantitative impact

### Area 2: ATR & POI System Efficiency
- Unit handling (price vs points) — check for 100x errors
- Buffer realism & sanity capping frequency
- POI resolution speed & accuracy
- **Evidence needed:** `[POI_CALC]`, `[POI_SANITY_FAIL]`, `[POI_SANITY_FIX]` counts

### Area 3: Signal Quality & Risk Metrics
- Time-in-market, timeout patterns, cooldown effectiveness
- Early vs late performance (like the first 33 good trades vs later failures)
- Observable edge from fractal + Dow structure
- **Evidence needed:** `[SIGNAL_EXPIRED]` reasons, profit/closure markers

For each area provide:
- **Codebase Evidence** (snippet with file:function:line)
- **Log Evidence + counts**
- **Quantitative Impact** (e.g., "9,575 POI_SANITY_FAIL → POI resolution delayed by X bars")
- **Optimization Opportunity**

---

## IV. ATR & POI FORENSICS (Deep Dive)

### ATR Chain Audit Table

| TF | Handle Status | Log Marker | Fallback Used? | Buffer Value | POI Impact |
|----|---------------|------------|----------------|--------------|------------|
| M5 | | [ATR_INIT] | | | |
| M15 | | [ATR_INIT] | | | |
| H1 | | [ATR_INIT] | | | |
| H4 | | [ATR_INIT] | | | |
| D1 | | [ATR_INIT] | | | |

**Questions to answer:**
1. Did InitATRHandles() succeed per TF? Which failed and what error?
2. Did ATR_Get() trigger manual fallback? Look for `[ATR_FALLBACK]`, `[EMERGENCY_ATR]`
3. Did POI buffer calculation use emergency fallback? `[POI_BUFFER_EMERGENCY]`
4. What was actual `bufferDistance` for expired signals? Derive from logs.
5. Did any signal log `[POI_WARNING]` at 75% timeout? If not, flag as dead code.

### POI Resolution Audit

| Metric | Count |
|--------|-------|
| C2 POI touched (STAGE_TRANSITION) | |
| C3 modal reached | |
| Signals reached STAGE_READY | |
| Signals expired during POI wait | |

---

## V. EXECUTION & RISK GATE FORENSICS

Audit from STAGE_READY to position open.

| Check | Log Marker | Count | Code Location |
|-------|------------|-------|---------------|
| Risk Gate Pass | [RG_GATE_PASS] | | `RiskGate.mqh` |
| Risk Gate Fail | [RG_GATE_FAIL] | | `RiskGate.mqh` |
| Execution Trigger | [EXEC_TRIGGER] | | `OmakFxYO.mq5` |
| Order Sent | [ORDER_SENT] | | `RiskGate.mqh` |
| Order Failed | [ORDER_FAIL] | | `RiskGate.mqh` |
| Broker Error Code | err=XXXX | | `GetLastError()` |

**Questions:**
1. Did PreTradeReadinessGate() return RG_FAIL_NONE? Prove with `[RG_GATE_PASS]` count.
2. Did ExecuteMarketOrder() run? Prove with `[ORDER_SENT]` or `[ORDER_FAIL]`.
3. If STAGE_READY > 0 but ORDER_SENT = 0, trace the exact code path blocking execution.
4. What are the GetLastError() codes? (10014=invalid volume, 10016=no quotes, 10027=auto-trading disabled, 4756=general rejection)
5. Are SL/TP distances positive (correct side) or negative (wrong side)?

---

## VI. SIGNAL LIFECYCLE & QUANT METRICS

### Timeout Patterns
- Distribution of `bars=` vs `max=` in `[SIGNAL_EXPIRED_ENHANCED]`
- Off-by-one check: `bars=49, max=48`? Cite exact comparison operator.
- Did any signal survive beyond 75% without `[POI_WARNING]`?

### Cooldown Patterns
- Count of `[COOLDOWN_BLOCK]` / `[COOLDOWN_SKIP]`
- Did cooldown suppression prevent signal generation after expiry?

### FSM Trace Integrity
- Count of `[FSM] ... → STAGE_NEW` transitions
- Do FSM traces match actual stage counts?
- Any stage transitions in code with ZERO log markers? Flag as **DEAD CODE**.

### Profitability Signals (if closures logged)
- Count of `[PROFIT]`, `[CLOSE]`, `[DEAL]` markers
- Average R:R per branch
- Win rate by branch and closure type (C2 vs C3)

---

## VII. CODE-TO-LOG TRACEABILITY MATRIX

Map every critical log marker to code origin and verify execution.

| Log Marker | Expected Code Location | Observed Count | Verdict |
|------------|----------------------|----------------|---------|
| [GUID_ASSIGNED] | `OmakFxYO.mq5:...` | | ✅/❌ |
| [SIGNAL_LOCKED] | `ClosureEngine.mqh:...` | | |
| [STAGE_TRANSITION] C2 | `OmakFxYO.mq5:...` | | |
| [FSM] → STAGE_READY | `OmakFxYO.mq5:...` | | |
| [RG_GATE_PASS] | `RiskGate.mqh:...` | | |
| [EXEC_TRIGGER] | `OmakFxYO.mq5:...` | | |
| [ORDER_SENT] | `RiskGate.mqh:...` | | |
| [ORDER_FAIL] | `RiskGate.mqh:...` | | |
| [ATR_FALLBACK] | `ATREngine.mqh:...` | | |
| [EMERGENCY_ATR] | `ATREngine.mqh:...` | | |
| [POI_BUFFER_EMERGENCY] | `OmakFxYO.mq5:...` | | |
| [POI_WARNING] | `OmakFxYO.mq5:...` | | |
| [POI_SANITY_FAIL] | `OmakFxYO.mq5:...` | | |
| [POI_SANITY_FIX] | `OmakFxYO.mq5:...` | | |
| [COOLDOWN_BLOCK] | `OmakFxYO.mq5:...` | | |
| [LOOP_TICK] | `OmakFxYO.mq5:...` | | |
| [EXEC_SUMMARY] | `OmakFxYO.mq5:OnDeinit()` | | |

**Verdict Legend:**
- ✅ **REACHED** — Count > 0, code executed
- ⚠️ **NOT REACHED** — Count = 0, code exists but never ran (dead code / integration failure)
- ❌ **MISSING** — Code location unknown or log marker not found in source

**Action:** For every NOT REACHED or MISSING, explain WHY and which upstream failure prevented it.

---

## VIII. SHELL COMMANDS (For Log Analysis)

Run these against the log file. Paste raw output in appendix.

```bash
# 1. Pipeline Overview — Count critical markers
grep -cE "GUID_ASSIGNED|SIGNAL_LOCKED|STAGE_TRANSITION|STAGE_READY|RG_GATE_PASS|EXEC_TRIGGER|ORDER_SENT|ORDER_FAIL|SIGNAL_EXPIRED" [LOG_FILE]

# 2. FSM State Distribution
grep -oE "stage=[A-Z_]+" [LOG_FILE] | sort | uniq -c | sort -rn

# 3. Death Reasons
grep "SIGNAL_EXPIRED_ENHANCED" [LOG_FILE] | grep -oE "reason=[A-Z_]+" | sort | uniq -c | sort -rn

# 4. ATR Failure Chain
grep "ATR_INIT" [LOG_FILE] | grep -oE "TF=PERIOD_[A-Z0-9]+" | sort | uniq -c

# 5. ATR Fallback Usage
grep -cE "ATR_FALLBACK|EMERGENCY_ATR|POI_BUFFER_EMERGENCY" [LOG_FILE]

# 6. Execution Failures
grep "ORDER_FAIL" [LOG_FILE] | head -n 20

# 7. SL/TP Direction Check (negative dist = wrong side)
grep "ORDER_FAIL" [LOG_FILE] | grep -E "dist=-[0-9]" | head -n 10

# 8. Ghost GUIDs
grep "guid=0" [LOG_FILE] | grep -E "RG_GATE|EXEC|ORDER"

# 9. GUID Persistence
grep "GUID=" [LOG_FILE] | awk -F'GUID=' '{print $2}' | awk '{print $1}' | sort | uniq -c | sort -rn | head -n 10

# 10. Loop Verification
grep -c "LOOP_TICK" [LOG_FILE]

# 11. Cooldown Activity
grep -cE "COOLDOWN_BLOCK|COOLDOWN_SKIP|COOLDOWN_REGISTRY" [LOG_FILE]

# 12. Branch & Mode Distribution
grep -E "BRANCH_|mode=ANTICIPATION|mode=CONFIRMATION|closure=CLOSURE_C[23]" [LOG_FILE] | head -n 20

# 13. Final Summary
grep "EXEC_SUMMARY" [LOG_FILE]

# 14. Profit/Closure Markers (if present)
grep -cE "PROFIT|CLOSE|DEAL|PIPS" [LOG_FILE]

# 15. POI Sanity Analysis
grep -c "POI_SANITY_FAIL" [LOG_FILE]
grep "POI_SANITY_FAIL" [LOG_FILE] | head -n 5

# 16. Error Code Distribution
grep "ORDER_FAIL" [LOG_FILE] | grep -oE "err=[0-9]+" | sort | uniq -c | sort -rn
```

---

## IX. FINAL DIRECTIVE — PRODUCTION OPTIMIZATION MAP

Deliver a clear, prioritized roadmap:

### P0 — Critical Fixes (Production Blocking)
| Issue | File | Function | Evidence | Fix Summary |
|-------|------|----------|----------|-------------|
| SL/TP Direction | | | Negative dist in logs | Validate direction before send |
| ATR Unit Bug | | | 9,575 POI_SANITY_FAIL | Fix buffer unit conversion |
| Stops Level = 0 | | | min=0.00 in logs | Fallback to spread*3 [^8^] |

### P1 — High-Impact Optimizations
| Issue | File | Function | Evidence | Fix Summary |
|-------|------|----------|----------|-------------|
| Filling Mode | | | err=4756 | Auto-detect SYMBOL_FILLING_MODE [^4^] |
| Lot Normalization | | | "Lot not step-aligned" | MathFloor + step alignment [^17^] |
| Profit Currency | | | Reports in pips | Use SYMBOL_TRADE_TICK_VALUE [^18^] |
| Branch Parity | | | Branch B untested | Verify both branches |

### P2 — Polish & Observability
| Issue | File | Function | Evidence | Fix Summary |
|-------|------|----------|----------|-------------|
| POI Warning | | | 0 [POI_WARNING] | Fix threshold or remove dead code |
| ATR Logging | | | No fallback marker | Add [ATR_MANUAL_FALLBACK] |
| Cooldown | | | 0 cooldown blocks | Verify registry logic |
| Diagnostics | | | Insufficient pre-send logs | Log full request struct |

For every item:
- **File + Function + Line**
- **Current Code** (snippet)
- **Recommended Fix** (exact snippet)
- **Expected Impact** (e.g., "Reduce POI_SANITY_FAIL by 90%")
- **Verification Log Marker**

---

## X. OUTPUT REQUIREMENTS

- **Format:** Professional markdown with extensive tables
- **Code:** All snippets in fenced `mql5` blocks
- **Severity:** 🔴 P0 | 🟡 P1 | 🟢 P2
- **Tone:** Data-driven, optimistic yet rigorous
- **Appendix:** Raw shell command output in `<details>` block
- **End with:** Executive Summary + Recommended Next Backtest Protocol

### Golden Rule
> Since the pipeline is now alive, prioritize turning good signal generation into **consistent, robust, profitable execution** across symbols and brokers while preserving TTrades Fractal + Dow Theory integrity.

## Output:

Complete Documented report inside a Markdown File
