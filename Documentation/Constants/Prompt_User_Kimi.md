# 🕵️‍♂️ OMAK FXYO FORENSIC LOG ANALYZER V4.0
Production Backtest Auditor — Codebase-Aware Forensics
Context: You are a Senior Quantitative Forensic Developer auditing the OmakFxYO EA backtest logs.
Mandate: Cross-reference log evidence against the actual codebase. Do not trust that "code exists" — verify it EXECUTED by finding its log marker in the backtest output.
Architecture: TTrades Fractal Model + Dow Theory | Branch A (D1→H1→M5) / Branch B (D1→H4→M15) | C2 & C3 standalone closures | Anticipation vs Confirmation modes | ATR-based POI buffers with manual fallback | RiskGate execution via OrderSendAsync.

### [PARAMETERS]
* TARGET_LOG: "20260508.log"
* LOG_PATH: "/home/zoro/.var/app/com.usebottles.bottles/data/bottles/bottles/MetaTrader-5/drive_c/Program Files/MetaTrader 5/Tester/Agent-127.0.0.1-3000/logs/"


----
0. PRE-AUDIT: READ THE CODEBASE
Before touching the log file, read these files to establish ground truth:
•  OmakFxYO/core/ATREngine.mqh — ATR_Get(), InitATRHandles(), manual fallback, emergency ATR
•  OmakFxYO/core/RiskGate.mqh — ExecuteMarketOrder(), PreTradeReadinessGate(), ConfirmOrderSent()
•  OmakFxYO/OmakFxYO.mq5 — OnTick() signal loop, MODE_RESOLVE_LOCKED, CheckSignalExpiry(), RG_GATE integration, C2 POI touch detection, cooldown registry
•  OmakFxYO/core/ClosureEngine.mqh — C2/C3 locking logic, modal upgrades
Rule: Every claim in this report must cite either a log line or a code location (file:function:line). No guesses.
----
I. GLOBAL PIPELINE INTEGRITY (7-POINT SNAPSHOT)
Provide a strict 7-point summary. Use ✅ if count > 0, ❌ if 0.
# Metric Count Status
1 Unique Signal GUIDs Generated  
2 Signals Locked (STAGE_WAITING_FOR_POI)  
3 POI Resolved → STAGE_READY  
4 Risk Gate Passed (RG_GATE_PASS)  
5 Execution Gate Reached (EXEC_GATE)  
6 Broker Handshake (ORDER_SENT)  
7 Trade Confirmation / Position Opened  
Critical Finding: State the exact stage where 100% mortality occurs (if any) and the count.
----
II. THE EXECUTION FUNNEL
Track survival from generation to execution. Calculate Survival % as (Current Stage Count / Generation Count) × 100.
Stage Log Marker Event Count Survival % Code Location
Generation [GUID_ASSIGNED]  100% OmakFxYO.mq5:CommitSignalToStore()
Locking [SIGNAL_LOCKED]   ClosureEngine.mqh or OmakFxYO.mq5
POI Wait [STAGE_WAITING_FOR_POI]   OmakFxYO.mq5
POI Touch (C2) [STAGE_TRANSITION] C2 POI touched   OmakFxYO.mq5 (C2 touch loop)
POI Touch (C3) [STAGE_TRANSITION] C3 modal   ClosureEngine.mqh
Ready [FSM] ... → STAGE_READY   OmakFxYO.mq5
Risk Gate [RG_GATE_PASS] / [RG_GATE_FAIL]   RiskGate.mqh:PreTradeReadinessGate()
Execution Gate [EXEC_GATE] / [EXEC_TRIGGER]   OmakFxYO.mq5
Order Sent [ORDER_SENT]   RiskGate.mqh:ExecuteMarketOrder()
Order Failed [ORDER_FAIL]   RiskGate.mqh:ExecuteMarketOrder()
Expired [SIGNAL_EXPIRED_ENHANCED]   OmakFxYO.mq5:CheckSignalExpiry()
Cooldown Block [COOLDOWN_X]   OmakFxYO.mq5:IsSignalOnCooldown()
Funnel Verdict: Identify the first stage where survival drops to 0% or near-0%. This is your chokepoint.
----
III. THE DEATH LEDGER (ROOT CAUSE FORENSICS)
Identify the Top 3 Kill Points. For each, trace the cascade:
Kill Point N: [Name]
The Kill Point: (e.g., POI_TIMEOUT, ATR_HANDLE_EXHAUSTION, RG_GATE_BLOCKED, ORDER_SEND_FAIL, COOLDOWN_SUPPRESSION)
Codebase Evidence:
•  File: ...
•  Function: ...
•  Lines: ...
•  Relevant code snippet (paste the actual logic)
Log Evidence:
•  Paste the exact log string(s) proving this kill point.
•  Count of occurrences.
The "Why":
Explain the mechanical failure. Why did this specific line of code block the trade?
(e.g., "ATR_Get() returned 0 because the H1 handle was INVALID_HANDLE, causing bufferDistance to collapse to minBuffer. Price never touched the 0.3-pip buffer around the POI, so the C2 touch condition ask >= bufferLow remained false for 48 bars.")
Cascade Relationship:
Show how this kill point destroys downstream stages.
(e.g., "ATR=0 → bufferDistance=minBuffer → POI zone too tight → no STAGE_TRANSITION → CheckSignalExpiry hits 48 bars → SIGNAL_EXPIRED → new signal generated → repeat.")
----
IV. ATR & POI FORENSICS
This is the EA's historical Achilles heel. Audit it ruthlessly.
ATR Chain Audit
TF Handle Status Log Marker Fallback Used? POI Impact
M5  [ATR_INIT] SUCCESS/FAIL  
M15  [ATR_INIT] SUCCESS/FAIL
H1  [ATR_INIT] SUCCESS/FAIL  
H4  [ATR_INIT] SUCCESS/FAIL  
D1  [ATR_INIT] SUCCESS/FAIL  
Questions to answer:
1.  Did InitATRHandles() succeed for all TFs? If not, which failed and what error code?
2.  Did ATR_Get() trigger manual fallback? Look for [ATR_FALLBACK], [EMERGENCY_ATR].
3.  Did the POI buffer calculation use emergency fallback? Look for [POI_BUFFER_EMERGENCY].
4.  What was the actual bufferDistance value for expired signals? Can it be derived from logs?
5.  Did any signal log [POI_WARNING] at 75% timeout? If not, the warning logic is dead code.
POI Resolution Audit
•  Count of signals that logged [STAGE_TRANSITION] C2 POI touched: __
•  Count of signals that reached STAGE_READY via any path: __
•  If 0 signals reached STAGE_READY, prove why by quoting the exact condition in the code that failed (e.g., ask >= bufferLow never true because bufferLow was above market price).
----
V. EXECUTION GATE FORENSICS
Audit the path from STAGE_READY to market order.
Check Log Marker Count Code Location
Risk Gate Validation [RG_GATE_PASS] / [RG_GATE_FAIL]  RiskGate.mqh
Execution Trigger [EXEC_TRIGGER]  OmakFxYO.mq5
Order Send Attempt [ORDER_SENT]  RiskGate.mqh:ExecuteMarketOrder()
Order Send Failure [ORDER_FAIL]  RiskGate.mqh:ExecuteMarketOrder()
Broker Rejection (error code in log)  OrderSendAsync() result
Questions to answer:
1.  Did PreTradeReadinessGate() ever return RG_FAIL_NONE? Prove with [RG_GATE_PASS] count.
2.  Did ExecuteMarketOrder() ever run? Prove with [ORDER_SENT] or [ORDER_FAIL] count.
3.  If STAGE_READY > 0 but ORDER_SENT = 0, trace the exact code path that prevents the call. Is the execution loop inside the same for loop as POI detection, or is it orphaned?
4.  Are there any GetLastError() codes in [ORDER_FAIL] logs? (e.g., 10014 = invalid volume, 10016 = no quotes, 10027 = auto-trading disabled)
----
VI. SIGNAL LIFECYCLE FORENSICS
Audit signal behavior over time.
Timeout Patterns
•  What is the distribution of bars= vs max= in [SIGNAL_EXPIRED_ENHANCED]?
•  Is there still an off-by-one (bars=49, max=48)? If yes, cite the exact comparison operator in CheckSignalExpiry().
•  Did any signal survive beyond 75% without [POI_WARNING]?
Cooldown Patterns
•  Count of [COOLDOWN_X] blocks: __
•  Did cooldown suppression prevent signal generation after expiry? Or did signals still spawn immediately?
FSM Trace Integrity
•  Count of [FSM] ... → STAGE_NEW transitions: __
•  Do the FSM traces match the actual stage counts? (e.g., if 10 signals reached STAGE_READY, there should be ~10 [FSM] logs showing that transition)
•  Are there any stage transitions that appear in the code but have ZERO log markers? Flag them as DEAD CODE.
----
VII. CODE-TO-LOG TRACEABILITY MATRIX
This is the most important section. Map every critical log marker to its code origin and verify execution.
Log Marker Expected Code Location (File:Function:Line) Observed Count in Log Verdict
[GUID_ASSIGNED] OmakFxYO.mq5:...  
[SIGNAL_LOCKED] OmakFxYO.mq5:...  
[STAGE_TRANSITION] C2 POI touched OmakFxYO.mq5:...  
[FSM] ... → STAGE_READY OmakFxYO.mq5:...  
[RG_GATE_PASS] RiskGate.mqh:...  
[EXEC_TRIGGER] OmakFxYO.mq5:...  
[ORDER_SENT] RiskGate.mqh:...  
[ORDER_FAIL] RiskGate.mqh:...  
[ATR_FALLBACK] ATREngine.mqh:...  
[EMERGENCY_ATR] ATREngine.mqh:...  
[POI_BUFFER_EMERGENCY] OmakFxYO.mq5:...  
[POI_WARNING] OmakFxYO.mq5:...  
[COOLDOWN_X] OmakFxYO.mq5:...  
[LOOP_TICK] OmakFxYO.mq5:...  
[EXEC_SUMMARY] OmakFxYO.mq5:OnDeinit()  
Verdict Legend:
•  REACHED — Count > 0, code executed
•  NOT REACHED — Count = 0, code exists but never ran (dead code / integration failure)
•  MISSING — Code location unknown or log marker not found in source
Action: For every row marked NOT REACHED or MISSING, explain WHY the code didn't run and which upstream failure prevented it.
----
VIII. ELITE SHELL COMMANDS
Run these against the log file before writing the report. Paste the raw output into an appendix.
# 1. Pipeline Overview — Count all critical markers
grep -cE "GUID_ASSIGNED|SIGNAL_LOCKED|STAGE_TRANSITION|STAGE_READY|RG_GATE_PASS|EXEC_GATE|ORDER_SENT|ORDER_FAIL|SIGNAL_EXPIRED" [LOG_FILE]

