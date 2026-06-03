OMAK FXYO — Backtest Log Forensic Analysis (v03 — Surgical & Traceable)

Pipeline Health, Execution Audit & Anomaly Detection

---

CONTEXT (Read‑Only)

You are auditing the OmakFxYO EA — an MT5 Expert Advisor that trades the TTrades Fractal Model + Dow Theory + Candle Range Theory (CRT).

Critical Terminology — Must Not Be Confused:

Term Meaning
C2 candle The second bar in the C1‑C2‑C3 sequence; it sweeps C1's extreme.
C2 closure Signal event where the C2 candle sweeps C1's extreme AND closes back inside C1's high‑low range. Always a reversal (Anticipation Mode). Per TTrades: "A candle 2 closure is always a reversal closure."
C3 candle The third bar; may form a C3 closure or simply expand.
C3 closure Signal event where the C3 candle engulfs C2's body without sweeping C2's extreme. Always a continuation (Confirmation Mode). Per TTrades: "Price does not sweep the previous candle, yet candle 3 closes over the body of candle 2 and engulfs it."
"Wait for C3" Wick‑filter rule: if C2 candle has a large wick, skip the C2 closure signal and wait for the C3 candle (not a C3 closure signal). Per TTrades: "Large wick on Candle 2 → skip C2 closure, wait for Candle 3."
Modal Upgrade One‑way transition: a locked C2 closure → C3 closure (inherits GUID). Never C3→C2.
Anticipation Mode C2 closure mode. Does NOT require D1 bias alignment. Validated by POI, liquidity sweep, displacement, CISD.
Confirmation Mode C3 closure mode. MUST align with D1 bias.

Architecture:

· Branch A: Intraday (D1→H1→M5) — ACTIVE
· Branch B: Swing (D1→H4→M15) — INTENTIONALLY OFF
· C2 and C3 pipelines are independent: separate slot limits (3 each), separate evaluation, separate bias gating.

---

PARAMETERS (Do Not Change These Paths)

```
TARGET_LOG:       20260520.log
LOG_PATH:         /home/zoro/.var/app/com.usebottles.bottles/data/bottles/bottles/MetaTrader-5/drive_c/Program Files/MetaTrader 5/Tester/Agent-127.0.0.1-3000/logs/
PARSER_SCRIPT:    OmakFxYO/scripts/omak_forensic_engine.py
REPORT_PATH:      OmakFxYO/Quant_Backtest_Reports/OmakFxYO_Quant_Forensic_Report_30.md
DECODED_LOG:      /tmp/omak_decoded.log
```

Rules:

· Go directly to LOG_PATH — it is an absolute path.
· Decode the entire log file using the parser script. No sampling. No "representative sections." This is non‑negotiable.
· Every claim must cite a log line OR a code location (file:function:line).

---

STAGE 0 — DECODE THE LOG

```bash
python3 OmakFxYO/scripts/omak_forensic_engine.py \
  --input "LOG_PATH/20260520.log" \
  --output "/tmp/omak_decoded.log"
```

Verify: wc -l /tmp/omak_decoded.log — confirm total lines. If the script prints a build ID or EA version string, capture it for the report header. This confirms which binary is actually running.

---

STAGE 1 — PRE‑AUDIT: Code Marker Verification

Verify each marker exists in both the decoded log and the source code. Use grep -c on the log and manual inspection of the code files.

# Marker Code File to Check Must Find
1 [GUID_ASSIGNED] core/LockedSignal.mqh ✅
2 [SIGNAL_LOCKED] core/ClosureEngine.mqh ✅
3 STAGE_READY (in FSM line) core/ClosureEngine.mqh ✅
4 [RG_GATE_PASS] core/RiskGate.mqh or OmakFxYO.mq5 ✅
5 [EXECUTION_TRIGGERED] core/OrderManager.mqh ✅
6 [ORDER_SENT] core/OrderManager.mqh ✅
7 [ORDER_FAIL] core/RiskGate.mqh ✅
8 [BIAS_ALIGN] core/BiasResolver.mqh ✅
9 [C2_REJECT] core/ClosureEngine.mqh ✅
10 [C2_CLOSURE_DETECTED] core/ClosureEngine.mqh ✅
11 [C2_LOCK_ATTEMPT] core/ClosureEngine.mqh ✅
12 [MODAL_UPGRADE] core/BranchEvaluator.mqh ✅
13 [ACCOUNT_GUARD_DAILY_LOSS] OmakFxYO.mq5 ✅
14 [ACCOUNT_GUARD_EMERGENCY] OmakFxYO.mq5 ✅
15 [EMERGENCY_CLOSE] OmakFxYO.mq5 ✅

