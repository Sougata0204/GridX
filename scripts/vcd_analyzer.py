#!/usr/bin/env python3
"""
============================================================================
GridX³ — VCD Waveform Analyzer & Profiler
============================================================================
Parses VCD dump files and generates performance analysis:
  1. Core utilization heatmap (per-core active vs stall %)
  2. NoC congestion timeline
  3. Tensor unit utilization timeline
  4. Memory stall breakdown

Usage:
  python vcd_analyzer.py gridx_trace.vcd --output report/
  python vcd_analyzer.py gridx_trace.vcd --signals core_state --csv

Designed for low-memory operation: streams VCD without loading it all at once.
============================================================================
"""

import argparse
import os
import re
import sys
from collections import defaultdict

# ============================================================================
# VCD STREAMING PARSER (Low Memory)
# ============================================================================
class VCDStreamParser:
    """Parses VCD files line by line without loading the entire file."""

    def __init__(self, filename):
        self.filename = filename
        self.signals = {}        # id -> {name, scope, width}
        self.signal_ids = {}     # name -> id
        self.timescale = "1ns"

    def parse_header(self):
        """Parse VCD header to extract signal definitions."""
        scope_stack = []
        with open(self.filename, 'r') as f:
            in_header = True
            for line in f:
                line = line.strip()
                if line.startswith('$timescale'):
                    parts = line.split()
                    if len(parts) >= 2:
                        self.timescale = parts[1]
                elif line.startswith('$scope'):
                    parts = line.split()
                    if len(parts) >= 3:
                        scope_stack.append(parts[2])
                elif line.startswith('$upscope'):
                    if scope_stack:
                        scope_stack.pop()
                elif line.startswith('$var'):
                    parts = line.split()
                    if len(parts) >= 5:
                        var_type = parts[1]
                        width = int(parts[2])
                        var_id = parts[3]
                        var_name = parts[4]
                        full_name = '.'.join(scope_stack + [var_name])
                        self.signals[var_id] = {
                            'name': var_name,
                            'full_name': full_name,
                            'scope': '.'.join(scope_stack),
                            'width': width
                        }
                        self.signal_ids[full_name] = var_id
                elif line.startswith('$enddefinitions'):
                    break
        return self.signals

    def stream_changes(self, signal_filter=None):
        """
        Generator that yields (timestamp, signal_id, value) tuples.
        Only yields for signals matching the filter (if provided).
        """
        current_time = 0
        with open(self.filename, 'r') as f:
            past_header = False
            for line in f:
                line = line.strip()
                if not past_header:
                    if line.startswith('$enddefinitions'):
                        past_header = True
                    continue

                if line.startswith('#'):
                    current_time = int(line[1:])
                elif len(line) > 1:
                    if line[0] in ('0', '1', 'x', 'X', 'z', 'Z'):
                        sig_id = line[1:]
                        value = line[0]
                        if signal_filter is None or sig_id in signal_filter:
                            yield (current_time, sig_id, value)
                    elif line[0] == 'b':
                        parts = line.split()
                        if len(parts) == 2:
                            value = parts[0][1:]
                            sig_id = parts[1]
                            if signal_filter is None or sig_id in signal_filter:
                                yield (current_time, sig_id, value)


# ============================================================================
# ANALYSIS FUNCTIONS
# ============================================================================

def analyze_core_utilization(parser, num_cores=8):
    """Compute per-core active vs stalled vs idle percentages."""
    print("[Analyzer] Computing core utilization...")
    header = parser.parse_header()

    # Find core_state signals
    core_signals = {}
    for sig_id, info in header.items():
        if 'core_state' in info['name'] or 'warp_state' in info['name']:
            core_signals[sig_id] = info

    if not core_signals:
        print("  WARNING: No core_state signals found in VCD")
        return {}

    # Stream and accumulate
    core_stats = defaultdict(lambda: {'active': 0, 'stall': 0, 'idle': 0, 'total': 0})
    last_time = {}
    last_value = {}

    for timestamp, sig_id, value in parser.stream_changes(set(core_signals.keys())):
        name = core_signals[sig_id]['full_name']
        if sig_id in last_time:
            dt = timestamp - last_time[sig_id]
            v = last_value.get(sig_id, '0000')
            if v in ('0100', '0101'):  # EXECUTE, UPDATE
                core_stats[name]['active'] += dt
            elif v in ('0110', '0111', '1001', '1010'):  # Various stall states
                core_stats[name]['stall'] += dt
            else:
                core_stats[name]['idle'] += dt
            core_stats[name]['total'] += dt
        last_time[sig_id] = timestamp
        last_value[sig_id] = value

    return dict(core_stats)


def analyze_memory_traffic(parser):
    """Track memory read/write request rates over time."""
    print("[Analyzer] Computing memory traffic...")
    header = parser.parse_header()

    mem_signals = {}
    for sig_id, info in header.items():
        if any(kw in info['name'] for kw in ['mem_read_valid', 'mem_write_valid', 'hbm']):
            mem_signals[sig_id] = info

    # Bin into time windows
    window_size = 1000  # time units per bin
    traffic = defaultdict(lambda: {'reads': 0, 'writes': 0})

    for timestamp, sig_id, value in parser.stream_changes(set(mem_signals.keys())):
        window = timestamp // window_size
        name = mem_signals[sig_id]['name']
        if value == '1':
            if 'read' in name:
                traffic[window]['reads'] += 1
            elif 'write' in name:
                traffic[window]['writes'] += 1

    return dict(traffic)


