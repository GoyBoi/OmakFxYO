OpenCode config: ~/.config/opencode/opencode.json


# TARGET_LOG:       20260601.log  ----- [the logs are UTF-16LE encoded]
# LOG_PATH:         /home/zoro/.var/app/com.usebottles.bottles/data/bottles/bottles/MetaTrader-5/drive_c/Program Files/MetaTrader 5/Tester/Agent-127.0.0.1-3000/logs/  

# REPORT_PATH:      OmakFxYO/Quant_Backtest_Reports/OmakFxYO_Forensic_Report_07.md
# DECODED_LOG:      /tmp/omak_decoded.log


## Running Analysis

### Using CLI (Recommended)

python3 OmakFxYO/scripts/omak_cli.py analyze "<LOG_PATH>/20260601.log"
python3 OmakFxYO/scripts/omak_cli.py analyze "<LOG_PATH>/20260601.log" --clinical


---

# STAGE 00 — DECODE THE LOG


python3 OmakFxYO/scripts/omak_cli.py analyze "<LOG_PATH>/20260601.log"


Verify: wc -l on output. Capture the EA_BUILD line if present.