Special check: Search the log for InpMaxDailyLossPercent= and InpEmergencyClosePercent=. Report the runtime values. Compare them to the code defaults in OmakFxYO.mq5 inputs section. Flag any mismatch — this is how the 5% vs 20% ghost lived for weeks.

---

STAGE 2 — PIPELINE HEALTH SNAPSHOT (8 Metrics)

Run on decoded log:

```bash
grep -c "[GUID_ASSIGNED]" /tmp/omak_decoded.log
grep -c "[SIGNAL_LOCKED]" /tmp/omak_decoded.log
grep -c "STAGE_READY" /tmp/omak_decoded.log
grep -c "\[RG_GATE_PASS\]" /tmp/omak_decoded.log
grep -c "\[EXECUTION_TRIGGERED\]" /tmp/omak_decoded.log
grep -c "\[ORDER_SENT\]" /tmp/omak_decoded.log
grep -c "deal performed\|DEAL_ENTRY\|\[DEAL_TRACK\]" /tmp/omak_decoded.log
grep -c "\[ORDER_FAIL\]" /tmp/omak_decoded.log
```

Pipeline Drop‑off Table:

# Stage Marker Count Survival %
1 Signals Generated GUID_ASSIGNED  100%
2 Signals Locked SIGNAL_LOCKED  
3 POI Resolved STAGE_READY  
4 Risk Gate Passed RG_GATE_PASS  
5 Execution Triggered EXECUTION_TRIGGERED  
6 Order Sent ORDER_SENT  
7 Deals Executed deal/DEAL_ENTRY  
8 Order Failed ORDER_FAIL  

Answer: Where does the pipeline die? Is the largest drop‑off between GUID_ASSIGNED→SIGNAL_LOCKED, SIGNAL_LOCKED→RG_GATE_PASS, or EXECUTION_TRIGGERED→ORDER_SENT? Quantify each gap.

---

STAGE 3 — EXECUTION BOTTLENECK & ORDER FAILURE ANALYSIS

3.1 Gate‑to‑Execution Flow

Compare RG_GATE_PASS count to EXECUTION_TRIGGERED count. If EXECUTION_TRIGGERED > RG_GATE_PASS, identify the surplus — these are signals bypassing the gate or being re‑triggered.

3.2 ORDER_FAIL Error Distribution

```bash
grep "ORDER_FAIL" /tmp/omak_decoded.log | grep -oE "retcode=[0-9]+" | sort | uniq -c | sort -rn
grep "ORDER_FAIL" /tmp/omak_decoded.log | grep -oE "reason=[A-Z_]+" | sort | uniq -c | sort -rn
```

Critical: If retcode=0 appears as a failure reason, flag it as a logic bug. Per MQL5 documentation, retcode=0 (TRADE_RETCODE_NO_RESULT) means "Request processed but no result returned from server" — this is normal in the Strategy Tester and does NOT indicate failure. Only TRADE_RETCODE_DONE (10009), TRADE_RETCODE_PLACED (10008), and TRADE_RETCODE_DONE_PARTIAL (10023) are documented success codes.

3.3 Silent Signal Death Detection

Some signals reach EXECUTION_TRIGGERED but never produce ORDER_SENT or ORDER_FAIL. These die in unlogged pre‑execution guards. Search for any [EXEC_SKIP] or similar markers. If none exist, flag the gap and recommend adding diagnostic logging to the pre‑execution checks (GUID validity, branch readiness, slot availability).

3.4 Market Session Failures

```bash
grep -ci "Market closed\|market closed\|MARKET_CLOSED" /tmp/omak_decoded.log
```

If count > 0, the EA is attempting to trade outside market hours. Per MQL5 best practice, SymbolInfoSessionTrade() should gate every order attempt.