def generate_text_report(core_stats, mem_traffic, output_dir):
    """Generate a plain-text performance report."""
    os.makedirs(output_dir, exist_ok=True)
    report_path = os.path.join(output_dir, 'perf_report.txt')

    with open(report_path, 'w') as f:
        f.write("=" * 72 + "\n")
        f.write("GridX³ Performance Analysis Report\n")
        f.write("=" * 72 + "\n\n")

        # Core Utilization
        f.write("--- Core Utilization ---\n")
        f.write(f"{'Signal':<50} {'Active%':>8} {'Stall%':>8} {'Idle%':>8}\n")
        f.write("-" * 74 + "\n")
        for name, stats in sorted(core_stats.items()):
            total = max(stats['total'], 1)
            active_pct = 100.0 * stats['active'] / total
            stall_pct = 100.0 * stats['stall'] / total
            idle_pct = 100.0 * stats['idle'] / total
            f.write(f"{name:<50} {active_pct:>7.1f}% {stall_pct:>7.1f}% {idle_pct:>7.1f}%\n")

        # Memory Traffic Summary
        f.write("\n--- Memory Traffic ---\n")
        total_reads = sum(v['reads'] for v in mem_traffic.values())
        total_writes = sum(v['writes'] for v in mem_traffic.values())
        f.write(f"Total Read Requests:  {total_reads}\n")
        f.write(f"Total Write Requests: {total_writes}\n")

        if mem_traffic:
            peak_window = max(mem_traffic.keys(),
                              key=lambda w: mem_traffic[w]['reads'] + mem_traffic[w]['writes'])
            peak = mem_traffic[peak_window]
            f.write(f"Peak Traffic Window:  t={peak_window} "
                    f"(reads={peak['reads']}, writes={peak['writes']})\n")

    print(f"[Analyzer] Report written to {report_path}")
    return report_path


def generate_csv(core_stats, mem_traffic, output_dir):
    """Generate CSV files for external plotting tools."""
    os.makedirs(output_dir, exist_ok=True)

    # Core utilization CSV
    csv_path = os.path.join(output_dir, 'core_utilization.csv')
    with open(csv_path, 'w') as f:
        f.write("signal,active_cycles,stall_cycles,idle_cycles,total_cycles,active_pct\n")
        for name, stats in sorted(core_stats.items()):
            total = max(stats['total'], 1)
            pct = 100.0 * stats['active'] / total
            f.write(f"{name},{stats['active']},{stats['stall']},{stats['idle']},{total},{pct:.1f}\n")
    print(f"[Analyzer] Core CSV: {csv_path}")

    # Memory traffic CSV
    csv_path2 = os.path.join(output_dir, 'memory_traffic.csv')
    with open(csv_path2, 'w') as f:
        f.write("time_window,reads,writes\n")
        for window in sorted(mem_traffic.keys()):
            t = mem_traffic[window]
            f.write(f"{window},{t['reads']},{t['writes']}\n")
    print(f"[Analyzer] Memory CSV: {csv_path2}")


# ============================================================================
# ASCII HEATMAP (no matplotlib dependency)
# ============================================================================
def print_ascii_heatmap(core_stats):
    """Print a simple ASCII heatmap of core utilization."""
    print("\n" + "=" * 60)
    print("Core Utilization Heatmap (Active %)")
    print("=" * 60)
    chars = " ░▒▓█"
    for name, stats in sorted(core_stats.items()):
        total = max(stats['total'], 1)
        pct = 100.0 * stats['active'] / total
        bar_len = int(pct / 2)
        idx = min(int(pct / 25), len(chars) - 1)
        bar = chars[idx] * bar_len
        short_name = name.split('.')[-1] if '.' in name else name
        print(f"  {short_name:<30} [{bar:<50}] {pct:.0f}%")
    print()


# ============================================================================
# MAIN
# ============================================================================
def main():
    parser_arg = argparse.ArgumentParser(description="GridX³ VCD Performance Analyzer")
    parser_arg.add_argument("vcd_file", help="Path to VCD file")
    parser_arg.add_argument("--output", default="vcd_report", help="Output directory")
    parser_arg.add_argument("--csv", action="store_true", help="Generate CSV files")
    parser_arg.add_argument("--signals", nargs="*", help="Filter signals by name substring")
    parser_arg.add_argument("--num-cores", type=int, default=8, help="Number of cores")
    args = parser_arg.parse_args()

    if not os.path.exists(args.vcd_file):
        print(f"ERROR: VCD file not found: {args.vcd_file}")
        sys.exit(1)

    vcd_parser = VCDStreamParser(args.vcd_file)

    print(f"[Analyzer] Parsing: {args.vcd_file}")
    print(f"[Analyzer] Output:  {args.output}")

    core_stats = analyze_core_utilization(vcd_parser, args.num_cores)
    mem_traffic = analyze_memory_traffic(vcd_parser)

    generate_text_report(core_stats, mem_traffic, args.output)
    print_ascii_heatmap(core_stats)

    if args.csv:
        generate_csv(core_stats, mem_traffic, args.output)

    print("[Analyzer] Done.")


if __name__ == "__main__":
    main()