# 2. FSM State Distribution — What stages were actually observed?
grep -oE "stage=[A-Z_]+" [LOG_FILE] | sort | uniq -c | sort -rn

# 3. Death Reasons — Why did signals die?
grep "SIGNAL_EXPIRED_ENHANCED" [LOG_FILE] | grep -oE "reason=[A-Z_]+" | sort | uniq -c | sort -rn

# 4. ATR Failure Chain — Which TFs failed?
grep "ATR_INIT" [LOG_FILE] | grep -oE "TF=PERIOD_[A-Z0-9]+" | sort | uniq -c

# 5. ATR Fallback Usage — Did manual/emergency ATR actually trigger?
grep -cE "ATR_FALLBACK|EMERGENCY_ATR|POI_BUFFER_EMERGENCY" [LOG_FILE]

# 6. Execution Failures — Why did orders fail?
grep "ORDER_FAIL" [LOG_FILE] | head -n 20

# 7. Ghost GUIDs — Corrupted signal IDs?
grep "guid=0" [LOG_FILE] | grep -E "RG_GATE|EXEC_GATE|ORDER"

# 8. GUID Persistence — Any stuck signals?
grep "GUID=" [LOG_FILE] | awk -F'GUID=' '{print $2}' | awk '{print $1}' | sort | uniq -c | sort -rn | head -n 10

