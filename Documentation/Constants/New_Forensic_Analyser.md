# OMAK FXYO — Backtest Log Forensic Analysis (v02 – Robust & Lightweight)
## Pipeline Health & Execution Audit

---

### CONTEXT (Read‑Only)
You are auditing OmakFxYO EA backtest logs. The EA uses TTrades Fractal Model + Dow Theory.
- Branch A: Intraday (D1→H1→M5) – **ACTIVE**
- Branch B: Swing (D1→H4→M15) – **INTENTIONALLY OFF**
- C2 = Anticipation Mode (standalone reversal)
- C3 = Confirmation Mode (standalone or modal upgrade from C2)

### [PARAMETERS]
- **TARGET_LOG:** `"20260518.log"`  
- **LOG_PATH:** `/home/zoro/.var/app/com.usebottles.bottles/data/bottles/bottles/MetaTrader-5/drive_c/Program Files/MetaTrader 5/Tester/Agent-127.0.0.1-3000/logs/`  
  *(Go directly to this path – it's the absolute path)*

**Log format:** MT5 encoded (spaces between characters). Use the parser script to decode. Decode the whole log file, analyse the entire log file. This is non-negotiable.

**Parser script:** `OmakFxYO/scripts/omak_forensic_engine.py` – run it to decode the log.

**Save final report to:** `OmakFxYO/Quant_Backtest_Reports/OmakFxYO_Quant_Forensic_Report_v20.md`

---

### STAGE 0 – DECODE THE LOG (Do this once)
Run the parser script on the target log file to produce a clean plain‑text version.  
From the project root, execute:

```bash
python OmakFxYO/scripts/omak_forensic_engine.py --input "/home/zoro/.../logs/20260518.log" --output "/tmp/omak_decoded.log"
```

(If the script does not have a --decode flag, simply run it as python OmakFxYO/scripts/omak_forensic_engine.py and follow any instructions it prints.)

You now have a decoded log at /tmp/omak_decoded.log. All subsequent commands will use that file – it’s plain text, small, and will never choke.

---

STAGE 1 – PRE‑AUDIT (Read code to understand markers)

Read these files to confirm what markers are produced:

1. OmakFxYO/core/ATREngine.mqh – ATR_Get(), InitATRHandles(), manual fallback
2. OmakFxYO/core/RiskGate.mqh – ExecuteMarketOrder(), PreTradeReadinessGate()
3. OmakFxYO/OmakFxYO.mq5 – OnTick() signal loop, MODE_RESOLVE_LOCKED, CheckSignalExpiry()
4. OmakFxYO/core/ClosureEngine.mqh – C2/C3 locking logic

Rule: Every claim must cite a log line OR a code location (file:function:line).

---

STAGE 2 – PIPELINE HEALTH SNAPSHOT (7 Metrics)

Run these counts on the decoded log file. Use grep -c (it will be fast).

# Metric Log Marker (exact string) Count Survival %
1 Signals Generated [GUID_ASSIGNED]  100%
2 Signals Locked [SIGNAL_LOCKED]  
3 POI Resolved → Ready STAGE_READY (inside an FSM line)  
4 Risk Gate Passed [RG_GATE_PASS]  
5 Execution Triggered [EXEC_TRIGGER]  
6 Order Sent [ORDER_SENT]  
7 Position Opened deal # or [DEAL]  

Critical Question: Where does the pipeline die? Report the exact stage and drop‑off %.

---

STAGE 3 – EXECUTION BOTTLENECK

Count and analyze:

1. RG_GATE_PASS vs EXEC_TRIGGER – if many passes but few triggers, the bottleneck is between RG and execution.
2. EXEC_TRIGGER vs ORDER_SENT – drop indicates failure in ExecuteMarketOrder() / order routing.
3. [ORDER_FAIL] – extract error codes. Use:
   ```bash
   grep "ORDER_FAIL" /tmp/omak_decoded.log | grep -oE "err=[0-9]+" | sort | uniq -c | sort -rn
   ```
4. [ORDER_FAIL] with negative distance – wrong SL/TP side.

Report:

· Error code distribution table
· Most frequent failure reason
· Whether bottleneck is pre‑send or post‑send

---

STAGE 4 – ATR & POI SYSTEM

Count these markers from the decoded log:

Marker Count Meaning
[ATR_INIT] per TF  ATR handle init
[ATR_FALLBACK]  ATR manual fallback used
[EMERGENCY_ATR]  Emergency ATR
[POI_BUFFER_EMERGENCY]  POI buffer emergency
[POI_SANITY_FAIL]  POI sanity check failed
[POI_SANITY_FIX]  Auto‑fix event

Questions:

· Which TF failed ATR init? (TF=PERIOD_D1 etc.)
· If [POI_SANITY_FAIL] > 0, what was the value?
· Did any signal reach [POI_WARNING] at 75% timeout? If 0, flag as dead code.

---

STAGE 5 – SIGNAL LIFECYCLE & DEATH REASONS

Capture expiry reasons:

```bash
grep "SIGNAL_EXPIRED_ENHANCED" /tmp/omak_decoded.log | grep -oE "reason=[A-Z_]+" | sort | uniq -c | sort -rn
```

Also check:

· [COOLDOWN_BLOCK] / [COOLDOWN_SKIP] – is cooldown active?
· [SIGNAL_EXPIRED] – any off‑by‑one (bars=49, max=48)?

Question: Are signals dying from expiry or execution failure?

---

STAGE 6 – C2 vs C3 PERFORMANCE

Count by closure type and mode (use combination of grep and awk if needed):

```bash
grep "SIGNAL_LOCKED" /tmp/omak_decoded.log | grep -oE "closure=CLOSURE_C[23]" | sort | uniq -c
grep -c "mode=ANTICIPATION" /tmp/omak_decoded.log
grep -c "mode=CONFIRMATION" /tmp/omak_decoded.log
grep -c "MODAL_UPGRADE" /tmp/omak_decoded.log
```

Type Locked Executed Orders Sent Success
C2 (Anticipation)    
C3 (Confirmation)    
C3 Modal Upgrade    

Validate: Does standalone C3 execute, or is it blocked waiting for C2?

---

STAGE 7 – CODE‑TO‑LOG TRACEABILITY

For each marker, verify presence in log vs code. Use ✅ (count>0), ⚠️ (count=0 but code exists), ❌ (not found in code).
If ⚠️, explain why it’s not firing.

---

STAGE 8 – PRIORITIZED FIX ROADMAP

Fill a 3‑tier table (P0, P1, P2) with exact issues, evidence, and fix suggestions.

---

APPENDIX – RAW COUNTS

Attach the output of:

```bash
grep -cE "GUID_ASSIGNED|SIGNAL_LOCKED|STAGE_READY|RG_GATE_PASS|EXEC_TRIGGER|ORDER_SENT|ORDER_FAIL|SIGNAL_EXPIRED" /tmp/omak_decoded.log
```

(and any other commands you ran)

---

OUTPUT RULES

· Format: Professional markdown, fenced code blocks for MQL5.
· Tone: Data‑driven, no guesses.
· End with: Executive Summary (3 bullets) + Recommended Next Backtest Protocol.

Golden Rule: The pipeline is now alive. Turn good signal generation into robust execution while preserving TTrades Fractal + Dow Theory integrity.
