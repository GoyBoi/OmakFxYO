# 🕵️‍♂️ PROMPT: OMAK FXYO FORENSIC LOG ANALYZER V3.0
Context: You are a Senior Quantitative Forensic Developer. Your task is to audit the backtest logs of the OmakFxYO v3.0 Finite State Machine (FSM) Engine.
Filesystem Path: /home/zoro/.var/app/com.usebottles.bottles/data/bottles/bottles/MetaTrader-5/drive_c/Program Files/MetaTrader 5/Tester/Agent-127.0.0.1-3000/logs/
Target Log: [20260507.log] 
## I. GLOBAL PIPELINE INTEGRITY (5-POINT SNAPSHOT)
Provide a strict 5-point summary of the engine's mechanical health. Use ✅ if count > 0, ❌ if count is 0.
 1. Unique Signal GUIDs: [Count]
 2. FSM State Transitions (STAGE_NONE → STAGE_WAITING): [Count]
 3. Execution Gate Pass (Pre-Order): [Count]
 4. Broker Handshake (ORDER_SENT): [Count]
 5. Confirmation/Modal Upgrades: [Count]
## II. THE BRANCH A FUNNEL AUDIT
Analyze the survival rate of signals through the FSM stages.
| FSM Stage | Log Marker | Event Count | Survival % |
|---|---|---|---|
| Generation | [GUID_ASSIGNED] |  | 100% |
| Locking | [SIGNAL_LOCKED] |  |  |
| Gating | [RG_GATE_PASS] |  |  |
| POI Target | [STAGE_WAITING_FOR_POI] |  |  |
| Trigger | [STAGE_READY] |  |  |
| Execution | [ORDER_SENT] |  |  |
## III. THE "DEATH LEDGER" (ROOT CAUSE FORENSICS)
Identify the Top 3 Kill Points. You must trace the "Cascade Relationship":
 * The Kill Point: (e.g., PRE_LOCK_RESET or BE_PIPELINE_BLOCKED)
 * Codebase Evidence: Cite the likely File and Line Number (referencing the Handover Dossier).
 * Log Evidence: Paste the exact log string of the failure.
 * The "Why": Explain why this specific line blocked the trade (e.g., "ATR Volatility Guard triggered at 9.2 vs Max 6.0").
## IV. ENGINE "HEARTBEAT" & STALENESS AUDIT
 * Pulse Frequency: Are [HEARTBEAT] events consistent? (Y/N)
 * Data Latency: Scan for [DATA_STALE] or [TIME_SYNC] warnings. Does the heartbeat continue while the pipeline is frozen?
 * The "Inactive Observer" Diagnosis: If Heartbeats are ✅ but Orders are ❌, identify if the engine is stuck in an infinite STAGE_NONE loop or a PRE_LOCK_RESET cycle.
## V. ELITE SHELL COMMANDS (FOR PRE-ANALYSIS)
Run these commands to extract the forensic data:# 1. Check for "Ghost" GUIDs (Critical Bug)
grep "guid=0" | grep -E "RG_GATE|EXECUTION_GATE"

## VI. WHAT'S GOING ON:
- Document samples of raw log files so we can understand the pipeline better. We have to know the flow of our pipeline, we can understand what's going on.
 *- Top sample
 *- Middle sample
 *- Bottom sample
 
 **- Any particular unique or interesting samples we might want to grab and show, so Developers get a much clearer idea of how our pipeline is following -- this might make it easy for us to trace the signals throught the pipeline

# 2. Map FSM State Leakage
grep -o "stage=[0-9]*" | sort | uniq -c

# 3. Identify the "Silent Killer" (Rejection reasons)
grep -E "FAIL|REJECT|BLOCKED|RESET" | awk -F'reason=' '{print $2}' | sort | uniq -c | sort -rn

# 4. Verify GUID Persistence (Did one GUID stay locked too long?)
grep "GUID=" | awk -F'GUID=' '{print $2}' | awk '{print $1}' | sort | uniq -c | sort -rn | head -n 5

# 5. Blindspots:
-- Based on what you see from the codebase and backtests logs, inside the pipeline - What Blindspots does our Architecture have? 

## Output: 
-- Document your report inside a markdown file "Omak_FxYO_Backtest Report_v11.md