---

STAGE 4 — ACCOUNT GUARD AUDIT (v03 New Section)

4.1 Threshold Verification

Search the log for the runtime parameter values:

```bash
grep -oE "InpMaxDailyLossPercent=[0-9.]+" /tmp/omak_decoded.log | head -1
grep -oE "InpEmergencyClosePercent=[0-9.]+" /tmp/omak_decoded.log | head -1
grep -oE "InpEquityDrawdownLimit=[0-9.]+" /tmp/omak_decoded.log | head -1
```

Compare to code defaults. If the log shows 5.0 but the code says 20.0, the Strategy Tester's internal parameter cache is overriding the code — the user must click "Default" in the Inputs tab.

4.2 Daily Loss Spam Detection

```bash
grep -c "ACCOUNT_GUARD_DAILY_LOSS" /tmp/omak_decoded.log
grep -c "ACCOUNT_GUARD_EMERGENCY" /tmp/omak_decoded.log
```

If the daily loss count exceeds 100, flag it as log spam — the throttle is missing or broken. The EA should log this at most once per minute using a static uint tick‑based throttle.

4.3 Emergency Close Analysis

```bash
grep "EMERGENCY_CLOSE\|ACCOUNT_GUARD_EMERGENCY" /tmp/omak_decoded.log | head -10
```

For each emergency close, extract: trigger reason (DD vs DAILY_LOSS), drawdown %, equity, and the time delta from the most recent ORDER_SENT. If positions are closed within 0‑2 minutes of opening, the emergency thresholds are too tight or the grace period is missing.

4.4 Position Hold Time

```bash
grep "DEAL_ENTRY\|deal performed" /tmp/omak_decoded.log | head -20
```

Calculate average hold time. If average < 5 minutes, the Account Guard (or another EA function) is manually closing positions before SL/TP can trigger. This violates the TTrades model, which requires trades to run to HTF structure targets.

4.5 Exit Reason Distribution

```bash
grep -oE "reason=[A-Z_]+" /tmp/omak_decoded.log | sort | uniq -c | sort -rn
```

If reason=EA dominates (positions closed by the EA rather than SL/TP), the Account Guard is the killer. If reason=SL or reason=TP appear, SL/TP are working.

---

STAGE 5 — C2 vs C3 PERFORMANCE (Terminology‑Precise)

5.1 Closure Type Distribution

```bash
grep "SIGNAL_LOCKED" /tmp/omak_decoded.log | grep -oE "closure=CLOSURE_C[23]" | sort | uniq -c
grep -c "CLOSURE_C2" /tmp/omak_decoded.log
grep -c "CLOSURE_C3" /tmp/omak_decoded.log
```

5.2 Mode Distribution

```bash
grep -c "mode=ANTICIPATION" /tmp/omak_decoded.log
grep -c "mode=CONFIRMATION" /tmp/omak_decoded.log
```

5.3 C2 Rejection Category Breakdown

```bash
grep "C2_REJECT" /tmp/omak_decoded.log | grep -oE "\[C2_REJECT\] [A-Z_]+" | sort | uniq -c | sort -rn
```

Expected rejection types (per ClosureEngine.mqh):

· NO_SWEEP — C2 candle did not sweep C1 extreme
· NO_REVERSAL_CLOSURE — C2 close outside C1 high‑low range (per TTrades: "closes back inside the previous candle's range")
· CONTEXT_REJECT — sweep did not target HTF structural level
· DISPLACEMENT_FAIL — insufficient displacement
· WICK_FILTER — large wick on C2 candle (per TTrades "Wait for C3" rule)
· POI_MISSING — no valid HTF point of interest

5.4 C2 Lock Attempt Analysis

```bash
grep -c "C2_CLOSURE_DETECTED" /tmp/omak_decoded.log
grep -c "C2_LOCK_ATTEMPT" /tmp/omak_decoded.log
grep -c "C2_LOCK_ATTEMPT.*SUCCESS" /tmp/omak_decoded.log
```

The gap between C2_CLOSURE_DETECTED and C2_LOCK_ATTEMPT is the C2 starvation chasm. If detection > 0 but lock attempts = 0, the rejection filters are killing every C2 closure before locking. Identify which rejection category dominates.

