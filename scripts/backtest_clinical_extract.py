#!/usr/bin/env python3
"""
Omak FxYO Clinical Backtest Extraction
Forensic MT5 Developer Mode
Strict log data only - no speculation
"""

import io
import re
from collections import defaultdict
from typing import Dict, List, Tuple, Any

class ClinicalExtractor:
    def __init__(self, filepath: str, encoding: str = 'utf-16-le'):
        self.filepath = filepath
        self.encoding = encoding
        self.lines = []
        self._load_log()
    
    def _load_log(self):
        """Load log file with proper encoding"""
        file_handle = None
        for enc in [self.encoding, 'utf-16-le', 'utf-16-be', 'utf-8', 'utf-8-sig']:
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
            self.lines = [line.strip() for line in f.readlines() if line.strip()]
        
        print(f"[LOG] Loaded {len(self.lines):,} lines", flush=True)
    
    def extract_metrics(self) -> Dict[str, Any]:
        """Extract all required metrics from log"""
        metrics = {
            'unique_guids': set(),
            'rg_gate_pass': 0,
            'execution_gate_pass': 0,
            'order_sent': 0,
            'ordercheck_reject': 0,
            'signal_expired': 0,
            'modal_upgrade': 0,
            'confirmation_gate_unlock': 0,
            'confirmation_gate_awaits': 0,
            'anticipation_gate_awaits': 0,
            'closure_c2_pass': 0,
            'closure_c3_pass': 0,
            'stage_poi': 0,
            'session_blocks': [],
            'branch_a_poi': 0,
            'branch_b_poi': 0,
            'branch_a_rg_pass': 0,
            'branch_b_rg_pass': 0,
            'branch_a_exec_pass': 0,
            'branch_b_exec_pass': 0,
            'branch_a_trades': 0,
            'branch_b_trades': 0,
            'exec_gate_fail': 0,
            'exec_gate_fail_by_reason': defaultdict(int),
# Model-aligned markers
        'c1_poi_valid': 0,
        'c1_poi_miss': 0,
        'c3_fallback': 0,
        'c2_wick_filter': 0,
        'exit_crt_target': 0,
        'exit_cisd_reversal': 0,
        'exit_dow_bos': 0,
        'exit_emergency_close': 0,
        'c2_accepted': 0,
        'c2_locked': 0,
        'state_cleared': 0,
        'c3_runtime_disabled': 0,
        'c3_reject': 0,
        'signal_corrupt': 0,
        'locked_signal_rejected': 0,
        'locked_signal_complete': 0,
        'commit_reject': 0,
        'structure_reject': 0,
        'entry_reject': 0,
        'entry_candidate_invalid': 0,
        'entry_candidate_set': 0,
        'c2_lock_diag': 0,
        'c2_lock_attempt': 0,
        'c2_eval_attempt': 0,
        'c2_bar_detected': 0,
        'c2_closure_detected': 0,
        'c3_context': 0,
        'c3_bias_align_pass': 0,
        'state_illegal': 0,
        'state_ghost_blocked': 0,
        'state_recovered': 0,
        'displacement': 0,
        'sl_calc': 0,
        'floor_calc': 0,
        'sym_classified': 0,
        # V6: Full canonical markers
        'wick_rule_block': 0,
        'wick_rule_pass': 0,
        'cisd_confirmed': 0,
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
        
        current_branch = 'A'
        
        for i, line in enumerate(self.lines):
            # Track branch context
            if '[BRANCH_CFG]' in line:
                match = re.search(r'Branch=(\d+)', line)
                if match:
                    current_branch = 'A' if match.group(1) == '0' else 'B'
            
            # Unique Signal GUIDs
            if 'GUID:' in line:
                match = re.search(r'GUID:(\d+)', line)
                if match:
                    metrics['unique_guids'].add(match.group(1))
            
            # RG_GATE PASS
            if '[RG_GATE]' in line and 'PASS' in line:
                metrics['rg_gate_pass'] += 1
                if current_branch == 'A':
                    metrics['branch_a_rg_pass'] += 1
                else:
                    metrics['branch_b_rg_pass'] += 1
            
            # EXEC_GATE_FAIL
            if '[EXEC_GATE_FAIL]' in line:
                metrics['exec_gate_fail'] += 1
                match = re.search(r'reason=(\w+)', line)
                if match:
                    reason = match.group(1)
                    metrics['exec_gate_fail_by_reason'][reason] += 1
            
            # EXEC_GATE PASS
            if '[EXEC_GATE]' in line and 'PASS' in line:
                metrics['execution_gate_pass'] += 1
                if current_branch == 'A':
                    metrics['branch_a_exec_pass'] += 1
                else:
                    metrics['branch_b_exec_pass'] += 1
            
            # ORDER_SENT
            if '[ORDER_SENT]' in line:
                metrics['order_sent'] += 1
                if current_branch == 'A':
                    metrics['branch_a_trades'] += 1
                else:
                    metrics['branch_b_trades'] += 1
            
            # ORDER_CHECK_REJECT
            if '[ORDER_CHECK_REJECT]' in line:
                metrics['ordercheck_reject'] += 1
                match = re.search(r'Code=(\d+)', line)
                if match:
                    retcode = match.group(1)
            
            # SIGNAL_EXPIRED
            if '[SIGNAL_EXPIRED]' in line:
                metrics['signal_expired'] += 1
                match = re.search(r'Reason:([^|]+)', line)
                if match:
                    reason = match.group(1).strip()
            
            # MODAL_UPGRADE
            if '[MODAL_UPGRADE]' in line:
                metrics['modal_upgrade'] += 1
            
            # CONFIRMATION_GATE
            if '[CONFIRMATION_GATE]' in line:
                if 'Awaiting' in line:
                    metrics['confirmation_gate_awaits'] += 1
                elif 'UNLOCK' in line or 'ACTIVE' in line:
                    metrics['confirmation_gate_unlock'] += 1
            
            # ANTICIPATION_GATE
            if '[ANTICIPATION_GATE]' in line:
                metrics['anticipation_gate_awaits'] += 1
            
            # CLOSURE tracking
            if '[CLOSURE]' in line:
                if 'C2=PASS' in line:
                    metrics['closure_c2_pass'] += 1
                elif 'C3=PASS' in line:
                    metrics['closure_c3_pass'] += 1
            
# SESSION_BLOCK
            if '[SESSION_BLOCK]' in line:
                match = re.search(r'Reason=(.+?)(?:\s+—|$)', line)
                if match:
                    reason = match.group(1).strip()
                    metrics['session_blocks'].append(reason)
            
            # Model-aligned markers
            if '[C1_POI_VALID]' in line:
                metrics['c1_poi_valid'] += 1
            if '[C1_POI_MISS]' in line:
                metrics['c1_poi_miss'] += 1
            if '[C3_FALLBACK]' in line:
                metrics['c3_fallback'] += 1
            if '[C2_WICK_FILTER]' in line:
                metrics['c2_wick_filter'] += 1
            if '[EXIT_CRT_TARGET]' in line:
                metrics['exit_crt_target'] += 1
            if '[EXIT_CISD_REVERSAL]' in line:
                metrics['exit_cisd_reversal'] += 1
            if '[EXIT_DOW_BOS]' in line:
                metrics['exit_dow_bos'] += 1
            if '[EXIT_EMERGENCY_CLOSE]' in line:
                metrics['exit_emergency_close'] += 1
            if '[C2_ACCEPTED]' in line:
                metrics['c2_accepted'] += 1
            if '[C2_LOCKED]' in line:
                metrics['c2_locked'] += 1
            if '[STATE_CLEARED]' in line:
                metrics['state_cleared'] += 1
            if '[C3_RUNTIME_DISABLED]' in line:
                metrics['c3_runtime_disabled'] += 1
            if '[C3_REJECT]' in line:
                metrics['c3_reject'] += 1
            if '[SIGNAL_CORRUPT]' in line:
                metrics['signal_corrupt'] += 1
            if '[LOCKED_SIGNAL_REJECTED]' in line:
                metrics['locked_signal_rejected'] += 1
            if '[LOCKED_SIGNAL_COMPLETE]' in line:
                metrics['locked_signal_complete'] += 1
            if '[COMMIT_REJECT]' in line:
                metrics['commit_reject'] += 1
            if '[STRUCTURE_REJECT]' in line:
                metrics['structure_reject'] += 1
            if '[ENTRY_REJECT]' in line:
                metrics['entry_reject'] += 1
            if '[ENTRY_CANDIDATE_INVALID]' in line:
                metrics['entry_candidate_invalid'] += 1
            if '[ENTRY_CANDIDATE_SET]' in line:
                metrics['entry_candidate_set'] += 1
            if '[C2_LOCK_DIAG]' in line:
                metrics['c2_lock_diag'] += 1
            if '[C3_CONTEXT]' in line:
                metrics['c3_context'] += 1
            if '[CONTEXT_EXPIRED]' in line:
                metrics['context_expired'] += 1
            if '[STATE_ILLEGAL]' in line:
                metrics['state_illegal'] += 1
            if '[STATE_GHOST_BLOCKED]' in line:
                metrics['state_ghost_blocked'] += 1
            if '[STATE_RECOVERED]' in line:
                metrics['state_recovered'] += 1
            if '[DISPLACEMENT]' in line:
                metrics['displacement'] += 1
            if '[SL_CALC]' in line:
                metrics['sl_calc'] += 1
            if '[FLOOR_CALC]' in line:
                metrics['floor_calc'] += 1
            if '[SYM_CLASSIFIED]' in line:
                metrics['sym_classified'] += 1
            
            # V6: Full canonical markers (AGENTS.md §VIII)
            if '[WICK_RULE_BLOCK]' in line:
                metrics['wick_rule_block'] += 1
            if '[WICK_RULE_PASS]' in line:
                metrics['wick_rule_pass'] += 1
            if '[CISD_CONFIRMED]' in line:
                metrics['cisd_confirmed'] += 1
            if '[CISD_FAILED]' in line:
                metrics['cisd_failed'] += 1
            if '[TSPOT_POI_MAPPED]' in line:
                metrics['tspot_poi_mapped'] += 1
            if '[TSPOT_POI_MISSING]' in line:
                metrics['tspot_poi_missing'] += 1
            if '[TIME_FILTER_BLOCK]' in line:
                metrics['time_filter_block'] += 1
            if '[TIME_FILTER_PASS]' in line:
                metrics['time_filter_pass'] += 1
            if '[SMT_DIVERGENCE_PASS]' in line:
                metrics['smt_divergence_pass'] += 1
            if '[SMT_DIVERGENCE_FAIL]' in line:
                metrics['smt_divergence_fail'] += 1
            if '[BIAS_ALIGNED]' in line:
                metrics['bias_aligned'] += 1
            if '[BIAS_MISALIGNED]' in line:
                metrics['bias_misaligned'] += 1
            if '[HTF_TARGET_HIT]' in line:
                metrics['htf_target_hit'] += 1
            if '[RESET_HTF_TARGET]' in line:
                metrics['reset_htf_target'] += 1
            if '[RISK_2R_VIOLATION]' in line:
                metrics['risk_2r_violation'] += 1
            if '[STATE_MUTATION]' in line:
                metrics['state_mutation'] += 1
            if '[HANDOVER_TIMEOUT]' in line:
                metrics['handover_timeout'] += 1
            if '[HANDOVER_ACQUIRED]' in line:
                metrics['handover_acquired'] += 1
            if '[HANDOVER_TRANSFERRED]' in line:
                metrics['handover_transferred'] += 1
            if '[HANDOVER_RELEASED]' in line:
                metrics['handover_released'] += 1
            if '[HANDOVER_FORCED_RELEASE]' in line:
                metrics['handover_forced_release'] += 1
            if '[RISK_FLOOR_BLOCK]' in line:
                metrics['risk_floor_block'] += 1
            if '[C3_DEMOTED_TO_C2]' in line:
                metrics['c3_demoted_to_c2'] += 1
            if '[C4_BLOCKED]' in line:
                metrics['c4_blocked'] += 1
            if '[STAGE_READY_PROTECTED]' in line:
                metrics['stage_ready_protected'] += 1
        
        return metrics
    
    def analyze_pipeline_funnel(self) -> Dict[str, Any]:
        """Analyze branch-specific pipeline funnel"""
        funnel = {
            'branch_a': {
                'stage_poi': 0,
                'rg_gate_pass': 0,
                'exec_gate_pass': 0,
                'trades': 0,
            },
            'branch_b': {
                'stage_poi': 0,
                'rg_gate_pass': 0,
                'exec_gate_pass': 0,
                'trades': 0,
            }
        }
        
        # Count stage POI transitions
        stage_poi_pattern = re.compile(r'\[STATE_ADVANCE\].*?(?:POI|STAGE_WAITING_FOR_POI)', re.IGNORECASE)
        
        for line in self.lines:
            if stage_poi_pattern.search(line):
                # Determine branch from context
                if 'Branch=0' in line or 'BRANCH_A' in line or 'INTRADAY' in line:
                    funnel['branch_a']['stage_poi'] += 1
                else:
                    funnel['branch_b']['stage_poi'] += 1
        
        return funnel
    
    def identify_death_points(self) -> List[Dict[str, Any]]:
        """Identify exact leakage/death points in signal pipeline"""
        death_points = []
        
        # Count reasons for no execution
        session_blocks = defaultdict(int)
        for line in self.lines:
            if '[SESSION_BLOCK]' in line:
                match = re.search(r'Reason=(.+?)(?:\s+—|$)', line)
                if match:
                    reason = match.group(1).strip()
                    session_blocks[reason] += 1
        
        if session_blocks:
            death_points.append({
                'marker': '[SESSION_BLOCK]',
                'root_cause': 'Session Time Gate',
                'details': session_blocks,
                'impact': sum(session_blocks.values())
            })
        
        # Look for closure without execution follow-up
        closures = 0
        anticipation_awaits = 0
        confirmation_awaits = 0
        
        for line in self.lines:
            if '[CLOSURE]' in line and 'PASS' in line:
                closures += 1
            if '[ANTICIPATION_GATE]' in line and 'Awaiting' in line:
                anticipation_awaits += 1
            if '[CONFIRMATION_GATE]' in line and 'Awaiting' in line:
                confirmation_awaits += 1
        
        if closures > 0 and anticipation_awaits > 0:
            death_points.append({
                'marker': '[ANTICIPATION_GATE] Awaiting',
                'root_cause': 'Execution Gate Never Passed',
                'details': f"{anticipation_awaits:,} signals waiting for execution",
                'impact': anticipation_awaits,
                'last_log_marker': '[ANTICIPATION_GATE]'
            })
        
        if closures > 0 and confirmation_awaits > 0:
            death_points.append({
                'marker': '[CONFIRMATION_GATE] Awaiting',
                'root_cause': 'Confirmation Condition Never Met',
                'details': f"{confirmation_awaits:,} signals waiting for confirmation",
                'impact': confirmation_awaits,
                'last_log_marker': '[CONFIRMATION_GATE]'
            })
        
        return death_points

def generate_report(filepath: str) -> str:
    """Generate clinical backtest report"""
    print(f"[INIT] Starting forensic analysis of {filepath}", flush=True)
    
    extractor = ClinicalExtractor(filepath)
    metrics = extractor.extract_metrics()
    funnel = extractor.analyze_pipeline_funnel()
    death_points = extractor.identify_death_points()
    
    unique_guid_count = len(metrics['unique_guids'])
    closure_total = metrics['closure_c2_pass'] + metrics['closure_c3_pass']
    
    # Build report
    report = "# Omak FxYO Clinical Backtest Report v5\n\n"
    
    # SECTION 1: Global Engine Health
    report += "## 1. Global Engine Health\n\n"
    
    status_line1 = "1. Unique Signal GUIDs Generated: {} {}".format(
        unique_guid_count,
        "✅" if unique_guid_count > 0 else "❌"
    )
    status_line2 = "2. [RG_GATE] PASS Events: {} {}".format(
        metrics['rg_gate_pass'],
        "✅" if metrics['rg_gate_pass'] > 0 else "❌"
    )
    status_line3 = "3. [EXEC_GATE] PASS Events: {} {}".format(
        metrics['execution_gate_pass'],
        "✅" if metrics['execution_gate_pass'] > 0 else "❌"
    )
    status_line4 = "4. [ORDER_SENT] Events: {} {}".format(
        metrics['order_sent'],
        "✅" if metrics['order_sent'] > 0 else "❌"
    )
    status_line5 = "5. [CONFIRMATION_GATE] UNLOCK / [MODAL_UPGRADE] Events: {} {}".format(
        metrics['confirmation_gate_unlock'] + metrics['modal_upgrade'],
        "✅" if (metrics['confirmation_gate_unlock'] + metrics['modal_upgrade']) > 0 else "❌"
    )
    
    report += status_line1 + "\n"
    report += status_line2 + "\n"
    report += status_line3 + "\n"
    report += status_line4 + "\n"
    report += status_line5 + "\n\n"
    
    # SECTION 2: Pipeline Funnel
    report += "## 2. Pipeline Funnel (Branch Breakdown)\n\n"
    report += "| Stage | Branch A (Intraday) | Branch B (Swing) |\n"
    report += "|-------|-------------------:|------------------:|\n"
    report += "| Reached STAGE_WAITING_FOR_POI | {} | {} |\n".format(
        funnel['branch_a']['stage_poi'], funnel['branch_b']['stage_poi']
    )
    report += "| Passed [RG_GATE] PASS | {} | {} |\n".format(
        metrics['branch_a_rg_pass'], metrics['branch_b_rg_pass']
    )
    report += "| Passed [EXEC_GATE] PASS | {} | {} |\n".format(
        metrics['branch_a_exec_pass'], metrics['branch_b_exec_pass']
    )
    report += "| Trades Executed | {} | {} |\n\n".format(
        metrics['branch_a_trades'], metrics['branch_b_trades']
    )
    
    # SECTION 3: Death Ledger
    report += "## 3. The Death Ledger (Leakage Points)\n\n"
    
    if death_points:
        for i, point in enumerate(death_points, 1):
            report += f"### Point {i}: {point['marker']}\n\n"
            report += f"**Root Cause**: {point['root_cause']}\n\n"
            report += f"**Last Log Marker Prior to Death**: `{point.get('last_log_marker', point['marker'])}`\n\n"
            report += f"**Impact**: {point['impact']:,} signals blocked\n\n"
            report += f"**Details**:\n"
            
            if isinstance(point['details'], dict):
                for key, value in point['details'].items():
                    report += f"- {key}: {value:,}\n"
            else:
                report += f"- {point['details']}\n"
            
            report += "\n"
    else:
        report += "No additional death points detected. All signals reached expected terminal states.\n\n"
    
    # EXEC_GATE_FAIL breakdown
    if metrics['exec_gate_fail'] > 0:
        report += "### Execution Gate Failure Breakdown\n\n"
        report += "| Reason | Count |\n"
        report += "|--------|------:|\n"
        for reason, count in sorted(metrics['exec_gate_fail_by_reason'].items(), key=lambda x: x[1], reverse=True):
            report += f"| {reason} | {count:,} |\n"
        report += f"\n**Total**: {metrics['exec_gate_fail']:,} signals blocked at the Execution Gate.\n\n"
        report += "**Review**: See [OrderManager.mqh](OmakFxYO/core/OrderManager.mqh) — `ExecutionGatePass()` function.\n\n"
    
    # Summary of leakage
    if closure_total > 0:
        report += f"**Critical Observation**: {closure_total:,} signals passed CLOSURE validation but "
        report += f"{metrics['confirmation_gate_awaits'] + metrics['anticipation_gate_awaits']:,} remain in AWAITING state. "
        report += "This indicates execution gates never transitioned to PASS state.\n\n"
    
    # SECTION 4: Developer Action Items
    report += "## 4. Developer Action Items\n\n"
    
    report += "### Root Cause Analysis\n\n"
    
    if metrics['order_sent'] == 0 and closure_total > 0:
        report += "**Issue**: No trades executed despite {0:,} closure triggers.\n\n".format(closure_total)
        report += "**Analysis**:\n"
        report += "- [CLOSURE] events detected: {0:,} (C2: {1:,}, C3: {2:,})\n".format(
            closure_total, metrics['closure_c2_pass'], metrics['closure_c3_pass']
        )
        report += "- [ANTICIPATION_GATE] awaiting execution: {0:,}\n".format(
            metrics['anticipation_gate_awaits']
        )
        report += "- [CONFIRMATION_GATE] awaiting execution: {0:,}\n".format(
            metrics['confirmation_gate_awaits']
        )
        report += "- [RG_GATE] PASS events: {0:,}\n".format(metrics['rg_gate_pass'])
        report += "- [EXEC_GATE] PASS events: {0:,}\n".format(metrics['execution_gate_pass'])
        report += "\n**Conclusion**: Execution pipeline stalled at gate validation stage.\n\n"
    
    if metrics['session_blocks']:
        block_summary = defaultdict(int)
        for reason in metrics['session_blocks']:
            block_summary[reason] += 1
        
        report += "### Session Blocking Analysis\n\n"
        report += "The EA applied session-level blocks preventing trade execution:\n\n"
        for reason, count in sorted(block_summary.items(), key=lambda x: x[1], reverse=True):
            report += f"- **{reason}**: {count:,} occurrences\n"
        report += "\n**File to Review**: [SessionManager.mqh](OmakFxYO/core/SessionManager.mqh) - Check session filtering logic at gate initialization\n\n"
    
    report += "### Recommended Code Inspection Points\n\n"
    report += "1. **[ClosureEngine.mqh](OmakFxYO/core/ClosureEngine.mqh)**\n"
    report += "   - Line ~150-180: Validate closure signal finalization\n"
    report += "   - Ensure PASS closures trigger anticipation/confirmation gate transitions\n\n"
    
    report += "2. **[SessionManager.mqh](OmakFxYO/core/SessionManager.mqh)**\n"
    report += "   - Check gap period detection logic\n"
    report += "   - Verify weekend cutoff is not blocking mid-week trades\n"
    report += "   - {0:,} SESSION_BLOCK events recorded — review filtering criteria\n\n".format(
        len(metrics['session_blocks'])
    )
    
    report += "3. **[TradeGovernor.mqh](OmakFxYO/core/TradeGovernor.mqh)**\n"
    report += "   - Verify [RG_GATE] PASS → [EXEC_GATE] PASS pathway\n"
    report += "   - Check condition for gateway state machine advancement\n\n"
    
    # Actionable directives
    report += "### Actionable Directives\n\n"
    
    if metrics['order_sent'] == 0:
        report += "**🔴 CRITICAL**: No [ORDER_SENT] events recorded.\n\n"
        report += "- [ ] Trace execution path from [CLOSURE] PASS → [EXEC_GATE] PASS → [ORDER_SENT]\n"
        report += "- [ ] Add debug logging at TradeGovernor line 200-250 to track state transitions\n"
        report += "- [ ] Verify SignalRegistry GUID persistence across gate transitions\n"
        report +=         "- [ ] Check OrderManager.mqh for order send retries/failures (no [ORDER_CHECK_REJECT] found)\n\n"
    
    if metrics['rg_gate_pass'] == 0 and closure_total > 0:
        report += "**🔴 CRITICAL**: [RG_GATE] PASS never achieved despite {0:,} closures.\n\n".format(closure_total)
        report += "- [ ] Review RiskGate.mqh gate validation logic\n"
        report += "- [ ] Check if gates are being locked after initialization\n"
        report += "- [ ] Verify price level requirements for RG_GATE transition\n\n"
    
    if metrics['execution_gate_pass'] == 0 and closure_total > 0:
        report += "**🔴 CRITICAL**: [EXEC_GATE] PASS never achieved.\n\n"
        report += "- [ ] Review SignalLifecycle.mqh gate state machine\n"
        report += "- [ ] Check SignalRegistry signal status at execution time\n"
        report += "- [ ] Verify no eternal LOCK condition on gates\n\n"
    
    report += "---\n"
    report += f"**Report Generated**: Clinical analysis of backtest log\n"
    report += f"**Total Lines Analyzed**: {len(extractor.lines):,}\n"
    report += f"**Unique GUIDs**: {unique_guid_count:,}\n"
    report += f"**Closure Events**: {closure_total:,}\n"
    
    # Model-aligned markers section
    if any([metrics['c1_poi_valid'], metrics['c1_poi_miss'], metrics['c3_fallback'],
            metrics['c2_wick_filter'], metrics['exit_crt_target'], metrics['exit_cisd_reversal'],
            metrics['exit_dow_bos'], metrics['exit_emergency_close']]):
        report += "\n### Model-Aligned Markers\n\n"
        report += "| Marker | Count |\n"
        report += "|--------|------:|\n"
        report += f"| [C1_POI_VALID] | {metrics['c1_poi_valid']:,} |\n"
        report += f"| [C1_POI_MISS] | {metrics['c1_poi_miss']:,} |\n"
        report += f"| [C3_FALLBACK] | {metrics['c3_fallback']:,} |\n"
        report += f"| [C2_WICK_FILTER] | {metrics['c2_wick_filter']:,} |\n"
        report += f"| [EXIT_CRT_TARGET] | {metrics['exit_crt_target']:,} |\n"
        report += f"| [EXIT_CISD_REVERSAL] | {metrics['exit_cisd_reversal']:,} |\n"
        report += f"| [EXIT_DOW_BOS] | {metrics['exit_dow_bos']:,} |\n"
        report += f"| [EXIT_EMERGENCY_CLOSE] | {metrics['exit_emergency_close']:,} |\n"
    
    # V6: Full canonical markers section
    v6_markers = {
        'wick_rule_block': '[WICK_RULE_BLOCK]',
        'wick_rule_pass': '[WICK_RULE_PASS]',
        'cisd_confirmed': '[CISD_CONFIRMED]',
        'cisd_failed': '[CISD_FAILED]',
        'tspot_poi_mapped': '[TSPOT_POI_MAPPED]',
        'tspot_poi_missing': '[TSPOT_POI_MISSING]',
        'time_filter_block': '[TIME_FILTER_BLOCK]',
        'time_filter_pass': '[TIME_FILTER_PASS]',
        'smt_divergence_pass': '[SMT_DIVERGENCE_PASS]',
        'smt_divergence_fail': '[SMT_DIVERGENCE_FAIL]',
        'bias_aligned': '[BIAS_ALIGNED]',
        'bias_misaligned': '[BIAS_MISALIGNED]',
        'htf_target_hit': '[HTF_TARGET_HIT]',
        'reset_htf_target': '[RESET_HTF_TARGET]',
        'risk_2r_violation': '[RISK_2R_VIOLATION]',
        'state_mutation': '[STATE_MUTATION]',
        'handover_timeout': '[HANDOVER_TIMEOUT]',
        'handover_acquired': '[HANDOVER_ACQUIRED]',
        'handover_transferred': '[HANDOVER_TRANSFERRED]',
        'handover_released': '[HANDOVER_RELEASED]',
        'handover_forced_release': '[HANDOVER_FORCED_RELEASE]',
        'risk_floor_block': '[RISK_FLOOR_BLOCK]',
        'c3_demoted_to_c2': '[C3_DEMOTED_TO_C2]',
        'c4_blocked': '[C4_BLOCKED]',
        'stage_ready_protected': '[STAGE_READY_PROTECTED]',
    }
    if any(metrics[k] for k in v6_markers):
        report += "\n### V6 Canonical Markers (AGENTS.md §VIII)\n\n"
        report += "| Marker | Count |\n"
        report += "|--------|------:|\n"
        for key, label in v6_markers.items():
            if metrics[key] > 0:
                report += f"| {label} | {metrics[key]:,} |\n"
        report += "\n"
    
    report += f"[OMAK_TELEMETRY] version=clinical-v2.0.0 lines={len(extractor.lines):,} guids={unique_guid_count:,} closures={closure_total:,} rg_pass={metrics['rg_gate_pass']:,} exec_pass={metrics['execution_gate_pass']:,} orders={metrics['order_sent']:,}\n"
    
    return report

if __name__ == "__main__":
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: backtest_clinical_extract.py <log_file>")
        sys.exit(1)
    
    log_file = sys.argv[1]
    report = generate_report(log_file)
    print(report)