# 9. Loop Verification — Is the tick loop actually running?
grep -c "LOOP_TICK" [LOG_FILE]

# 10. Cooldown Activity — Is cooldown registry active?
grep -cE "COOLDOWN_BLOCK|COOLDOWN_SKIP" [LOG_FILE]

# 11. Branch & Mode Distribution — What was the EA actually doing?
grep -E "BRANCH_CFG|closure=CLOSURE_C[23]|mode=ANTICIPATION|mode=CONFIRMATION" [LOG_FILE] | head -n 20

# 12. Final Summary — Deinit report
grep "EXEC_SUMMARY" [LOG_FILE]

----
IX. FINAL DIRECTIVE — MECHANICAL REPAIR MAP
Do not suggest "optimizations" or "tweaks." Deliver a Mechanical Repair Map:
1.  Primary Failure: The single code location that caused 100% mortality (or the dominant failure mode).
2.  Integration Failures: Any code that exists but never executed (dead code due to missing call site).
3.  Data Flow Breaks: Places where a value is calculated but never consumed (e.g., manual ATR computed but POI uses old handle).
4.  Logic Errors: Off-by-one, wrong comparison operator, inverted boolean.
5.  Resource Errors: Handle leaks, memory pressure, broker rejection codes.
For each repair, specify:
•  File: ...
•  Function: ...
•  Line: ...
•  Current Code: (paste)
•  Fix: (exact code change or architectural rewiring required)
•  Log Marker to Verify Fix: (which log marker should appear after the fix is applied)
----
OUTPUT REQUIREMENTS
Save the complete report as:
OmakFxYO_Forensic_Report_v16.md
Include:
•  Raw shell command output in a collapsible <details> block or appendix
•  All code snippets in fenced code blocks with language mql5
•  Severity badges: 🔴 P0 (blocks execution), 🟡 P1 (causes failures), 🟢 P2 (robustness)
Golden Rule: If a log marker doesn't appear in the backtest, the code that emits it is either dead or unreachable. Your job is to prove which one.
---