5.5 Performance Table

Type Detected Locked RG Pass Orders Sent Deals
C2 (Anticipation)     
C3 (Confirmation)     
Modal Upgrade (C2→C3) — —   

5.6 Modal Upgrade Verification

```bash
grep -c "MODAL_UPGRADE" /tmp/omak_decoded.log
```

If count = 0, check: does the modal upgrade code exist? (Yes, in core/BranchEvaluator.mqh). Does it require a C2 closure to be locked first? (Yes — ctx.modalUpgrade.pending is only set when a C2 closure commits). If C2 closures are 0, modal upgrade cannot fire. This is a dependency, not a bug.

---

STAGE 6 — BIAS STABILITY ANALYSIS

6.1 Bias Flip Frequency

```bash
grep -c "D1_BIAS" /tmp/omak_decoded.log
grep "D1_BIAS" /tmp/omak_decoded.log | grep -oE "BIAS_BULLISH|BIAS_BEARISH|BIAS_NEUTRAL" | sort | uniq -c
```

Extract sequential bias values from the log and count transitions. If bias flips more than once per week, flag it as unstable. Per Dow Theory and TTrades guidance: "Everything starts with the daily chart. Before looking at lower timeframes, there needs to be a clear daily bias." — a bias that flips daily is not a bias, it's noise.

6.2 Bias vs Signal Direction Alignment

```bash
grep "BIAS_ALIGN.*REJECT" /tmp/omak_decoded.log | head -10
```

If Confirmation Mode (C3 closure) signals are being rejected due to bias misalignment, note the rejection count. Confirmation Mode must align with D1 bias — but if the bias itself is unstable, valid C3 closures will be rejected incorrectly.

---

STAGE 7 — ATR & POI SYSTEM

```bash
grep -c "ATR_INIT" /tmp/omak_decoded.log
grep -c "ATR_FALLBACK" /tmp/omak_decoded.log
grep -c "EMERGENCY_ATR" /tmp/omak_decoded.log
grep -c "POI_SANITY_FAIL" /tmp/omak_decoded.log
grep -c "POI_WARNING" /tmp/omak_decoded.log
```

Flag if POI_SANITY_FAIL > 0 (POI system broken) or if ATR_FALLBACK > 0 (ATR handles failing).

---

STAGE 8 — SIGNAL LIFECYCLE & DEATH REASONS

```bash
grep -c "SIGNAL_EXPIRED" /tmp/omak_decoded.log
grep -c "COOLDOWN_BLOCK" /tmp/omak_decoded.log
grep -c "COOLDOWN_SKIP" /tmp/omak_decoded.log
grep "SIGNAL_EXPIRED_ENHANCED" /tmp/omak_decoded.log | grep -oE "reason=[A-Z_]+" | sort | uniq -c | sort -rn
```

Are signals dying from expiry, cooldown, or execution failure?

---

STAGE 9 — CROSS‑REFERENCE: DEALS vs SIGNAL PIPELINE

This is the v03 killer feature. Not all deals come from the signal pipeline — some may come from a rogue code path or manual intervention.

1. Extract all deal tickets and their GUIDs (if logged).
2. Match each deal to a [ORDER_SENT] log line by timestamp proximity (±5 seconds) and GUID.
3. Report:
   · Matched deals: Deals with a clear pipeline lineage.
   · Orphan deals: Deals with no corresponding ORDER_SENT or GUID — these are ghosts from an unlogged execution path.
   · Orphan GUIDs: ORDER_SENT lines with no subsequent deal — these are orders that were sent but never filled.

If orphan deals > 0, there is a second order‑sending mechanism in the EA that bypasses the forensic pipeline entirely.

---

STAGE 10 — LOG SPAM DETECTION

```bash
# Top 10 most frequent log lines
grep -oE "\[[A-Z_]+\]" /tmp/omak_decoded.log | sort | uniq -c | sort -rn | head -10
```

Any marker appearing more than 1,000 times in a single backtest is log spam. Flag it and identify whether the code has a throttle. The existing halt message at OmakFxYO.mq5 line ~4060 already uses a 60‑second throttle — other repeated messages should follow the same pattern.

---

STAGE 11 — CODE‑TO‑LOG TRACEABILITY MATRIX

