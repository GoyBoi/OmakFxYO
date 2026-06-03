#!/usr/bin/env python3
"""
Omak FxYO CLI - Single Entry Point
==================================
Usage:
    python omak_cli.py analyze <logfile>
    python omak_cli.py analyze <logfile> --clinical
    python omak_cli.py bias-conflict <logfile>

Commands:
    analyze          Full forensic analysis (use --clinical for leak-focused output)
    bias-conflict    Show bias conflict analysis

Flags:
    --clinical       Transition Failure Analysis only (skip general stats)
    --json           JSON output
    --sample N       Limit lines processed
"""

import os
import sys
import json
import argparse
from pathlib import Path
from typing import Optional, Dict, Any

script_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, script_dir)

from omak_forensic_engine import (
    OmakForensicEngine,
    run_forensic_analysis,
    SignalEvent,
    ExecutionGap,
    GapType,
    TELEMETRY_VERSION,
)


class OmakCLI:
    """Canonical CLI for Omak FxYO log analysis."""

    def __init__(self):
        self.parser = self._create_parser()
        self._output: Optional[str] = None

    def _create_parser(self) -> argparse.ArgumentParser:
        parser = argparse.ArgumentParser(
            prog='omak',
            description='Omak FxYO Forensic Analysis System',
            formatter_class=argparse.RawDescriptionHelpFormatter,
            epilog="""
Examples:
  python omak_cli.py analyze 20260425.log
  python omak_cli.py analyze 20260425.log --clinical
  python omak_cli.py analyze 20260425.log --clinical --json
  python omak_cli.py bias-conflict 20260425.log
            """
        )

        subparsers = parser.add_subparsers(dest='command', help='Available commands')

        analyze_parser = subparsers.add_parser('analyze', help='Full forensic analysis')
        analyze_parser.add_argument('logfile', help='Path to log file')
        analyze_parser.add_argument('--json', action='store_true', help='JSON output')
        analyze_parser.add_argument('--output', '-o', metavar='PATH', help='Output path')
        analyze_parser.add_argument(
            '--clinical', action='store_true',
            help='Transition Failure Analysis only (skip general stats)'
        )

        bias_parser = subparsers.add_parser('bias-conflict', help='Bias conflict analysis')
        bias_parser.add_argument('logfile', help='Path to log file')

        return parser

    def run(self, args: list = None) -> int:
        parsed = self.parser.parse_args(args)

        if not parsed.command:
            self.parser.print_help()
            return 0

        logfile = parsed.logfile

        if not os.path.exists(logfile):
            print(f"Error: File not found: {logfile}", file=sys.stderr)
            return 1

        if parsed.command == 'analyze':
            self._cmd_analyze(logfile, parsed)
        elif parsed.command == 'bias-conflict':
            self._cmd_bias_conflict(logfile, parsed)

        return 0

    def _cmd_analyze(self, logfile: str, parsed) -> None:
        clinical = getattr(parsed, 'clinical', False)
        engine = OmakForensicEngine(logfile)

        engine.analyze(run_leak_diagnosis=True)

        output = getattr(parsed, 'output', None)
        if clinical:
            self._print_clinical_report(engine, output)
            return

        report = engine.get_clinical_audit()

        if getattr(parsed, 'json', False):
            print(json.dumps(report, indent=2))
            return

        if output:
            with open(output, 'w') as f:
                f.write(run_forensic_analysis(logfile))
            print(f"Report written to: {output}")
        else:
            print(run_forensic_analysis(logfile))

    def _print_clinical_report(self, engine: OmakForensicEngine, output: Optional[str] = None) -> None:
        """
        Print Transition Failure Analysis only.
        Skips general stats. Outputs summary table: Signals vs Leaked vs Trades.
        """
        stats = engine._funnel_stats
        conflicts = engine.get_bias_conflict_report()
        gaps = engine.get_gap_analysis()

        signals_captured = stats.get('pipeline_entries', 0)
        signals_leaked = len(gaps)
        trades_placed = stats.get('trade_executions', 0)
        bias_overrides = stats.get('bias_overrides', 0)

        telemetry = engine.get_telemetry()
        print(f"[OMAK_TELEMETRY] {TELEMETRY_VERSION} "
              f"lines={telemetry['total_lines']} "
              f"entries={telemetry['pipeline_entries']} "
              f"signals={telemetry['signals_finalized']} "
              f"leaks={telemetry['signals_leaked']} "
              f"trades={telemetry['trade_executions']} "
              f"leak_rate={telemetry['leak_rate_pct']:.1f}% "
              f"conv_rate={telemetry['conversion_rate_pct']:.1f}%\n")
        print("# Omak FxYO — Transition Failure Analysis\n")
        print("## Signal Lifecycle Summary\n")
        print("| Metric | Count |")
        print("|--------|------:|")
        print(f"| Signals Captured | {signals_captured:,} |")
        print(f"| Signals Leaked | {signals_leaked:,} |")
        print(f"| Trades Placed | {trades_placed:,} |")
        print(f"| Bias Overrides (D1 bypass) | {bias_overrides:,} |")

        conversion_rate = 0.0
        leak_rate = 0.0
        if signals_captured > 0:
            conversion_rate = (trades_placed / signals_captured) * 100
            leak_rate = (signals_leaked / signals_captured) * 100

        print(f"| Conversion Rate | {conversion_rate:.1f}% |")
        print(f"| Leak Rate | {leak_rate:.1f}% |\n")
        
        signal_unlocks = stats.get('signal_unlocks', 0)
        signal_expirations = stats.get('signal_expirations', 0)
        mode_prereq_blocks = stats.get('mode_prereq_blocks', 0)
        
        print("## Signal Lifecycle Events\n")
        print("| Event | Count |")
        print("|-------|------:|")
        print(f"| Signal Unlocks | {signal_unlocks:,} |")
        print(f"| Signal Expirations | {signal_expirations:,} |")
        print(f"| MODE PREREQ Blocks | {mode_prereq_blocks:,} |\n")
        
        print("## Leak Breakdown\n")
        if gaps:
            print("| Signal ID | Gate | Reason |")
            print("|-----------|------|--------|")
            for gap in gaps[:50]:
                print(f"| {gap['signal_id']} | {gap['gap_type']} | {gap['reason']} |")
        else:
            print("| _No leaks detected_ | — | — |\n")

        print("## Bias Conflicts\n")
        if conflicts:
            print("| Type | Count |")
            print("|------|------:|")
            for conflict_type, count in conflicts.items():
                print(f"| {conflict_type} | {count:,} |")
        else:
            print("| _No conflicts_ | — |\n")

        if bias_overrides > 0:
            print("## D1 Neutral Override Events\n")
            print(f"**{bias_overrides:,} signals** proceeded on Structure TF bias despite D1 neutrality.")
            print("This is expected behavior per the Hierarchy of Truth (Strike 1).\n")

        output = getattr(self, '_output', None)
        if output:
            with open(output, 'w') as f:
                f.write(self._build_clinical_string(engine))
            print(f"Clinical report written to: {output}")

    def _build_clinical_string(self, engine: OmakForensicEngine) -> str:
        stats = engine._funnel_stats
        signals_captured = stats.get('pipeline_entries', 0)
        signals_leaked = len(engine.get_gap_analysis())
        trades_placed = stats.get('trade_executions', 0)
        bias_overrides = stats.get('bias_overrides', 0)

        lines = ["# Omak FxYO — Transition Failure Analysis\n"]
        lines.append("## Signal Lifecycle Summary\n")
        lines.append("| Metric | Count |")
        lines.append("|--------|------:|")
        lines.append(f"| Signals Captured | {signals_captured:,} |")
        lines.append(f"| Signals Leaked | {signals_leaked:,} |")
        lines.append(f"| Trades Placed | {trades_placed:,} |")
        lines.append(f"| Bias Overrides (D1 bypass) | {bias_overrides:,} |\n")
        return "\n".join(lines)

    def _cmd_bias_conflict(self, logfile: str, parsed) -> None:
        engine = OmakForensicEngine(logfile)
        engine.analyze()

        conflicts = engine.get_bias_conflict_report()

        print("# Bias Conflict Analysis\n")
        print("| Type | Count |")
        print("|------|------:|")
        for conflict_type, count in conflicts.items():
            print(f"| {conflict_type} | {count:,} |")


def main() -> int:
    cli = OmakCLI()
    return cli.run(sys.argv[1:])


if __name__ == "__main__":
    sys.exit(main())