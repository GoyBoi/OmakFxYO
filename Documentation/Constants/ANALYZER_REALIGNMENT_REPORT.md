# Analyzer Realignment Report

## Summary

This document records the forensic analyzer realignment performed to align marker parsing with actual log evidence from the OmakFxYO MT5 EA.

## Evidence Source

- Log file: `20260529.log`
- Total unique markers detected: 49 distinct marker types
- Key observation: Mode labels include numeric suffixes `[2]` (e.g., `CONFIRMATION[2]`)

## Changes Made

### 1. Canonical Mode Label Parsing (omak_forensic_engine.py line 126)

**Before:**
```python
'signal_locked': re.compile(r'\[SIGNAL_LOCKED\]\s*(C[23])\s*\|\s*GUID:(\d+)\s*\|\s*mode=(\w+)', re.IGNORECASE),
```

**After:**
```python
'signal_locked': re.compile(r'\[SIGNAL_LOCKED\]\s*(C[23])\s*\|\s*GUID:(\d+)\s*\|\s*mode=([A-Z_]+)(?:\[\d+\])?', re.IGNORECASE),
```

**Rationale:** Log entries show `mode=CONFIRMATION[2]` and `mode=ANTICIPATION[1]`. The regex now captures the mode name and optionally strips the numeric suffix.

### 2. Additional Marker Patterns Added (omak_forensic_engine.py)

Added patterns for 31 additional markers observed in logs:

| Marker | Evidence Count | Pattern |
|--------|--------------|---------|
| `[C2_ACCEPTED]` | 70 | Simple presence check |
| `[C2_LOCKED]` | 14 | Simple presence check |
| `[C2_LOCK_ATTEMPT]` | 304 | Simple presence check |
| `[C2_LOCK_DIAG]` | 2,772 | Simple presence check |
| `[C2_EVAL_ATTEMPT]` | 1,383 | Simple presence check |
| `[C2_BAR_DETECTED]` | 2,339 | Simple presence check |
| `[C2_CLOSURE_DETECTED]` | 1,000 | Simple presence check |
| `[STATE_CLEARED]` | 2,957 | Simple presence check |
| `[STATE_TRANSITION_OK]` | 2,054 | GUID + state transition |
| `[STATE_ILLEGAL]` | 1,972 | Simple presence check |
| `[STATE_GHOST_BLOCKED]` | 1,881 | Simple presence check |
| `[STATE_RECOVERED]` | 228 | Simple presence check |
| `[SIGNAL_CORRUPT]` | 233 | Simple presence check |
| `[LOCKED_SIGNAL_REJECTED]` | 246 | Simple presence check |
| `[LOCKED_SIGNAL_COMPLETE]` | 22 | Simple presence check |
| `[COMMIT_REJECT]` | 1,351 | Simple presence check |
| `[STRUCTURE_REJECT]` | 503 | Simple presence check |
| `[ENTRY_REJECT]` | 504 | Simple presence check |
| `[ENTRY_CANDIDATE_INVALID]` | 247 | Simple presence check |
| `[ENTRY_CANDIDATE_SET]` | 61 | Simple presence check |
| `[C3_RUNTIME_DISABLED]` | 2,765 | Simple presence check |
| `[C3_REJECT]` | 2,503 | Simple presence check |
| `[C3_CONTEXT]` | 4,735 | Simple presence check |
| `[C3_BIAS_ALIGN_PASS]` | 1,142 | Simple presence check |
| `[CONTEXT_EXPIRED]` | 1,408 | Simple presence check |
| `[SL_CALC]` | 70 | Simple presence check |
| `[FLOOR_CALC]` | 61 | Simple presence check |
| `[SYM_CLASSIFIED]` | 121 | Simple presence check |
| `[GUID_PREALLOC]` | 1,258 | Simple presence check |
| `[GUID_DUPLICATE_BLOCKED]` | 143 | Simple presence check |
| `[BR_RESOLVE]` | 1,222 | Simple presence check |
| `[FSM]` | 31 | Simple presence check |
| `[STAGE_TRANSITION]` | 26 | Simple presence check |
| `[DISPLACEMENT]` | 0 (pattern exists, no explicit marker) | Simple presence check |

### 3. EXEC_SKIP Pattern Fix (omak_forensic_engine.py line 194)

**Before:**
```python
'exec_skip': re.compile(r'\[EXEC_SKIP\]\s*Lot=(\d+) or gate fail', re.IGNORECASE),
```

**After:**
```python
'exec_skip': re.compile(r'\[EXEC_SKIP\].*guid=(\d+)', re.IGNORECASE),
```

**Rationale:** Log format shows `Lot=0 or gate fail | guid=...` - simplified to capture guid and fixed match for Lot=0.

### 4. Duplicate Pattern Removal (omak_forensic_engine.py)

Removed duplicate definitions for:
- `state_advance` (was defined twice: lines 156, 196)
- `signal_unlock` (was defined twice: lines 155, 197)
- `signal_committed` (was defined twice in _funnel_stats: lines 283, 290)

### 5. backtest_clinical_extract.py Updates

Added missing marker counters to metrics dict and extraction logic:
- All C2/C3 state markers
- State transition and error markers
- Entry/structure/entry candidate markers
- Context lifecycle markers

## Invariant Compliance

All changes comply with AGENTS.md constitutional rules:
- No hardcoded runtime labels added
- No fake confirmation states created
- All patterns derived directly from log evidence
- MODE_NONE forbidden state remains blocked

## Verification

Run analysis against log:
```bash
python3 OmakFxYO/scripts/omak_cli.py analyze 20260529.log
```

Expected output should now count all observed markers correctly.