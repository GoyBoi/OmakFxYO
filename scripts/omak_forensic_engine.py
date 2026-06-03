#!/usr/bin/env python3
"""
Omak FxYO Forensic Engine
Canonical log format: 20260425.log
CLI Entry: omak_cli.py
"""

import io
import re
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Optional, Tuple


class SignalType(Enum):
    C2_SWEEP = "C2_SWEEP"
    C3_DISPLACEMENT = "C3_DISPLACEMENT"
    ENTRY_TRIGGER = "ENTRY_TRIGGER"


class BranchType(Enum):
    BRANCH_INTRADAY = "BRANCH_INTRADAY"
    BRANCH_SWING = "BRANCH_SWING"
    BRANCH_A = "BRANCH_A"
    BRANCH_B = "BRANCH_B"


class GateStatus(Enum):
    PASS = "PASS"
    FAIL = "FAIL"
    LOCK = "LOCK"
    UNLOCK = "UNLOCK"


class BiasType(Enum):
    BULLISH = "BULLISH"
    BEARISH = "BEARISH"
    NEUTRAL = "NEUTRAL"
    PENDING = "PENDING"


@dataclass
class SignalEvent:
    signal_id: int
    signal_type: SignalType
    branch_type: BranchType
    active_branch: str
    timestamp: str = ""
    entry_lineno: int = 0
    exit_lineno: int = 0
    raw_lines: List[str] = field(default_factory=list)
    
    mode_prereq_status: GateStatus = GateStatus.FAIL
    rg_gate_status: GateStatus = GateStatus.FAIL
    signal_finalized: bool = False
    
    closure_type: str = ""
    closure_result: str = ""
    direction: str = ""
    
    d1_bias: BiasType = BiasType.NEUTRAL
    structure_bias: BiasType = BiasType.NEUTRAL
    
    validation_error: str = ""
    
    def validate_branch(self) -> Tuple[bool, Optional[str]]:
        if self.branch_type == BranchType.BRANCH_A or self.branch_type == BranchType.BRANCH_INTRADAY:
            branch_id = 0
        else:
            branch_id = 1
            
        if self.mode_prereq_status == GateStatus.FAIL:
            return False, f"MODE PREREQ failed for Branch {branch_id}"
        
        return True, None
    
    def has_logic_leak(self) -> bool:
        has_closure = bool(self.closure_type and self.closure_result == "PASS")
        no_execution = not self.signal_finalized and self.exit_lineno > 0
        return has_closure and no_execution


class GapType(Enum):
    MODE_PREREQ_FAIL = "MODE_PREREQ_FAIL"
    D1_NEUTRAL_LOCK = "D1_NEUTRAL_LOCK"
    SSE_RANGE = "SSE_RANGE"
    LIQUIDITY_MISSING = "LIQUIDITY_MISSING"
    SPREAD_FAIL = "SPREAD_FAIL"
    VOLATILITY_FAIL = "VOLATILITY_FAIL"
    UNKNOWN = "UNKNOWN"


@dataclass
class ExecutionGap:
    signal_id: int
    gap_type: GapType
    closure_lineno: int
    expected_exit_lineno: int
    distance_lines: int
    reason: str


TELEMETRY_VERSION = "omak-forensic-v2.0.0"