Marker Code Location Log Count Status
GUID_ASSIGNED LockedSignal.mqh:282  ✅/⚠️/❌
SIGNAL_LOCKED ClosureEngine.mqh:2171  
STAGE_READY ClosureEngine.mqh:2633  
RG_GATE_PASS RiskGate.mqh:996  
EXECUTION_TRIGGERED OrderManager.mqh:1493  
ORDER_SENT OrderManager.mqh:1500  
ORDER_FAIL RiskGate.mqh:1058  
C2_REJECT ClosureEngine.mqh  
MODAL_UPGRADE BranchEvaluator.mqh:816  
ACCOUNT_GUARD_DAILY_LOSS OmakFxYO.mq5:4044  

---

STAGE 12 — PRIORITIZED FIX ROADMAP

Tier Issue Evidence (log line or grep count) Fix Suggestion
P0 (critical — blocks profitability)  
P1 (high — affects strategy)  
P2 (medium — observability/tuning)  

---

APPENDIX — RAW COUNTS

```bash
for marker in "GUID_ASSIGNED" "SIGNAL_LOCKED" "STAGE_READY" "RG_GATE_PASS" "EXECUTION_TRIGGERED" "ORDER_SENT" "ORDER_FAIL" "SIGNAL_EXPIRED" "C2_REJECT" "C2_CLOSURE_DETECTED" "C2_LOCK_ATTEMPT" "CLOSURE_C2" "CLOSURE_C3" "MODAL_UPGRADE" "ANTICIPATION" "CONFIRMATION" "BIAS_ALIGN" "ACCOUNT_GUARD_DAILY_LOSS" "ACCOUNT_GUARD_EMERGENCY" "EMERGENCY_CLOSE" "ATR_INIT" "ATR_FALLBACK" "D1_BIAS"; do
  count=$(grep -c "$marker" /tmp/omak_decoded.log 2>/dev/null || echo "0")
  echo "$marker: $count"
done
```

---

OUTPUT RULES

· Format: Professional markdown with fenced code blocks for log excerpts and MQL5 code.
· Tone: Data‑driven, forensic. Every claim backed by a count or a code location.
· Executive Summary: 3‑5 bullets at the top of the report, answering:
  1. Did the pipeline execute trades? (Yes/No + count)
  2. What is the primary bottleneck? (Stage + drop‑off %)
  3. Is the Account Guard sabotaging positions? (Emergency close count + average hold time)
  4. Are C2 closures firing? (Detection count vs lock count)
  5. What is the single highest‑priority fix?

---

PARSER SCRIPT COMPANION UPDATE

The omak_forensic_engine.py script at OmakFxYO/scripts/omak_forensic_engine.py must be verified/updated to extract these additional markers that the v02 prompt was blind to:

```python
# New markers the parser must extract (add to existing marker list):
MARKERS_V03 = [
    "[C2_REJECT]",           # C2 validation failures (categorised)
    "[C2_CLOSURE_DETECTED]", # C2 detected before validation
    "[C2_LOCK_ATTEMPT]",     # C2 attempting to lock
    "[MODAL_UPGRADE]",       # C2→C3 upgrade events
    "[ACCOUNT_GUARD_DAILY_LOSS]",  # Daily loss trigger (count for spam detection)
    "[ACCOUNT_GUARD_EMERGENCY]",   # Emergency DD trigger
    "[EMERGENCY_CLOSE]",     # Individual position emergency close
    "[EXEC_SKIP]",           # Pre-execution guard rejection (if added)
    "InpMaxDailyLossPercent=",     # Runtime parameter value
    "InpEmergencyClosePercent=",   # Runtime parameter value
    "BUILD_ID:",             # EA binary identity
]
```

The script should also detect and flag:

· Log spam: any marker appearing >1,000 times
· Parameter mismatches: runtime value vs known code defaults
· Orphan deals: deals without a pipeline GUID match
· Rapid exits: positions closed <5 minutes after open

---

Golden Rule: The pipeline is alive. Turn good signal generation into robust execution while preserving TTrades Fractal Model + Dow Theory + CRT integrity. No more ghosts — every signal, every deal, every rejection must be traceable end‑to‑end.