class OmakForensicEngine:
    """
    Main forensic analysis engine for MT5 multi-branch EA logs.
    Canonical log format: 20260425.log
    """
    
    CHUNK_SIZE = 10000
    GAP_DETECTION_WINDOW = 20
    LIMIT_LOOKAHEAD = 20

    PATTERNS = {
        'displacement': re.compile(r'\[DISPLACEMENT\]\s+State=(VALID|INVALID)\s*\|\s+Strength=([\d.]+)', re.IGNORECASE),
        'branch_eval': re.compile(r'\[BE\]\s*\[BRANCH=(\w+)\]\s*A=(\w+)\s*B=(\w+)', re.IGNORECASE),
        'session_state': re.compile(r'\[SESSION_STATE\]\s+Current=(\w+)\s+\|\s+IsTrading=(\w+)', re.IGNORECASE),
        'branch_cfg': re.compile(r'\[BRANCH_CFG\]\s*Branch=(\d+)\s*\|\s*BiasSource=([\w_]+)\s*\|\s*StructTF=(\d+)', re.IGNORECASE),
        'mode_decouple': re.compile(r'\[MODE_DECOUPLE\]\s+(.*?)$', re.IGNORECASE),
        'anticipation_gate': re.compile(r'\[ANTICIPATION_GATE\]\s*(C[23]_\w+)\s*[—\-]\s*Awaiting Execution Gate', re.IGNORECASE),
        'confirmation_gate': re.compile(r'\[CONFIRMATION_GATE\]\s*(C[23]_\w+)\s*[—\-]\s*Awaiting Execution Gate', re.IGNORECASE),
        'closure': re.compile(r'\[CLOSURE\]\s*(C[23])=(\w+)\s*\|\s*type=(CLOSURE_\w+)\s*\|\s*(BUY|SELL)', re.IGNORECASE),
        'signal_locked': re.compile(r'\[SIGNAL_LOCKED\]\s*(C[23])\s*\|\s*GUID:(\d+)\s*\|\s*mode=([A-Z_]+)(?:\[\d+\])?', re.IGNORECASE),
        'signal_committed': re.compile(r'\[SIGNAL_COMMITTED\]\s*GUID:(\d+)\s*\|\s*Branch:(\d+)\s*\|\s*Slot:(\d+)', re.IGNORECASE),
        'signal_bridged': re.compile(r'\[SIGNAL_BRIDGED_TO_STORE\]\s*GUID:(\d+)\s*\|\s*Source:([\w_]+)', re.IGNORECASE),
        'execution_entry': re.compile(r'\[EXEC_ENTRY\]\s*GUID=(\d+)\s*\|\s*stage=(\w+)\s*\|\s*isCommitted=(true|false)\s*\|\s*dir=(-?\d+)', re.IGNORECASE),
        'execution_trigger': re.compile(r'\[EXEC_TRIGGER\]\s+GUID[=:](\d+)', re.IGNORECASE),
        'order_result': re.compile(r'\[ORDER\]\s*([A-Z_]+)\s*\|?(.*)', re.IGNORECASE),
        'execution_event': re.compile(r'\[EXEC\]\s*Filling=([A-Z_]+)\s*\|\s*Symbol=([^\s|]+)', re.IGNORECASE),
        'signal_cleared': re.compile(r'\[SIGNAL_CLEARED_BY_GUID\]\s*GUID:(\d+)\s*\|\s*Reason:([A-Z_]+)', re.IGNORECASE),
        'lte_event': re.compile(r'\[LTE\]\s*TIER CHANGE DETECTED.*?Previous:\s*(LT_\w+)\s*\|\s*Current:\s*(LT_\w+)', re.IGNORECASE | re.DOTALL),
        'rg_gate_pass': re.compile(r'\[RG_GATE_PASS\]', re.IGNORECASE),
        'rg_gate_fail': re.compile(r'\[RG_GATE_FAIL\]', re.IGNORECASE),
        'execution_gate_enter': re.compile(r'\[EXEC_GATE\]\s+ENTER', re.IGNORECASE),
        'execution_gate': re.compile(r'\[EXEC_GATE\]', re.IGNORECASE),
        'execution_gate_pass': re.compile(r'\[EXEC_GATE\]\s+PASS', re.IGNORECASE),
        'execution_triggered': re.compile(r'\[EXEC_TRIGGER\]', re.IGNORECASE),
        'order_sent': re.compile(r'\[ORDER_SENT\]', re.IGNORECASE),
        'order_fail': re.compile(r'\[ORDER_FAIL\]', re.IGNORECASE),
        'stage_ready': re.compile(r'STAGE_READY', re.IGNORECASE),
        'stage_waiting_for_poi': re.compile(r'STAGE_WAITING_FOR_POI', re.IGNORECASE),
        'guid_assigned': re.compile(r'\[GUID_ASSIGNED\]', re.IGNORECASE),
        'poi_sanity_pass': re.compile(r'\[POI_SANITY_PASS\]', re.IGNORECASE),
        'poi_sanity_fail': re.compile(r'\[POI_SANITY_FAIL\]', re.IGNORECASE),
        'poi_sanity_cap': re.compile(r'\[POI_SANITY_CAP\]', re.IGNORECASE),
        'atr_init': re.compile(r'\[ATR_INIT\]', re.IGNORECASE),
        'atr_fallback': re.compile(r'ATR_FALLBACK|EMERGENCY_ATR', re.IGNORECASE),
        'exec_summary': re.compile(r'\[EXEC_SUMMARY\]', re.IGNORECASE),
        'take_profit': re.compile(r'take profit triggered', re.IGNORECASE),
        'deal_performed': re.compile(r'deal performed', re.IGNORECASE),
        'ordercheck_reject': re.compile(r'\[ORDER_CHECK_REJECT\]\s+GUID=(\d+)\s+\|\s+Code=(\d+)', re.IGNORECASE),
        'signal_expired': re.compile(r'\[SIGNAL_EXPIRED\]\s*(?:([^\|]+?)\s*\|\s*)?GUID:(\d+)', re.IGNORECASE),
        'cisd_confirmed': re.compile(r'\[CISD_CONFIRMED\]', re.IGNORECASE),
        'signal_unlock': re.compile(r'\[SIGNAL_UNLOCK\]\s+GUID:(\d+)\s+\|\s+Stage:\s*(\w+)', re.IGNORECASE),
        'state_advance': re.compile(r'\[STATE_ADVANCE\]\s+ID:(\d+)\s+\|\s+(.*?)\s+->\s+(.*?)$', re.IGNORECASE),
        'pipeline_entry': re.compile(r'\[PIPELINE_ENTRY\]\s+Processing\s+(C[23]_\w+)\s+for\s+Branch\s+(\w+)', re.IGNORECASE),
        'd1_bias': re.compile(r'\[D1_BIAS\]\s+(\w+)\s+\|\s+prevClose=([\d.]+)\s+\|\s+prior2Low=([\d.]+)', re.IGNORECASE),
        'trade_result': re.compile(r'\[TRADE_RESULT\]\s+(\w+)', re.IGNORECASE),
        'commit_trace': re.compile(r'\[COMMIT_TRACE\]\s+GUID:(\d+)\s+\|\s+Mode:(\d+)\s+\|\s+Branch:(\d+)', re.IGNORECASE),
        'gate_entry': re.compile(r'\[GATE_ENTRY\]\s+GUID:(\d+)\s+\|\s+Mode:(\w+)\s+\|\s+Closure:(\w+)\s+\|\s+Stage:(\w+)', re.IGNORECASE),
        'risk_not_tradeable': re.compile(r'\[RISK_NOT_TRADEABLE\]', re.IGNORECASE),
        'ready_cleared_blocked': re.compile(r'\[READY_CLEARED_BLOCKED\]', re.IGNORECASE),
        'c2_setup_expired': re.compile(r'\[C2_SETUP_EXPIRED\]', re.IGNORECASE),
        'rg_gate_calc': re.compile(r'\[RG_GATE_CALC\]', re.IGNORECASE),
        'bridge_gap': re.compile(r'\[BRIDGE_GAP\]\s+Closure bypassed: g_p9ctx.mode is EMPTY', re.IGNORECASE),
        'exec_gate_fail': re.compile(r'\[EXEC_GATE_FAIL\]\s+reason=(\w+).*?guid=(\d+)', re.IGNORECASE),
        
        # V2: Missing patterns from log analysis
        'account_guard_emergency': re.compile(r'\[ACCOUNT_GUARD_EMERGENCY\].*?DD=([\d.]+)%', re.IGNORECASE),
        'account_guard_daily_loss': re.compile(r'\[ACCOUNT_GUARD_DAILY_LOSS\].*?Loss=([\d.]+)%', re.IGNORECASE),
        'account_guard_cooldown': re.compile(r'\[ACCOUNT_GUARD\].*?cooldown', re.IGNORECASE),
        'c2_reject': re.compile(r'\[C2_REJECT\]\s*(\w+)', re.IGNORECASE),
        'risk_minlot_reject': re.compile(r'\[RISK_MINLOT_REJECT\]', re.IGNORECASE),
        'order_skip': re.compile(r'\[ORDER_SKIP\]', re.IGNORECASE),
        'lot_rejected': re.compile(r'\[ORDER\]\s+LOT_REJECTED', re.IGNORECASE),
        'market_closed': re.compile(r'Market closed', re.IGNORECASE),
        'order_fail_reason': re.compile(r'\[ORDER_FAIL\]\s+reason=(\w+)', re.IGNORECASE),
        'deal_track_entry': re.compile(r'\[DEAL_TRACK\]\s+ENTRY.*?guid=([\-\d]+).*?dir=(\w+).*?price=([\d.]+)', re.IGNORECASE),
        'deal_track_exit': re.compile(r'\[DEAL_TRACK\]\s+EXIT.*?guid=([\-\d]+).*?profit=([\-\d.]+).*?holdMin=(\d+)', re.IGNORECASE),
        'deal_track_summary': re.compile(r'\[DEAL_TRACKED\]\s+ticket=(\d+)\s+\|\s+profit=([\-\d.]+)\s+\|\s+totalDeals=(\d+)\s+\|\s+W=(\d+)\s+L=(\d+)', re.IGNORECASE),

        # Exit markers (3.3)
        'exit_crt_target': re.compile(r'\[EXIT_CRT_TARGET\]\s+GUID=(\d+)', re.IGNORECASE),
        'exit_cisd_reversal': re.compile(r'\[EXIT_CISD_REVERSAL\]\s+GUID=(\d+)', re.IGNORECASE),
        'exit_dow_bos': re.compile(r'\[EXIT_DOW_BOS\]\s+GUID=(\d+)', re.IGNORECASE),
        'exit_trail_stop': re.compile(r'\[EXIT_TRAIL_STOP\]\s+GUID=(\d+)', re.IGNORECASE),
        'exit_sl_hit': re.compile(r'\[EXIT_SL_HIT\]\s+GUID=(\d+)', re.IGNORECASE),
        'exit_emergency_close': re.compile(r'\[EXIT_EMERGENCY_CLOSE\]\s+GUID=(\d+)', re.IGNORECASE),
        
        # Model-aligned markers
        'c1_poi_valid': re.compile(r'\[C1_POI_VALID\]', re.IGNORECASE),
        'c1_poi_miss': re.compile(r'\[C1_POI_MISS\]', re.IGNORECASE),
        'c3_fallback': re.compile(r'\[C3_FALLBACK\]', re.IGNORECASE),
        'trail_psl': re.compile(r'\[TRAIL_PSL\]', re.IGNORECASE),
        'trail_psh': re.compile(r'\[TRAIL_PSH\]', re.IGNORECASE),
        'c2_wick_filter': re.compile(r'\[C2_WICK_FILTER\]', re.IGNORECASE),
        'risk_profile_error': re.compile(r'\[RISK_PROFILE_ERROR\].*?derivedRR=([\d.]+)', re.IGNORECASE),
        'pyramid_add': re.compile(r'\[PYRAMID_ADD\]', re.IGNORECASE),
        'signal_stored': re.compile(r'\[SIGNAL_STORED\]\s*GUID:(\d+)\s*\|\s*branch=(\d+)\s*\|\s*slot=(\d+)', re.IGNORECASE),
        'exec_skip': re.compile(r'\[EXEC_SKIP\].*guid=(\d+)', re.IGNORECASE),
        'state_transition_ok': re.compile(r'\[STATE_TRANSITION_OK\]\s*GUID:(\d+)\s+(\w+)\s*->\s*(\w+)', re.IGNORECASE),
        'c2_accepted': re.compile(r'\[C2_ACCEPTED\]', re.IGNORECASE),
        'state_cleared': re.compile(r'\[STATE_CLEARED\]', re.IGNORECASE),
        'c3_runtime_disabled': re.compile(r'\[C3_RUNTIME_DISABLED\]', re.IGNORECASE),
        'c3_accepted': re.compile(r'\[C3_ACCEPTED\]', re.IGNORECASE),
        'c4_accepted': re.compile(r'\[C4_ACCEPTED\]', re.IGNORECASE),
        'pipeline_kill': re.compile(r'\[PIPELINE_KILL\]', re.IGNORECASE),
        'sl_terminate': re.compile(r'\[SL_TERMINATE\]', re.IGNORECASE),
        'c1_poi_valid': re.compile(r'\[C1_POI_VALID\]', re.IGNORECASE),
        'c1_poi_miss': re.compile(r'\[C1_POI_MISS\]', re.IGNORECASE),
        'c3_fallback': re.compile(r'\[C3_FALLBACK\]', re.IGNORECASE),
        'trail_psl': re.compile(r'\[TRAIL_PSL\]', re.IGNORECASE),
        'trail_psh': re.compile(r'\[TRAIL_PSH\]', re.IGNORECASE),
        'c2_wick_filter': re.compile(r'\[C2_WICK_FILTER\]', re.IGNORECASE),
        'risk_profile_error': re.compile(r'\[RISK_PROFILE_ERROR\].*?derivedRR=([\d.]+)', re.IGNORECASE),
        'pyramid_add': re.compile(r'\[PYRAMID_ADD\]', re.IGNORECASE),
        'signal_stored': re.compile(r'\[SIGNAL_STORED\]\s*GUID:(\d+)\s*\|\s*branch=(\d+)\s*\|\s*slot=(\d+)', re.IGNORECASE),
        'signal_corrupt': re.compile(r'\[SIGNAL_CORRUPT\]', re.IGNORECASE),
        'locked_signal_rejected': re.compile(r'\[LOCKED_SIGNAL_REJECTED\]', re.IGNORECASE),
        'commit_reject': re.compile(r'\[COMMIT_REJECT\]', re.IGNORECASE),
        'structure_reject': re.compile(r'\[STRUCTURE_REJECT\]', re.IGNORECASE),
        'entry_reject': re.compile(r'\[ENTRY_REJECT\]', re.IGNORECASE),
        'entry_candidate_invalid': re.compile(r'\[ENTRY_CANDIDATE_INVALID\]', re.IGNORECASE),
        'entry_candidate_set': re.compile(r'\[ENTRY_CANDIDATE_SET\]', re.IGNORECASE),
        'c2_lock_diag': re.compile(r'\[C2_LOCK_DIAG\]', re.IGNORECASE),
        'c3_context': re.compile(r'\[C3_CONTEXT\]', re.IGNORECASE),
        'context_expired': re.compile(r'\[CONTEXT_EXPIRED\]', re.IGNORECASE),
        'state_illegal': re.compile(r'\[STATE_ILLEGAL\]', re.IGNORECASE),
        'state_ghost_blocked': re.compile(r'\[STATE_GHOST_BLOCKED\]', re.IGNORECASE),
        'state_recovered': re.compile(r'\[STATE_RECOVERED\]', re.IGNORECASE),
        'c2_locked': re.compile(r'\[C2_LOCKED\]', re.IGNORECASE),
        'c2_bar_detected': re.compile(r'\[C2_BAR_DETECTED\]', re.IGNORECASE),
        'c2_closure_detected': re.compile(r'\[C2_CLOSURE_DETECTED\]', re.IGNORECASE),
        'c2_lock_attempt': re.compile(r'\[C2_LOCK_ATTEMPT\]', re.IGNORECASE),
        'c2_eval_attempt': re.compile(r'\[C2_EVAL_ATTEMPT\]', re.IGNORECASE),
        'c3_reject': re.compile(r'\[C3_REJECT\]', re.IGNORECASE),
        'c3_bias_align_pass': re.compile(r'\[C3_BIAS_ALIGN_PASS\]', re.IGNORECASE),
        'sl_calc': re.compile(r'\[SL_CALC\]', re.IGNORECASE),
        'floor_calc': re.compile(r'\[FLOOR_CALC\]', re.IGNORECASE),
        'sym_classified': re.compile(r'\[SYM_CLASSIFIED\]', re.IGNORECASE),
        'guid_prealloc': re.compile(r'\[GUID_PREALLOC\]', re.IGNORECASE),
        'guid_duplicate_blocked': re.compile(r'\[GUID_DUPLICATE_BLOCKED\]', re.IGNORECASE),
        'br_resolve': re.compile(r'\[BR_RESOLVE\]', re.IGNORECASE),
        'locked_signal_complete': re.compile(r'\[LOCKED_SIGNAL_COMPLETE\]', re.IGNORECASE),
        'fsm': re.compile(r'\[FSM\]', re.IGNORECASE),
        'stage_transition': re.compile(r'\[STAGE_TRANSITION\]', re.IGNORECASE),
        'signal_expired_enhanced': re.compile(r'\[SIGNAL_EXPIRED_ENHANCED\]', re.IGNORECASE),
        'init_marker': re.compile(r'\[INIT\]', re.IGNORECASE),
        'displacement_marker': re.compile(r'\[DISPLACEMENT\]', re.IGNORECASE),
        'signal_force_cleared': re.compile(r'\[SIGNAL_FORCE_CLEARED\]', re.IGNORECASE),
        'c3_lock_attempt': re.compile(r'\[C3_LOCK_ATTEMPT\]', re.IGNORECASE),
        'lock_call': re.compile(r'\[LOCK_CALL\]', re.IGNORECASE),
        'sl_terminate': re.compile(r'\[SL_TERMINATE\]', re.IGNORECASE),

        # V6: All canonical markers from AGENTS.md §VIII
        'wick_rule_block': re.compile(r'\[WICK_RULE_BLOCK\]', re.IGNORECASE),
        'wick_rule_pass': re.compile(r'\[WICK_RULE_PASS\]', re.IGNORECASE),
        'cisd_failed': re.compile(r'\[CISD_FAILED\]', re.IGNORECASE),
        'tspot_poi_mapped': re.compile(r'\[TSPOT_POI_MAPPED\]', re.IGNORECASE),
        'tspot_poi_missing': re.compile(r'\[TSPOT_POI_MISSING\]', re.IGNORECASE),
        'time_filter_block': re.compile(r'\[TIME_FILTER_BLOCK\]', re.IGNORECASE),
        'time_filter_pass': re.compile(r'\[TIME_FILTER_PASS\]', re.IGNORECASE),
        'smt_divergence_pass': re.compile(r'\[SMT_DIVERGENCE_PASS\]', re.IGNORECASE),
        'smt_divergence_fail': re.compile(r'\[SMT_DIVERGENCE_FAIL\]', re.IGNORECASE),
        'bias_aligned': re.compile(r'\[BIAS_ALIGNED\]', re.IGNORECASE),
        'bias_misaligned': re.compile(r'\[BIAS_MISALIGNED\]', re.IGNORECASE),
        'htf_target_hit': re.compile(r'\[HTF_TARGET_HIT\]', re.IGNORECASE),
        'reset_htf_target': re.compile(r'\[RESET_HTF_TARGET\]', re.IGNORECASE),
        'risk_2r_violation': re.compile(r'\[RISK_2R_VIOLATION\]', re.IGNORECASE),
        'state_mutation': re.compile(r'\[STATE_MUTATION\]', re.IGNORECASE),
        'handover_timeout': re.compile(r'\[HANDOVER_TIMEOUT\]', re.IGNORECASE),
        'handover_acquired': re.compile(r'\[HANDOVER_ACQUIRED\]', re.IGNORECASE),
        'handover_transferred': re.compile(r'\[HANDOVER_TRANSFERRED\]', re.IGNORECASE),
        'handover_released': re.compile(r'\[HANDOVER_RELEASED\]', re.IGNORECASE),
        'handover_forced_release': re.compile(r'\[HANDOVER_FORCED_RELEASE\]', re.IGNORECASE),
        'risk_floor_block': re.compile(r'\[RISK_FLOOR_BLOCK\]', re.IGNORECASE),
        'c3_demoted_to_c2': re.compile(r'\[C3_DEMOTED_TO_C2\]', re.IGNORECASE),
        'c4_blocked': re.compile(r'\[C4_BLOCKED\]', re.IGNORECASE),
        'stage_ready_protected': re.compile(r'\[STAGE_READY_PROTECTED\]', re.IGNORECASE),
        'ready_cleared_blocked': re.compile(r'\[READY_CLEARED_BLOCKED\]', re.IGNORECASE),
    }
    
    def __init__(self, filepath: str, encoding: str = 'utf-8'):
        self.filepath = filepath
        self.encoding = encoding
        self.signals: Dict[int, SignalEvent] = {}
        self._current_signal: Optional[SignalEvent] = None
        self._last_closure_lineno: int = 0
        self._active_branch: int = 0
        
        self._lines_processed = 0
        self._bytes_processed = 0
        
        self._active_branch_for_stats = "BRANCH_A"
        
        self._unique_guids: set = set()
        
        self._funnel_stats = {
            'total_lines': 0,
            'pipeline_entries': 0,
            'branch_configs': 0,
            'branch_evaluations': 0,
            'branch_a_ok': 0,
            'branch_a_fail': 0,
            'branch_b_ok': 0,
            'branch_b_fail': 0,
            'branch_a_signals': 0,
            'branch_b_signals': 0,
            'branch_a_stage_poi': 0,
            'branch_b_stage_poi': 0,
            'branch_a_rg_gate_pass': 0,
            'branch_b_rg_gate_pass': 0,
            'branch_a_exec_gate_pass': 0,
            'branch_b_exec_gate_pass': 0,
            'branch_a_trades': 0,
            'branch_b_trades': 0,
            'anticipation_gate_awaits': 0,
            'anticipation_gate_unlocks': 0,
            'anticipation_gate_locks': 0,
            'confirmation_gate_awaits': 0,
            'confirmation_gate_unlocks': 0,
            'confirmation_gate_locks': 0,
            'bias_overrides': 0,
            'closures': 0,
            'c2_closures': 0,
            'c3_closures': 0,
            'closure_c2_pass': 0,
            'closure_c3_pass': 0,
            'd1_bias_bullish': 0,
            'd1_bias_bearish': 0,
            'd1_bias_neutral': 0,
            'execution_gaps': 0,
            'mode_prereq_blocks': 0,
            'sse_range_blocks': 0,
            'liquidity_blocks': 0,
            'trade_executions': 0,
            'trade_exec_market_buy': 0,
            'trade_exec_market_sell': 0,
            'trade_exec_limit': 0,
            'rg_gate_breakout': 0,
            'rg_gate_retrace': 0,
            'rg_limit_set': 0,
            'rg_limit_expired': 0,
            'execution_gate_pass': 0,
            'stage_waiting_for_poi': 0,
            'state_advance': 0,
            'registry_signal': 0,
            'obs_exec': 0,
            'obs_lot': 0,
            'session_blocks': 0,
            'session_events': 0,
            'data_stale': 0,
            'rg_gate_pass': 0,
            'execution_gate_market_deferred': 0,
            'signal_wait': 0,
            'displacement_valid': 0,
            'displacement_invalid': 0,
            'struct_overrides_d1_neutral': 0,
             'ordercheck_rejects': 0,
            'signal_locked': 0,
            'signal_unlocks': 0,
            'signal_expirations': 0,
            'mode_decouples': 0,
            # NEW tracking
            'signal_committed': 0,
            'signal_stored': 0,
            'exec_skip': 0,
            'state_transition_ok': 0,
            'risk_profile_error': 0,
            'rr_violated_zero': 0,
            # NEW tracking
            'signal_committed': 0,
            'signal_bridged': 0,
            'execution_entry': 0,
            'execution_trigger': 0,
            'execution_trigger_fail': 0,
            'order_events': 0,
            'order_invalid': 0,
            'signal_cleared': 0,
            'lot_debug': 0,
            'lot_calc': 0,
            'lot_final': 0,
            'lte_events': 0,
            'exec_gate_fail': 0,
            # V5 enhanced tracking
            'guid_assigned': 0,
            'rg_gate_fail': 0,
            'execution_triggered': 0,
            'order_fail': 0,
            'stage_ready': 0,
            'stage_waiting_for_poi': 0,
            'poi_sanity_pass': 0,
            'poi_sanity_fail': 0,
            'poi_sanity_cap': 0,
            'atr_init': 0,
            'atr_fallback': 0,
            'exec_summary': 0,
            'take_profit': 0,
            'deal_performed': 0,
            'branch_a': 0,
            'branch_b': 0,
            'anticipation_mode': 0,
            'confirmation_mode': 0,
            
            # V2: Account Guard tracking
            'account_guard_emergency': 0,
            'account_guard_daily_loss': 0,
            'account_guard_cooldown': 0,
            'account_guard_peak_dd': 0.0,
            
# V2: C2 rejection tracking
            'c2_reject_total': 0,

            # V2: Risk minLot tracking
            'risk_minlot_reject': 0,

            # V2: Order skip/reject tracking
            'order_skip': 0,
            'lot_rejected': 0,
            'exec_gate_enter': 0,
            'risk_not_tradeable': 0,
            'ready_cleared_blocked': 0,
            'c2_setup_expired': 0,

            # V2: Order failure tracking
            'market_closed': 0,
            'order_fail_max_retries': 0,

            # V2: Trade P/L tracking
            'deals_total': 0,
            'deals_buy': 0,
            'deals_sell': 0,
            'trades_roundtrip': 0,
            'trades_tracked': 0,
            'trades_wins': 0,
            'trades_losses': 0,
            'trades_untracked_emergency': 0,
            'total_profit': 0.0,
            'avg_hold_time_min': 0.0,

            # Exit markers (3.3)
            'exit_crt_target': 0,
            'exit_cisd_reversal': 0,
            'exit_dow_bos': 0,
            'exit_trail_stop': 0,
            'exit_sl_hit': 0,
            'exit_emergency_close': 0,

            # Model-aligned markers
            'c1_poi_valid': 0,
            'c1_poi_miss': 0,
            'c3_fallback': 0,
            'trail_psl': 0,
            'trail_psh': 0,
            'c2_wick_filter': 0,
            'pyramid_add': 0,

            # Additional model markers
            'c2_accepted': 0,
            'c2_locked': 0,
            'c2_lock_attempt': 0,
            'c2_lock_diag': 0,
            'c2_eval_attempt': 0,
            'c2_bar_detected': 0,
            'c2_closure_detected': 0,
            'c3_context': 0,
            'c3_runtime_disabled': 0,
            'c3_accepted': 0,
            'c3_reject': 0,
            'c4_accepted': 0,
            'pipeline_kill': 0,
            'c3_bias_align_pass': 0,
            'state_cleared': 0,
            'state_illegal': 0,
            'state_ghost_blocked': 0,
            'state_recovered': 0,
            'state_transition_ok': 0,
            'signal_corrupt': 0,
            'locked_signal_rejected': 0,
            'locked_signal_complete': 0,
            'commit_reject': 0,
            'structure_reject': 0,
            'entry_reject': 0,
            'entry_candidate_invalid': 0,
            'entry_candidate_set': 0,
            'context_expired': 0,
            'displacement_marker': 0,
            'sl_calc': 0,
            'floor_calc': 0,
            'sym_classified': 0,
            'guid_prealloc': 0,
            'guid_duplicate_blocked': 0,
            'br_resolve': 0,
            'fsm': 0,
            'stage_transition': 0,
            'signal_expired_enhanced': 0,
            'init_marker': 0,
            'cisd_confirmed': 0,
            'signal_force_cleared': 0,
            'c3_lock_attempt': 0,
            'lock_call': 0,
            'sl_terminate': 0,

            # V6: Full canonical marker set (AGENTS.md §VIII)
            'wick_rule_block': 0,
            'wick_rule_pass': 0,
            'cisd_failed': 0,
            'tspot_poi_mapped': 0,
            'tspot_poi_missing': 0,
            'time_filter_block': 0,
            'time_filter_pass': 0,
            'smt_divergence_pass': 0,
            'smt_divergence_fail': 0,
            'bias_aligned': 0,
            'bias_misaligned': 0,
            'htf_target_hit': 0,
            'reset_htf_target': 0,
            'risk_2r_violation': 0,
            'state_mutation': 0,
            'handover_timeout': 0,
            'handover_acquired': 0,
            'handover_transferred': 0,
            'handover_released': 0,
            'handover_forced_release': 0,
            'risk_floor_block': 0,
            'c3_demoted_to_c2': 0,
            'c4_blocked': 0,
            'stage_ready_protected': 0,
        }
        
        self._bias_conflicts: Dict[str, int] = defaultdict(int)
        self._execution_gaps: List[ExecutionGap] = []
        
        self._recent_closures: List[Tuple[int, str, str, str]] = []
        self._log_lines: List[str] = []
        self._line_to_index: Dict[int, int] = {}
        
        # V2: Trade lifecycle tracking
        self._pending_entries: Dict[str, Dict] = {}  # guid -> entry data
        self._completed_trades: List[Dict] = []  # list of completed trades with P/L
    
    def _handle_branch_cfg(self, lineno: int, line: str, match: re.Match) -> None:
        branch_id = match.group(1)
        bias_source = match.group(2)
        struct_tf = match.group(3)
        
        self._funnel_stats['branch_configs'] += 1
        self._active_branch_for_stats = f"BRANCH_{branch_id}"
    
    def _handle_rg_gate_pass(self, lineno: int, line: str) -> None:
        self._funnel_stats['rg_gate_pass'] += 1
        if self._active_branch_for_stats == "BRANCH_0" or self._active_branch_for_stats == "BRANCH_A":
            self._funnel_stats['branch_a_rg_gate_pass'] += 1
        else:
            self._funnel_stats['branch_b_rg_gate_pass'] += 1
    
    def _handle_execution_gate_pass(self, lineno: int, line: str) -> None:
        self._funnel_stats['execution_gate_pass'] += 1
        if self._active_branch_for_stats == "BRANCH_0" or self._active_branch_for_stats == "BRANCH_A":
            self._funnel_stats['branch_a_exec_gate_pass'] += 1
        else:
            self._funnel_stats['branch_b_exec_gate_pass'] += 1
    
    def _handle_exec_gate_fail(self, lineno: int, line: str, match: re.Match) -> None:
        reason = match.group(1).upper()
        guid = match.group(2)
        self._funnel_stats['exec_gate_fail'] += 1
        reason_key = f"exec_gate_fail_{reason.lower()}"
        self._funnel_stats[reason_key] = self._funnel_stats.get(reason_key, 0) + 1
        if guid:
            self._unique_guids.add(int(guid))

    def _handle_order_sent(self, lineno: int, line: str, match: re.Match) -> None:
        direction = match.group(1)
        price = match.group(2)
        
        self._funnel_stats['trade_executions'] += 1
        if self._active_branch_for_stats == "BRANCH_0" or self._active_branch_for_stats == "BRANCH_A":
            self._funnel_stats['branch_a_trades'] += 1
        else:
            self._funnel_stats['branch_b_trades'] += 1
        
        if direction.upper() == "BUY":
            self._funnel_stats['trade_exec_market_buy'] += 1
        else:
            self._funnel_stats['trade_exec_market_sell'] += 1
    
    def _handle_signal_unlock(self, lineno: int, line: str, match: re.Match) -> None:
        signal_id = match.group(1)
        stage = match.group(2)
        self._funnel_stats['signal_unlocks'] = self._funnel_stats.get('signal_unlocks', 0) + 1
    
    def _handle_signal_expired(self, lineno: int, line: str, match: re.Match) -> None:
        reason = (match.group(1) or "").strip()
        guid = match.group(2)
        self._funnel_stats['signal_expirations'] = self._funnel_stats.get('signal_expirations', 0) + 1
        self._unique_guids.add(int(guid))
    
    def _handle_ordercheck_reject(self, lineno: int, line: str, match: re.Match) -> None:
        guid = match.group(1)
        retcode = match.group(2)
        self._funnel_stats['ordercheck_rejects'] += 1
        self._unique_guids.add(int(guid))
    
    def _handle_signal_locked(self, lineno: int, line: str, match: re.Match) -> None:
        signal_type = match.group(1)
        guid = match.group(2)
        mode = match.group(3)
        
        self._funnel_stats['signal_locked'] += 1
        self._unique_guids.add(int(guid))
    
    def _handle_registry(self, lineno: int, line: str, match: re.Match) -> None:
        signal_id = match.group(1)
        self._funnel_stats['registry_signal'] += 1
        self._unique_guids.add(int(signal_id))
    
    def _handle_rg_gate_triggered(self, lineno: int, line: str, match: re.Match) -> None:
        direction = match.group(1)
        trigger_type = match.group(2)
        
        if trigger_type.upper() == "BREAKOUT":
            self._funnel_stats['rg_gate_breakout'] += 1
        else:
            self._funnel_stats['rg_gate_retrace'] += 1
    
    def _handle_limit_set(self, lineno: int, line: str, match: re.Match) -> None:
        direction = match.group(1)
        price = match.group(2)
        self._funnel_stats['rg_limit_set'] += 1
    
    def _handle_mode_decouple(self, lineno: int, line: str, match: re.Match) -> None:
        self._funnel_stats['mode_decouples'] = self._funnel_stats.get('mode_decouples', 0) + 1
    
    def analyze(self, sample_limit: Optional[int] = None, run_leak_diagnosis: bool = True) -> Dict[int, SignalEvent]:
        # P0 FIX: Always analyze FULL log file - sample mode disabled to prevent contaminated reports
        # Forensic analysis REQUIRES complete log coverage for accurate diagnosis
        import time
        _start_ts = time.time()

        if sample_limit is not None:
            print(f"[WARNING] sample_limit={sample_limit} ignored — forcing FULL log analysis for forensic accuracy")
            sample_limit = None  # Force full analysis
        
        self._ingest_log(sample_limit)
        self._detect_execution_gaps()
        if run_leak_diagnosis:
            self._run_pipeline_leak_diagnosis()
        self._finalize_signals()

        _elapsed = time.time() - _start_ts
        _signals_finalized = sum(1 for s in self.signals.values() if s.signal_finalized)
        _signals_leaked = len(self._execution_gaps)
        _total_guids = len(self._unique_guids)
        _trades = self._funnel_stats.get('trade_executions', 0)

        print(f"[OMAK_TELEMETRY] version={TELEMETRY_VERSION} "
              f"duration={_elapsed:.2f}s "
              f"lines={self._funnel_stats.get('total_lines',0)} "
              f"guids={_total_guids} "
              f"signals={_signals_finalized} "
              f"leaks={_signals_leaked} "
              f"trades={_trades} "
              f"pipeline_entries={self._funnel_stats.get('pipeline_entries',0)}")

        return self.signals
    
    def _run_pipeline_leak_diagnosis(self) -> None:
        """
        Run diagnose_pipeline_leak for each dead signal found.
        """
        for closure_rec in self._recent_closures:
            closure_lineno, closure_type, closure_result, direction = closure_rec
            
            if closure_result != "PASS":
                continue
            
            signal_id = closure_lineno
            diagnosis = self.diagnose_pipeline_leak(self._log_lines, closure_lineno, signal_id)
            
            if diagnosis['status'] == 'DEAD':
                self._bias_conflicts[f"LEAK_{diagnosis['prereq_gate']}"] += 1
    
    def _ingest_log(self, sample_limit: Optional[int] = None) -> None:
        file_handle = None
        
        for enc in [self.encoding, 'utf-16', 'utf-16-le', 'utf-16-be', 'utf-8', 'utf-8-sig']:
            try:
                file_handle = io.open(
                    self.filepath,
                    mode='r',
                    encoding=enc,
                    errors='ignore'
                )
                break
            except (UnicodeDecodeError, LookupError):
                continue
        
        if file_handle is None:
            raise RuntimeError(f"Could not decode file: {self.filepath}")
        
        with file_handle as f:
            while True:
                chunk = f.readlines(self.CHUNK_SIZE)
                if not chunk:
                    break
                
                for line in chunk:
                    line = self._clean_line(line)
                    if not line.strip():
                        continue
                    
                    self._lines_processed += 1
                    self._funnel_stats['total_lines'] += 1
                    
                    self._line_to_index[self._lines_processed] = len(self._log_lines)
                    self._log_lines.append(line)
                    
                    if sample_limit and self._lines_processed > sample_limit:
                        return
                    
                    self._process_line(line)
                
                self._bytes_processed += sum(len(l) for l in chunk)
    
    def _clean_line(self, line: str) -> str:
        if line.startswith('\ufeff'):
            line = line[1:]
        return line.strip()
    
    def _process_line(self, line: str) -> None:
        lineno = self._lines_processed
        
        if match := self.PATTERNS['displacement'].search(line):
            state = match.group(1).upper()
            if state == 'VALID':
                self._funnel_stats['displacement_valid'] += 1
            else:
                self._funnel_stats['displacement_invalid'] += 1
            return
        
        if match := self.PATTERNS['branch_eval'].search(line):
            branch_name = match.group(1).upper()
            a_result = match.group(2).upper()
            b_result = match.group(3).upper()
            
            self._funnel_stats['branch_evaluations'] += 1
            if branch_name in ['A', 'INTRADAY']:
                if a_result == "OK":
                    self._funnel_stats['branch_a_ok'] += 1
                else:
                    self._funnel_stats['branch_a_fail'] += 1
            if branch_name in ['B', 'SWING']:
                if b_result == "OK":
                    self._funnel_stats['branch_b_ok'] += 1
                else:
                    self._funnel_stats['branch_b_fail'] += 1
            
            if self._current_signal:
                if a_result == "OK":
                    self._current_signal.mode_prereq_status = GateStatus.PASS
                else:
                    self._current_signal.mode_prereq_status = GateStatus.FAIL
            return
        
        if match := self.PATTERNS['session_state'].search(line):
            return
        
        if match := self.PATTERNS['branch_cfg'].search(line):
            self._handle_branch_cfg(lineno, line, match)
            return

        if match := self.PATTERNS['anticipation_gate'].search(line):
            self._funnel_stats['anticipation_gate_awaits'] += 1
            return

        if match := self.PATTERNS['confirmation_gate'].search(line):
            self._funnel_stats['confirmation_gate_awaits'] += 1
            return

        if match := self.PATTERNS['rg_gate_pass'].search(line):
            self._handle_rg_gate_pass(lineno, line)
            return

        if match := self.PATTERNS['execution_gate_pass'].search(line):
            self._handle_execution_gate_pass(lineno, line)
            return
            
        if self.PATTERNS['execution_gate'].search(line):
            self._funnel_stats['exec_gate_enter'] = self._funnel_stats.get('exec_gate_enter', 0) + 1
            return

        if match := self.PATTERNS['ordercheck_reject'].search(line):
            self._handle_ordercheck_reject(lineno, line, match)
            return

        if match := self.PATTERNS['signal_locked'].search(line):
            self._handle_signal_locked(lineno, line, match)
            return

        if match := self.PATTERNS['signal_unlock'].search(line):
            self._handle_signal_unlock(lineno, line, match)
            return

        if match := self.PATTERNS['signal_expired'].search(line):
            self._handle_signal_expired(lineno, line, match)
            return

        if self.PATTERNS['cisd_confirmed'].search(line):
            self._funnel_stats['cisd_confirmed'] += 1
            return

        if match := self.PATTERNS['signal_committed'].search(line):
            self._handle_signal_committed(lineno, line, match)
            return

        if match := self.PATTERNS['signal_stored'].search(line):
            self._handle_signal_stored(lineno, line, match)
            return

        if match := self.PATTERNS['exec_skip'].search(line):
            self._handle_exec_skip(lineno, line, match)
            return

        # V2: Gate entry pattern (full format from logs)
        if match := self.PATTERNS['gate_entry'].search(line):
            guid = match.group(1)
            mode = match.group(2)
            closure = match.group(3)
            stage = match.group(4)
            self._funnel_stats['gate_entry'] = self._funnel_stats.get('gate_entry', 0) + 1
            self._unique_guids.add(int(guid))
            return

        # V2: Risk not tradeable (lot calc failure)
        if self.PATTERNS['risk_not_tradeable'].search(line):
            self._funnel_stats['risk_not_tradeable'] = self._funnel_stats.get('risk_not_tradeable', 0) + 1
            return

        # V2: READY_CLEARED_BLOCKED (protected READY signal skipped)
        if self.PATTERNS['ready_cleared_blocked'].search(line):
            self._funnel_stats['ready_cleared_blocked'] = self._funnel_stats.get('ready_cleared_blocked', 0) + 1
            return

        # V2: C2_SETUP_EXPIRED (setup timeout)
        if self.PATTERNS['c2_setup_expired'].search(line):
            self._funnel_stats['c2_setup_expired'] = self._funnel_stats.get('c2_setup_expired', 0) + 1
            return

        # V2: RG_GATE_CALC
        if self.PATTERNS['rg_gate_calc'].search(line):
            self._funnel_stats['rg_gate_calc'] = self._funnel_stats.get('rg_gate_calc', 0) + 1
            return

        # V2: EXEC_GATE ENTER (distinct from generic EXEC_GATE)
        if self.PATTERNS['execution_gate_enter'].search(line):
            self._funnel_stats['exec_gate_enter'] = self._funnel_stats.get('exec_gate_enter', 0) + 1
            return

        if match := self.PATTERNS['state_transition_ok'].search(line):
            self._handle_state_transition_ok(lineno, line, match)
            return

        if match := self.PATTERNS['signal_bridged'].search(line):
            self._handle_signal_bridged(lineno, line, match)
            return

        if match := self.PATTERNS['execution_entry'].search(line):
            self._handle_execution_entry(lineno, line, match)
            return

        if match := self.PATTERNS['execution_trigger'].search(line):
            self._handle_execution_trigger(lineno, line, match)
            return

        if match := self.PATTERNS['order_result'].search(line):
            self._handle_order_result(lineno, line, match)
            return

        if match := self.PATTERNS['execution_event'].search(line):
            self._handle_execution_event(lineno, line, match)
            return

        if match := self.PATTERNS['signal_cleared'].search(line):
            self._handle_signal_cleared(lineno, line, match)
            return

        if match := self.PATTERNS['lte_event'].search(line):
            self._handle_lte_event(lineno, line, match)
            return
        
        if match := self.PATTERNS['displacement'].search(line):
            self._handle_displacement(lineno, line, match)
            return
        
        if match := self.PATTERNS['branch_eval'].search(line):
            self._handle_branch_eval(lineno, line, match)
            return
        
        if match := self.PATTERNS['closure'].search(line):
            self._handle_closure(lineno, line, match)
            return
        
        # V5 Enhanced Pattern Matching
        if self.PATTERNS['guid_assigned'].search(line):
            self._funnel_stats['guid_assigned'] += 1
            return
        
        if self.PATTERNS['rg_gate_fail'].search(line):
            self._funnel_stats['rg_gate_fail'] += 1
            return
        
        if match := self.PATTERNS['exec_gate_fail'].search(line):
            self._handle_exec_gate_fail(lineno, line, match)
            return
        
        # V6: Consolidated EXEC_TRIGGER tracking (single count — no double-count)
        # Note: handled above via execution_trigger handler with _handle_execution_trigger
        
        if self.PATTERNS['order_fail'].search(line):
            self._funnel_stats['order_fail'] += 1
            return
        
        if self.PATTERNS['stage_ready'].search(line):
            self._funnel_stats['stage_ready'] += 1
            return
        
        if self.PATTERNS['stage_waiting_for_poi'].search(line):
            self._funnel_stats['stage_waiting_for_poi'] += 1
            return
        
        if self.PATTERNS['poi_sanity_pass'].search(line):
            self._funnel_stats['poi_sanity_pass'] += 1
            return
        
        if self.PATTERNS['poi_sanity_fail'].search(line):
            self._funnel_stats['poi_sanity_fail'] += 1
            return
        
        if self.PATTERNS['poi_sanity_cap'].search(line):
            self._funnel_stats['poi_sanity_cap'] += 1
            return
        
        if self.PATTERNS['atr_init'].search(line):
            self._funnel_stats['atr_init'] += 1
            return
        
        if self.PATTERNS['atr_fallback'].search(line):
            self._funnel_stats['atr_fallback'] += 1
            return
        
        if self.PATTERNS['exec_summary'].search(line):
            self._funnel_stats['exec_summary'] += 1
            return
        
        if self.PATTERNS['take_profit'].search(line):
            self._funnel_stats['take_profit'] += 1
            return
        
        if self.PATTERNS['deal_performed'].search(line):
            self._funnel_stats['deal_performed'] += 1
            if 'buy' in line.lower():
                self._funnel_stats['deals_buy'] += 1
                self._funnel_stats['deals_total'] += 1
            elif 'sell' in line.lower():
                self._funnel_stats['deals_sell'] += 1
                self._funnel_stats['deals_total'] += 1
            return
        
        # V2: Account Guard patterns
        if match := self.PATTERNS['account_guard_emergency'].search(line):
            dd = float(match.group(1))
            self._funnel_stats['account_guard_emergency'] += 1
            if dd > self._funnel_stats['account_guard_peak_dd']:
                self._funnel_stats['account_guard_peak_dd'] = dd
            return
        
        if match := self.PATTERNS['account_guard_daily_loss'].search(line):
            self._funnel_stats['account_guard_daily_loss'] += 1
            return
        
        if self.PATTERNS['account_guard_cooldown'].search(line):
            self._funnel_stats['account_guard_cooldown'] += 1
            return
        
        # V2: C2 rejection pattern
        if match := self.PATTERNS['c2_reject'].search(line):
            self._funnel_stats['c2_reject_total'] += 1
            return

        # V2: Risk minLot reject pattern
        if self.PATTERNS['risk_minlot_reject'].search(line):
            self._funnel_stats['risk_minlot_reject'] = self._funnel_stats.get('risk_minlot_reject', 0) + 1
            return

        # V2: Order skip pattern
        if self.PATTERNS['order_skip'].search(line):
            self._funnel_stats['order_skip'] = self._funnel_stats.get('order_skip', 0) + 1
            return

        # V2: Lot rejected pattern
        if self.PATTERNS['lot_rejected'].search(line):
            self._funnel_stats['lot_rejected'] = self._funnel_stats.get('lot_rejected', 0) + 1
            return

        # V2: Market closed pattern
        if self.PATTERNS['market_closed'].search(line):
            self._funnel_stats['market_closed'] += 1
            return
        
        # V2: Order failure reason
        if match := self.PATTERNS['order_fail_reason'].search(line):
            reason = match.group(1).upper()
            if 'MAX_RETRIES' in reason:
                self._funnel_stats['order_fail_max_retries'] += 1
            return
        
        # V2: Deal track entry (capture for trade pairing)
        if match := self.PATTERNS['deal_track_entry'].search(line):
            guid = match.group(1)
            direction = match.group(2)
            price = float(match.group(3))
            self._pending_entries[guid] = {
                'direction': direction,
                'entry_price': price,
                'lineno': lineno
            }
            return
        
        # V2: Deal track exit (pair with entry for P/L)
        if match := self.PATTERNS['deal_track_exit'].search(line):
            guid = match.group(1)
            profit = float(match.group(2))
            hold_min = int(match.group(3))
            
            # Calculate round-trip trades
            if guid in self._pending_entries:
                entry = self._pending_entries.pop(guid)
                self._completed_trades.append({
                    'guid': guid,
                    'entry_price': entry['entry_price'],
                    'profit': profit,
                    'hold_min': hold_min
                })
                self._funnel_stats['trades_roundtrip'] += 1
                
                # Track wins/losses
                if profit > 0:
                    self._funnel_stats['trades_wins'] += 1
                else:
                    self._funnel_stats['trades_losses'] += 1
                
                self._funnel_stats['total_profit'] += profit
                
                # Calculate running average hold time
                old_avg = self._funnel_stats['avg_hold_time_min']
                n = self._funnel_stats['trades_roundtrip']
                self._funnel_stats['avg_hold_time_min'] = old_avg + (hold_min - old_avg) / n
            return
        
        # V2: Deal track summary (final stats per day)
        if match := self.PATTERNS['deal_track_summary'].search(line):
            self._funnel_stats['trades_tracked'] = int(match.group(3))
            return
        
        # Exit markers (3.3)
        for exit_key in ['exit_crt_target', 'exit_cisd_reversal', 'exit_dow_bos',
                         'exit_trail_stop', 'exit_sl_hit', 'exit_emergency_close']:
            if self.PATTERNS[exit_key].search(line):
                self._funnel_stats[exit_key] += 1
                return
        
        # Model-aligned markers
        for model_key in ['c1_poi_valid', 'c1_poi_miss', 'c3_fallback',
                           'trail_psl', 'trail_psh', 'c2_wick_filter', 'pyramid_add',
                           'c2_accepted', 'c2_locked', 'c2_lock_attempt', 'c2_lock_diag',
                           'c2_eval_attempt', 'c2_bar_detected', 'c2_closure_detected',
                           'c3_context', 'c3_runtime_disabled', 'c3_accepted', 'c3_reject', 'c3_bias_align_pass',
                           'c4_accepted', 'pipeline_kill',
                           'state_cleared', 'state_illegal', 'state_ghost_blocked', 'state_recovered',
                           'state_transition_ok', 'signal_corrupt', 'locked_signal_rejected',
                           'locked_signal_complete', 'commit_reject', 'structure_reject',
                           'entry_reject', 'entry_candidate_invalid', 'entry_candidate_set',
                           'context_expired', 'displacement_marker', 'sl_calc', 'floor_calc',
                           'sym_classified', 'guid_prealloc', 'guid_duplicate_blocked',
                           'br_resolve', 'fsm', 'stage_transition', 'signal_expired_enhanced',
                           'init_marker', 'signal_force_cleared', 'c3_lock_attempt',
                           'lock_call', 'sl_terminate']:
            if self.PATTERNS[model_key].search(line):
                self._funnel_stats[model_key] += 1
                return

        # V6: Full canonical markers from AGENTS.md §VIII
        for canonical_key in ['wick_rule_block', 'wick_rule_pass',
                               'cisd_failed', 'tspot_poi_mapped', 'tspot_poi_missing',
                               'time_filter_block', 'time_filter_pass',
                               'smt_divergence_pass', 'smt_divergence_fail',
                               'bias_aligned', 'bias_misaligned',
                               'htf_target_hit', 'reset_htf_target',
                               'risk_2r_violation', 'state_mutation',
                               'handover_timeout', 'handover_acquired',
                               'handover_transferred', 'handover_released',
                               'handover_forced_release', 'risk_floor_block',
                               'c3_demoted_to_c2', 'c4_blocked',
                               'stage_ready_protected']:
            if self.PATTERNS[canonical_key].search(line):
                self._funnel_stats[canonical_key] += 1
                return

        if match := self.PATTERNS['risk_profile_error'].search(line):
            self._handle_risk_profile_error(lineno, line, match)
            return
        
        # Mode detection
        if 'ANTICIPATION' in line:
            self._funnel_stats['anticipation_mode'] += 1
        if 'CONFIRMATION' in line:
            self._funnel_stats['confirmation_mode'] += 1
        
        # Branch detection
        if 'BRANCH=A' in line or 'BRANCH=0' in line:
            self._funnel_stats['branch_a'] += 1
        if 'BRANCH=B' in line or 'BRANCH=1' in line:
            self._funnel_stats['branch_b'] += 1
    
    def _handle_signal_committed(self, lineno: int, line: str, match: re.Match) -> None:
        guid = match.group(1)
        branch = match.group(2)
        slot = match.group(3)
        self._funnel_stats['signal_committed'] += 1
        if self._active_branch_for_stats in ["BRANCH_A", "BRANCH_0"]:
            self._funnel_stats['branch_a_signals'] += 1
        else:
            self._funnel_stats['branch_b_signals'] += 1
        self._unique_guids.add(int(guid))

    def _handle_signal_bridged(self, lineno: int, line: str, match: re.Match) -> None:
        guid = match.group(1)
        source = match.group(2)
        self._funnel_stats['signal_bridged'] += 1
        self._unique_guids.add(int(guid))

    def _handle_execution_entry(self, lineno: int, line: str, match: re.Match) -> None:
        guid = match.group(1)
        stage = match.group(2)
        is_committed = match.group(3).lower() == 'true'
        direction = match.group(4)
        self._funnel_stats['execution_entry'] += 1
        self._unique_guids.add(int(guid))

    def _handle_execution_trigger(self, lineno: int, line: str, match: re.Match) -> None:
        guid_str = match.group(1)
        is_fail = 'FAIL' in line.upper()
        if is_fail:
            self._funnel_stats['execution_trigger_fail'] += 1
        else:
            self._funnel_stats['execution_trigger'] += 1
        if guid_str:
            self._unique_guids.add(int(guid_str))

    def _handle_order_result(self, lineno: int, line: str, match: re.Match) -> None:
        result = match.group(1)
        detail = match.group(2) if match.lastindex >= 2 else ""
        self._funnel_stats['order_events'] += 1
        if 'INVALID' in result.upper():
            self._funnel_stats['order_invalid'] += 1

    def _handle_execution_event(self, lineno: int, line: str, match: re.Match) -> None:
        filling = match.group(1)
        symbol = match.group(2)
        self._funnel_stats['trade_executions'] += 1
        if self._active_branch_for_stats in ["BRANCH_A", "BRANCH_0"]:
            self._funnel_stats['branch_a_trades'] += 1
        else:
            self._funnel_stats['branch_b_trades'] += 1

    def _handle_signal_cleared(self, lineno: int, line: str, match: re.Match) -> None:
        guid = match.group(1)
        reason = match.group(2)
        self._funnel_stats['signal_cleared'] += 1
        self._unique_guids.add(int(guid))

    def _handle_lte_event(self, lineno: int, line: str, match: re.Match) -> None:
        prev_tier = match.group(1)
        curr_tier = match.group(2)
        self._funnel_stats['lte_events'] += 1

    def _handle_gate_override(self, lineno: int, line: str, match: re.Match) -> None:
        gate_action = match.group(1).upper()
        gate_detail = match.group(2)
        
        if gate_action == "D1_NEUTRAL":
            self._funnel_stats['bias_overrides'] += 1
            self._funnel_stats['struct_overrides_d1_neutral'] += 1
            self._bias_conflicts['STRUCT_OVERRIDES_D1_NEUTRAL'] += 1
    
    def _handle_confirmation_gate(self, lineno: int, line: str, match: re.Match) -> None:
        status = match.group(1).upper()
        detail = match.group(2)
        
        if status == "ACTIVE":
            self._funnel_stats['confirmation_gate_unlocks'] += 1
        else:
            self._funnel_stats['confirmation_gate_locks'] += 1
    
    def _handle_closure(self, lineno: int, line: str, match: re.Match) -> None:
        closure_char = match.group(1).upper()  # C2 or C3
        closure_type = match.group(3).upper()   # CLOSURE_C2, CLOSURE_C3, or CLOSURE_NONE
        direction = match.group(4).upper()    # BUY or SELL
        
        self._funnel_stats['closures'] += 1
        
        # Only count valid closures (CLOSURE_C2 or CLOSURE_C3) as pipeline entries
        if closure_type in ["CLOSURE_C2", "CLOSURE_C3"]:
            self._funnel_stats['pipeline_entries'] += 1
            if closure_char == "C2":
                self._funnel_stats['closure_c2_pass'] += 1
            else:
                self._funnel_stats['closure_c3_pass'] += 1
        
        if self._current_signal:
            self._current_signal.closure_type = closure_char
            self._current_signal.closure_result = closure_type
            self._current_signal.direction = direction
        
        self._recent_closures.append((
            lineno,
            closure_char,
            closure_type,
            direction
        ))
        self._last_closure_lineno = lineno
        
        if len(self._recent_closures) > 100:
            self._recent_closures = self._recent_closures[-100:]

    def _handle_closure_entry(self, lineno: int, line: str, match: re.Match) -> None:
        closure_type = match.group(1).upper()
        closure_result = match.group(2).upper()
        
        if closure_result == "PASS":
            self._funnel_stats['pipeline_entries'] += 1
            
            if closure_type == "C2":
                self._funnel_stats['c2_closures'] += 1
            else:
                self._funnel_stats['c3_closures'] += 1
    
    def _handle_signal_stored(self, lineno: int, line: str, match: re.Match) -> None:
        guid = match.group(1)
        branch = match.group(2)
        slot = match.group(3)
        self._funnel_stats['signal_stored'] += 1
        self._unique_guids.add(int(guid))

    def _handle_exec_skip(self, lineno: int, line: str, match: re.Match) -> None:
        lot = float(match.group(1))
        self._funnel_stats['exec_skip'] += 1

    def _handle_state_transition_ok(self, lineno: int, line: str, match: re.Match) -> None:
        guid = match.group(1)
        from_stage = match.group(2)
        to_stage = match.group(3)
        self._funnel_stats['state_transition_ok'] += 1
        self._unique_guids.add(int(guid))

    def _handle_d1_bias(self, lineno: int, line: str, match: re.Match) -> None:
        bias_str = match.group(1).upper()
        prev_close = match.group(2) if match.lastindex >= 2 else None
        prior_2low = match.group(3) if match.lastindex >= 3 else None
        
        if "BULLISH" in bias_str:
            self._funnel_stats['d1_bias_bullish'] += 1
        elif "BEARISH" in bias_str:
            self._funnel_stats['d1_bias_bearish'] += 1
        else:
            self._funnel_stats['d1_bias_neutral'] += 1
        
        if self._current_signal:
            if "BULLISH" in bias_str:
                self._current_signal.d1_bias = BiasType.BULLISH
            elif "BEARISH" in bias_str:
                self._current_signal.d1_bias = BiasType.BEARISH
            else:
                self._current_signal.d1_bias = BiasType.NEUTRAL
    
    def _handle_risk_profile_error(self, lineno: int, line: str, match: re.Match) -> None:
        derived_rr = float(match.group(1))
        self._funnel_stats['risk_profile_error'] += 1
        self._funnel_stats['rr_violated_zero'] = self._funnel_stats.get('rr_violated_zero', 0) + 1

    def _handle_state_advance(self, lineno: int, line: str, match: re.Match) -> None:
        signal_id = int(match.group(1))
        from_stage = match.group(2).strip()
        to_stage = match.group(3).strip()
        self._funnel_stats['state_advance'] += 1
        
        if to_stage == "STAGE_WAITING_FOR_POI":
            self._funnel_stats['stage_waiting_for_poi'] += 1
            if self._active_branch_for_stats == "BRANCH_A":
                self._funnel_stats['branch_a_stage_poi'] += 1
            else:
                self._funnel_stats['branch_b_stage_poi'] += 1
    
    def _handle_mode_prereq_block(self, lineno: int, line: str, match: re.Match) -> None:
        reason = match.group(1).strip()
        self._funnel_stats['mode_prereq_blocks'] += 1
        
        if "SSE=RANGE" in reason.upper():
            self._funnel_stats['sse_range_blocks'] += 1
    
    def _detect_execution_gaps(self) -> None:
        gap_reasons = {
            'D1=NEUTRAL': GapType.D1_NEUTRAL_LOCK,
            'FULL_NEUTRAL': GapType.D1_NEUTRAL_LOCK,
            'SSE=RANGE': GapType.SSE_RANGE,
            'Liquidity not ERL': GapType.LIQUIDITY_MISSING,
            'Spread': GapType.SPREAD_FAIL,
            'Volatility': GapType.VOLATILITY_FAIL,
        }
        
        for closure_rec in self._recent_closures:
            closure_lineno, closure_type, closure_result, direction = closure_rec
            
            if closure_result != "PASS":
                continue
            
            gap_type = GapType.UNKNOWN
            reason = "Unknown"
            
            lines_after = []
            for i in range(closure_lineno, min(closure_lineno + self.GAP_DETECTION_WINDOW, self._lines_processed)):
                lines_after.append(i)
            
            if lines_after:
                distance = closure_lineno - self._last_closure_lineno
                if distance < self.GAP_DETECTION_WINDOW:
                    exec_gap = ExecutionGap(
                        signal_id=closure_lineno,
                        gap_type=GapType.UNKNOWN,
                        closure_lineno=closure_lineno,
                        expected_exit_lineno=lines_after[-1] if lines_after else closure_lineno,
                        distance_lines=distance,
                        reason="No trade after closure"
                    )
                    self._execution_gaps.append(exec_gap)
                    self._funnel_stats['execution_gaps'] += 1
    
    def diagnose_pipeline_leak(self, log_lines: List[str], closure_lineno: int, signal_id: int) -> Dict[str, Any]:
        """
        Diagnose why a signal died between closure detection and execution.
        
        Logic: If closure == PASS AND 0 LIMIT_ORDER follows within LIMIT_LOOKAHEAD lines,
               find the last [MODE PREREQ] or [BE] entry.
        
        Output: Explicitly state: "Signal [ID] died at [PREREQ_GATE] due to [REASON]."
        """
        gap_type = GapType.UNKNOWN
        reason = "Unknown"
        prereq_gate = "UNKNOWN"
        
        lookback_start = max(0, closure_lineno - 50)
        lookback_lines = log_lines[lookback_start:closure_lineno]
        
        lookforward_end = min(len(log_lines), closure_lineno + self.LIMIT_LOOKAHEAD)
        lookforward_lines = log_lines[closure_lineno:lookforward_end]
        
        has_limit_order = any('LIMIT_ORDER' in line.upper() or 'RG_LIMIT' in line.upper() 
                              for line in lookforward_lines)
        
        if has_limit_order:
            return {
                'signal_id': signal_id,
                'status': 'LIMIT_PENDING',
                'prereq_gate': 'RG_LIMIT_PENDING',
                'reason': 'Signal awaiting C4 retracement — limit order active',
                'message': f"Signal [{signal_id}] is alive, awaiting C4 retracement — LIMIT_ORDER active"
            }
        
        prereq_blocks = [
            ('D1_NEUTRAL_STRUCT_NEUTRAL', 'FULL_NEUTRAL', 'D1 + Structure TF both NEUTRAL'),
            ('D1=NEUTRAL', 'D1_NEUTRAL', 'D1 bias is NEUTRAL'),
            ('SSE=RANGE', 'SSE_RANGE', 'HTF SSE is in RANGE consolidation'),
            ('Liquidity not ERL', 'LIQUIDITY_MISSING', 'No ERL liquidity tier detected'),
            ('Spread', 'SPREAD_FAIL', 'Spread exceeds maximum threshold'),
            ('No locked', 'NO_LOCKED_SIGNAL', 'No C2/C3 signal locked on entry TF'),
            ('No closure', 'NO_CLOSURE_TRIGGER', 'No valid closure trigger found'),
            ('SSE not TRANSITION', 'HTF_NOT_TRANSITION', 'HTF not in TRANSITION state for Anticipation'),
            ('SSE not TREND', 'HTF_NOT_TREND', 'HTF not TREND or TRANSITION for Confirmation'),
            ('C2 signal not at active stage', 'C2_STAGE_INVALID', 'C2 signal not at valid stage'),
            ('C3 signal not at POI/closure', 'C3_STAGE_INVALID', 'C3 signal not at POI/closure'),
            ('Stage=', 'MODE_PREREQ_STAGE', 'Signal stage not in valid list'),
        ]
        
        last_prereq_match = None
        for line in reversed(lookback_lines):
            line_upper = line.upper()
            for pattern, gate, desc in prereq_blocks:
                if pattern.upper() in line_upper:
                    last_prereq_match = (gate, desc, line.strip())
                    break
            if last_prereq_match:
                break
        
        if last_prereq_match:
            prereq_gate, reason, raw_line = last_prereq_match
            gap_type = GapType.D1_NEUTRAL_LOCK if 'NEUTRAL' in reason.upper() else GapType.UNKNOWN
            
            message = f"Signal [{signal_id}] died at [{prereq_gate}] due to [{reason}]"
            
            exec_gap = ExecutionGap(
                signal_id=signal_id,
                gap_type=gap_type,
                closure_lineno=closure_lineno,
                expected_exit_lineno=closure_lineno,
                distance_lines=0,
                reason=reason
            )
            self._execution_gaps.append(exec_gap)
            self._funnel_stats['execution_gaps'] += 1
            
            return {
                'signal_id': signal_id,
                'status': 'DEAD',
                'prereq_gate': prereq_gate,
                'reason': reason,
                'message': message,
                'raw_log_line': raw_line
            }
        
        return {
            'signal_id': signal_id,
            'status': 'UNKNOWN_GAP',
            'prereq_gate': 'UNKNOWN',
            'reason': 'No blocking condition found in lookback window',
            'message': f"Signal [{signal_id}] died at [UNKNOWN] due to [UNKNOWN_GAP]"
        }
    
    def _finalize_current_signal(self) -> None:
        if not self._current_signal:
            return
        
        signal = self._current_signal
        is_valid, error = signal.validate_branch()
        
        if not is_valid:
            signal.validation_error = error
        
        if signal.has_logic_leak():
            self._funnel_stats['trade_executions'] = max(0, self._funnel_stats['trade_executions'] - 1)
        
        self.signals[signal.signal_id] = signal
        self._current_signal = None
    
    def _finalize_signals(self) -> None:
        if self._current_signal:
            self._finalize_current_signal()
    
    def get_funnel_report(self) -> Dict[str, Any]:
        stats = self._funnel_stats
        
        funnel = {
            'total_lines': stats['total_lines'],
            'pipeline_entries': stats['pipeline_entries'],
            'branch_configs': stats['branch_configs'],
            'branch_evaluations': stats['branch_evaluations'],
            'branch_a_pass_rate': self._calc_rate(
                stats['branch_a_ok'],
                stats['branch_evaluations']
            ),
            'branch_a_signals': stats['branch_a_signals'],
            'branch_b_signals': stats['branch_b_signals'],
            'branch_a_stage_poi': stats['branch_a_stage_poi'],
            'branch_b_stage_poi': stats['branch_b_stage_poi'],
            'branch_a_rg_gate_pass': stats['branch_a_rg_gate_pass'],
            'branch_b_rg_gate_pass': stats['branch_b_rg_gate_pass'],
            'branch_a_exec_gate_pass': stats['branch_a_exec_gate_pass'],
            'branch_b_exec_gate_pass': stats['branch_b_exec_gate_pass'],
            'branch_a_trades': stats['branch_a_trades'],
            'branch_b_trades': stats['branch_b_trades'],
            'anticipation_unlocks': stats['anticipation_gate_unlocks'],
            'anticipation_locks': stats['anticipation_gate_locks'],
            'confirmation_unlocks': stats['confirmation_gate_unlocks'],
            'confirmation_locks': stats['confirmation_gate_locks'],
            'bias_overrides': stats['bias_overrides'],
            'closures': stats['closures'],
            'closure_c2_pass': stats['closure_c2_pass'],
            'closure_c3_pass': stats['closure_c3_pass'],
            'd1_bias_distribution': {
                'bullish': stats['d1_bias_bullish'],
                'bearish': stats['d1_bias_bearish'],
                'neutral': stats['d1_bias_neutral'],
            },
            'rg_gate_breakout': stats['rg_gate_breakout'],
            'rg_gate_retrace': stats['rg_gate_retrace'],
            'rg_limit_set': stats['rg_limit_set'],
            'rg_limit_expired': stats['rg_limit_expired'],
            'execution_gate_pass': stats['execution_gate_pass'],
            'exec_gate_fail': stats['exec_gate_fail'],
            'exec_gate_fail_breakdown': {
                'slot_master_blocked': stats.get('exec_gate_fail_slot_master_blocked', 0),
                'modal_upgrade_blocked': stats.get('exec_gate_fail_modal_upgrade_blocked', 0),
                'slot_c3_blocked': stats.get('exec_gate_fail_slot_c3_blocked', 0),
                'stage_not_ready': stats.get('exec_gate_fail_stage_not_ready', 0),
                'not_committed': stats.get('exec_gate_fail_not_committed', 0),
                'signal_expired': stats.get('exec_gate_fail_signal_expired', 0),
                'already_executed': stats.get('exec_gate_fail_already_executed', 0),
                'retry_cap_reached': stats.get('exec_gate_fail_retry_cap_reached', 0),
                'invalid_direction': stats.get('exec_gate_fail_invalid_direction', 0),
                'invalid_exec_mode': stats.get('exec_gate_fail_invalid_exec_mode', 0),
                'invalid_entry_price': stats.get('exec_gate_fail_invalid_entry_price', 0),
                'invalid_c2_levels': stats.get('exec_gate_fail_invalid_c2_levels', 0),
                'invalid_branch': stats.get('exec_gate_fail_invalid_branch', 0),
                'invalid_signal_state': stats.get('exec_gate_fail_invalid_signal_state', 0),
                'sl_direction_invalid': stats.get('exec_gate_fail_sl_direction_invalid', 0),
            },
            'stage_waiting_for_poi': stats['stage_waiting_for_poi'],
            'state_advances': stats['state_advance'],
            'execution_gaps': stats['execution_gaps'],
            'mode_prereq_blocks': stats['mode_prereq_blocks'],
            'sse_range_blocks': stats['sse_range_blocks'],
            'liquidity_blocks': stats['liquidity_blocks'],
            'trade_executions': stats['trade_executions'],
            'signal_unlocks': stats['signal_unlocks'],
            'signal_expirations': stats['signal_expirations'],
            'mode_decouples': stats['mode_decouples'],
'signal_wait': stats['signal_wait'],
             'rg_gate_pass': stats['rg_gate_pass'],
             'cisd_confirmed': stats['cisd_confirmed'],
             'ordercheck_rejects': stats['ordercheck_rejects'],
            'signal_locked': stats['signal_locked'],
            'unique_guid_count': len(self._unique_guids),
            
            # V2: Account Guard stats
            'account_guard_emergency': stats['account_guard_emergency'],
            'account_guard_daily_loss': stats['account_guard_daily_loss'],
            'account_guard_cooldown': stats['account_guard_cooldown'],
            'account_guard_peak_dd': stats['account_guard_peak_dd'],
            
            # V2: C2 rejection stats
            'c2_reject_total': stats['c2_reject_total'],
            
            # V2: Order failure stats
            'market_closed': stats['market_closed'],
            'order_fail_max_retries': stats['order_fail_max_retries'],
            
            # V2: Trade P/L stats
            'deals_total': stats['deals_total'],
            'deals_buy': stats['deals_buy'],
            'deals_sell': stats['deals_sell'],
            'trades_roundtrip': stats['trades_roundtrip'],
            'trades_tracked': stats['trades_tracked'],
            'trades_wins': stats['trades_wins'],
            'trades_losses': stats['trades_losses'],
            'trades_untracked_emergency': max(0, stats['deals_total'] // 2 - stats['trades_tracked']),
            'total_profit': stats['total_profit'],
            'avg_hold_time_min': round(stats['avg_hold_time_min'], 2),
            
            # Model-aligned markers
            'c1_poi_valid': stats['c1_poi_valid'],
            'c1_poi_miss': stats['c1_poi_miss'],
            'c3_fallback': stats['c3_fallback'],
            'trail_psl': stats['trail_psl'],
            'trail_psh': stats['trail_psh'],
            'c2_wick_filter': stats['c2_wick_filter'],
            'pyramid_add': stats['pyramid_add'],
            
            # Exit markers
            'exit_crt_target': stats['exit_crt_target'],
            'exit_cisd_reversal': stats['exit_cisd_reversal'],
            'exit_dow_bos': stats['exit_dow_bos'],
            'exit_trail_stop': stats['exit_trail_stop'],
            'exit_sl_hit': stats['exit_sl_hit'],
            'exit_emergency_close': stats['exit_emergency_close'],
        }
        
        return funnel
    
    def _calc_rate(self, numerator: int, denominator: int) -> float:
        if denominator == 0:
            return 0.0
        return round(numerator / denominator * 100, 1)
    
    def get_bias_conflict_report(self) -> Dict[str, int]:
        return dict(self._bias_conflicts)
    
    def get_gap_analysis(self) -> List[Dict[str, Any]]:
        return [
            {
                'signal_id': g.signal_id,
                'gap_type': g.gap_type.value,
                'closure_lineno': g.closure_lineno,
                'distance_lines': g.distance_lines,
                'reason': g.reason,
            }
            for g in self._execution_gaps
        ]
    
    def get_telemetry(self) -> Dict[str, Any]:
        stats = self._funnel_stats
        gaps = self._execution_gaps
        return {
            'version': TELEMETRY_VERSION,
            'total_lines': stats.get('total_lines', 0),
            'unique_guids': len(self._unique_guids),
            'pipeline_entries': stats.get('pipeline_entries', 0),
            'signals_finalized': sum(1 for s in self.signals.values() if s.signal_finalized),
            'signals_leaked': len(gaps),
            'trade_executions': stats.get('trade_executions', 0),
            'leak_rate_pct': (len(gaps) / max(1, stats.get('pipeline_entries', 1))) * 100,
            'conversion_rate_pct': (stats.get('trade_executions', 0) / max(1, stats.get('pipeline_entries', 1))) * 100,
        }

    def get_clinical_audit(self) -> Dict[str, Any]:
        funnel = self.get_funnel_report()
        conflicts = self.get_bias_conflict_report()
        gaps = self.get_gap_analysis()
        
        surgical_rec = self._generate_surgical_recommendation()
        
        return {
            'funnel': funnel,
            'bias_conflicts': conflicts,
            'execution_gaps': gaps,
            'surgical_recommendation': surgical_rec,
        }
    
    def _generate_surgical_recommendation(self) -> Dict[str, Any]:
        stats = self._funnel_stats
        
        blocks = stats['mode_prereq_blocks']
        sse_range = stats['sse_range_blocks']
        liquidity = stats['liquidity_blocks']
        
        primary_cause = "UNKNOWN"
        mql5_function = "Unknown"
        line_number = 0
        
        if blocks > 0:
            if sse_range > liquidity:
                primary_cause = "SSE_RANGE"
                mql5_function = "ValidateModePrerequisites"
                line_number = 266
            elif liquidity > 0:
                primary_cause = "LIQUIDITY_MISSING"
                mql5_function = "ValidateModePrerequisites"
                line_number = 382
            else:
                primary_cause = "D1_NEUTRAL_LOCK"
                mql5_function = "ValidateModePrerequisites"
                line_number = 284
        
        if stats['d1_bias_neutral'] > stats['d1_bias_bullish'] + stats['d1_bias_bearish']:
            severity = "CRITICAL"
        else:
            severity = "MODERATE"
        
        return {
            'primary_block_cause': primary_cause,
            'mql5_function': mql5_function,
            'line_number': line_number,
            'severity': severity,
            'recommendation': f"Review {mql5_function} at line {line_number} — check bias dependency"
        }


def run_forensic_analysis(filepath: str, output_format: str = 'markdown') -> str:
    engine = OmakForensicEngine(filepath)
    engine.analyze()
    
    audit = engine.get_clinical_audit()
    funnel = audit['funnel']
    conflicts = audit['bias_conflicts']
    gaps = audit['execution_gaps']
    surgical = audit['surgical_recommendation']
    
    if output_format == 'json':
        import json
        return json.dumps(audit, indent=2)
    
    telemetry = engine.get_telemetry()
    report = f"""# Omak FxYO Forensic Audit

[OMAK_TELEMETRY] version={telemetry['version']} lines={telemetry['total_lines']} guids={telemetry['unique_guids']} entries={telemetry['pipeline_entries']} signals={telemetry['signals_finalized']} leaks={telemetry['signals_leaked']} trades={telemetry['trade_executions']} leak_rate={telemetry['leak_rate_pct']:.1f}% conv_rate={telemetry['conversion_rate_pct']:.1f}%

## Execution Funnel

| Stage | Count | Rate |
|-------|------:|-----:|
| Total Log Lines | {funnel['total_lines']:,} | 100% |
| Pipeline Entries | {funnel['pipeline_entries']:,} | {funnel['pipeline_entries']/funnel['total_lines']*100:.1f}% |
| Branch CFGs | {funnel['branch_configs']:,} | — |
| Branch Evaluations | {funnel['branch_evaluations']:,} | — |
| Branch A Pass Rate | — | {funnel['branch_a_pass_rate']:.1f}% |
| Anticipation UNLOCK | {funnel['anticipation_unlocks']:,} | — |
| Anticipation LOCK | {funnel['anticipation_locks']:,} | — |
| Confirmation UNLOCK | {funnel['confirmation_unlocks']:,} | — |
| Confirmation LOCK | {funnel['confirmation_locks']:,} | — |
| Bias Overrides (D1 neutral) | {funnel['bias_overrides']:,} | — |
| Closures (C2/C3 PASS) | {funnel['closures']:,} | — |
| C2 PASS | {funnel['closure_c2_pass']:,} | — |
| C3 PASS | {funnel['closure_c3_pass']:,} | — |
| State Advances | {funnel['state_advances']:,} | — |
| Signal Unlocks | {funnel['signal_unlocks']:,} | — |
| Signal Expirations | {funnel['signal_expirations']:,} | — |
| Mode Decouples | {funnel['mode_decouples']:,} | — |
| RG Gate BREAKOUT Triggered | {funnel['rg_gate_breakout']:,} | — |
| RG Gate RETRACE Triggered | {funnel['rg_gate_retrace']:,} | — |
| CISD Confirmed | {funnel['cisd_confirmed']:,} | — |
| RG Limit Set (C4 Trap) | {funnel['rg_limit_set']:,} | — |
| RG Limit Expired | {funnel['rg_limit_expired']:,} | — |
| Execution Gate PASS | {funnel['execution_gate_pass']:,} | — |
| **Trade Executions** | **{funnel['trade_executions']:,}** | — |

## D1 Bias Distribution

| Bias | Count |
|------|------:|
| BULLISH | {funnel['d1_bias_distribution']['bullish']:,} |
| BEARISH | {funnel['d1_bias_distribution']['bearish']:,} |
| NEUTRAL | {funnel['d1_bias_distribution']['neutral']:,} |

## Bias Conflicts (Structural vs D1)

| Conflict Type | Count |
|---------------|------:|
"""
    
    for conflict_type, count in conflicts.items():
        report += f"| {conflict_type} | {count:,} |\n"
    
        report += f"""
## Execution Gate Failures

| Metric | Value |
|--------|------:|
| Total EXEC_GATE_FAIL | {funnel['exec_gate_fail']:,} |
"""

        exec_fail_bd = funnel['exec_gate_fail_breakdown']
        # Only show non-zero breakdowns
        nonzero = [(k, v) for k, v in exec_fail_bd.items() if v > 0]
        if nonzero:
            report += "| Failure Reason | Count |\n"
            report += "|---------------|------:|\n"
            for reason, count in sorted(nonzero, key=lambda x: x[1], reverse=True):
                label = reason.replace('_', ' ').title()
                report += f"| {label} | {count:,} |\n"
        report += "\n"

        report += f"""
## Execution Gaps

| Metric | Value |
|--------|------:|
| Total Gaps | {len(gaps):,} |
| MODE_PREREQ Blocks | {funnel['mode_prereq_blocks']:,} |
| SSE_RANGE Blocks | {funnel['sse_range_blocks']:,} |
| Liquidity Blocks | {funnel['liquidity_blocks']:,} |

## V2: Trade P/L Analysis

| Metric | Value |
|--------|------:|
| Total Deals (entries+exits) | {funnel['deals_total']:,} |
| Buy Deals | {funnel['deals_buy']:,} |
| Sell Deals | {funnel['deals_sell']:,} |
| Round-Trip Trades | {funnel['trades_roundtrip']:,} |
| Tracked Trades (with P/L) | {funnel['trades_tracked']:,} |
| Wins | {funnel['trades_wins']:,} |
| Losses | {funnel['trades_losses']:,} |
| Untracked (emergency close) | {funnel['trades_untracked_emergency']:,} |
| Win Rate | {funnel['trades_wins'] / max(1, funnel['trades_tracked']) * 100:.1f}% |
| Total P/L | {funnel['total_profit']:.2f} |
| Avg Hold Time (min) | {funnel['avg_hold_time_min']:.1f} |

## V2: Account Guard Impact

| Metric | Value |
|--------|------:|
| Emergency Closes | {funnel['account_guard_emergency']:,} |
| Daily Loss Triggers | {funnel['account_guard_daily_loss']:,} |
| Cooldown Events | {funnel['account_guard_cooldown']:,} |
| Peak Drawdown % | {funnel['account_guard_peak_dd']:.1f}% |

## V2: Signal Rejection Analysis

| Metric | Value |
|--------|------:|
| C2 Rejections | {funnel['c2_reject_total']:,} |
| C3 Closures (PASS) | {funnel['closure_c3_pass']:,} |
| Market Closed Errors | {funnel['market_closed']:,} |
| MAX_RETRIES Failures | {funnel['order_fail_max_retries']:,} |
| RISK_PROFILE_ERROR | {funnel.get('risk_profile_error', 0):,} |
| RR Violated (Zero) | {funnel.get('rr_violated_zero', 0):,} |
| EXEC_SKIP (Lot=0) | {funnel['exec_skip']:,} |

## V3: Exit Marker Distribution

| Exit Type | Count |
|-----------|------:|
| CRT Target | {funnel['exit_crt_target']:,} |
| CISD Reversal | {funnel['exit_cisd_reversal']:,} |
| Dow BOS | {funnel['exit_dow_bos']:,} |
| Trailing Stop | {funnel['exit_trail_stop']:,} |
| SL Hit | {funnel['exit_sl_hit']:,} |
| Emergency Close | {funnel['exit_emergency_close']:,} |

## Surgical Recommendation

| Item | Value |
|------|-------|
| Primary Block | {surgical['primary_block_cause']} |
| MQL5 Function | {surgical['mql5_function']} |
| Line Number | {surgical['line_number']} |
| Severity | {surgical['severity']} |
| Recommendation | {surgical['recommendation']} |

---
*Generated by OmakForensicEngine*
"""
    
    return report


if __name__ == "__main__":
    import sys
    import argparse
    
    parser = argparse.ArgumentParser(description="OmakFxYO Forensic Engine")
    parser.add_argument("--input", "-i", required=True, help="Input log file path")
    parser.add_argument("--output", "-o", help="Output decoded log file path (optional)")
    args = parser.parse_args()
    
    input_path = args.input
    
    # Auto-detect encoding and convert to UTF-8 if needed
    import io
    converted_lines = None
    
    # Try UTF-16 first (MT5 logs are often UTF-16)
    for enc in ['utf-16', 'utf-16-le', 'utf-16-be', 'utf-8', 'utf-8-sig']:
        try:
            with io.open(input_path, 'r', encoding=enc, errors='ignore') as f:
                converted_lines = f.readlines()
            print(f"[INFO] Detected encoding: {enc}")
            break
        except (UnicodeDecodeError, LookupError):
            continue
    
    if converted_lines is None:
        raise RuntimeError(f"Could not decode file: {input_path}")
    
    # Normalize line endings (UTF-16 has CRLF, convert to LF)
    normalized_lines = [line.replace('\r\n', '\n').replace('\r', '\n') for line in converted_lines]
    
    # Write decoded log if output specified
    if args.output:
        with io.open(args.output, 'w', encoding='utf-8', newline='') as f:
            f.writelines(normalized_lines)
        print(f"[INFO] Decoded log written to: {args.output}")
    
    # Create temp file for engine (it needs a file path)
    import tempfile
    import os
    
    # Write to temp file that will be cleaned up
    with tempfile.NamedTemporaryFile(mode='w', suffix='.log', delete=False, encoding='utf-8') as tmp:
        tmp.writelines(normalized_lines)
        tmp_path = tmp.name
    
    try:
        print(run_forensic_analysis(tmp_path))
    finally:
        os.unlink(tmp_path)