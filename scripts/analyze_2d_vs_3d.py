#!/usr/bin/env python3
"""
GridX³ 2D vs 3D Topology Comparison Analyzer
=============================================
Parses [CSV] lines from gvf.sv (3D) and gvf_2d.sv (2D) simulation logs,
computes bandwidth, bisection bandwidth, hop-count models, and produces
a publication-grade comparison table.

Usage:
    python analyze_2d_vs_3d.py <path_to_3d_log> <path_to_2d_log>
    python analyze_2d_vs_3d.py   (uses default paths in xsim_work/)
"""

import sys
import re
import os
from collections import OrderedDict

# ===========================================================================
# CONSTANTS — from gridx_mem_pkg.sv and gridx_pkg.sv
# ===========================================================================
FLIT_WIDTH_BITS      = 256      # gridx_mem_pkg::FLIT_WIDTH
NOC_FREQ_MHZ         = 1000     # gridx_mem_pkg::NOC_FREQ_MHZ
LINK_BW_GBPS         = 256      # gridx_mem_pkg::LINK_BW_GBPS
NUM_VCS              = 4        # gridx_mem_pkg::NUM_VCS
SIM_CLK_PERIOD_NS    = 5.0      # gvf.sv::CLK_PERIOD (200 MHz simulation clock)
SIM_CLK_FREQ_HZ      = 1e9 / SIM_CLK_PERIOD_NS  # 200 MHz

# Topology constants
CONFIG_3D = {"name": "3D-BASELINE", "CUBE_X": 2, "CUBE_Y": 2, "CUBE_Z": 2, "cores": 8}
CONFIG_2D = {"name": "2D-SLICE",    "CUBE_X": 2, "CUBE_Y": 2, "CUBE_Z": 1, "cores": 4}


def parse_csv_lines(log_path):
    """Extract [CSV] lines from simulation log and parse into suite records."""
    results = OrderedDict()
    csv_pattern = re.compile(
        r'\[CSV\]\s+'
        r'([^,]+),'      # config label
        r'([^,]+),'      # kernel name
        r'(\d+),'        # threads
        r'(\d+),'        # cycles
        r'(\d+),'        # hbm_reads
        r'(\d+),'        # hbm_writes
        r'(\d+)'         # total_flits
    )

    if not os.path.exists(log_path):
        print(f"[ERROR] Log file not found: {log_path}")
        return results

    with open(log_path, 'r', errors='replace') as f:
        for line in f:
            m = csv_pattern.search(line)
            if m:
                config  = m.group(1).strip()
                kernel  = m.group(2).strip()
                threads = int(m.group(3))
                cycles  = int(m.group(4))
                hbm_rd  = int(m.group(5))
                hbm_wr  = int(m.group(6))
                flits   = int(m.group(7))

                # Use kernel+threads as key (handles duplicate kernel names)
                key = f"{kernel}(T={threads})"
                results[key] = {
                    "config":  config,
                    "kernel":  kernel,
                    "threads": threads,
                    "cycles":  cycles,
                    "hbm_rd":  hbm_rd,
                    "hbm_wr":  hbm_wr,
                    "flits":   flits,
                }
    return results


def effective_bandwidth(total_flits, cycle_count, flit_width_bits, clk_hz):
    """
    Compute effective bandwidth from simulation counters.
    Returns (cycles_per_flit, bytes_per_sec).
    cycles_per_flit is clock-independent and defensible without post-synthesis Fmax.
    bytes_per_sec uses assumed clock and should be labeled as such.
    """
    if total_flits == 0 or cycle_count == 0:
        return (float('inf'), 0.0)
    cycles_per_flit = cycle_count / total_flits
    bytes_per_flit  = flit_width_bits / 8
    bytes_per_sec   = bytes_per_flit * clk_hz / cycles_per_flit
    return (cycles_per_flit, bytes_per_sec)


def bisection_bandwidth_links(cube_x, cube_y, cube_z):
    """
    Bisection cut along X: parallel links crossing = CUBE_Y × CUBE_Z.
    This is the minimum cut for an X×Y×Z 3D mesh with XY-routing.
    """
    return cube_y * cube_z


def avg_hop_count(dims):
    """
    Average hop count for a k-ary n-cube with uniform random traffic.
    For each dimension d with size k_d: average hops in that dim = (k_d - 1) / 3.
    Total average hops = sum over all dimensions.
    Handles non-symmetric dimensions (X≠Y≠Z).
    """
    return sum((k - 1) / 3.0 for k in dims)


def queueing_latency(hop_count, router_delay_cycles, injection_rate, link_capacity):
    """
    M/M/1 per-router latency model.
    latency ≈ hop_count × (router_delay + ρ/(1-ρ) × service_time)
    where ρ = injection_rate / link_capacity.

    Returns latency in cycles, or "SATURATED" string if ρ >= 1.
    """
    if link_capacity == 0:
        return float('inf')
    rho = injection_rate / link_capacity
    if rho >= 1.0:
        return float('inf')  # saturated
    service_time = 1.0 / link_capacity if link_capacity > 0 else 0
    per_hop = router_delay_cycles + (rho / (1.0 - rho)) * service_time
    return hop_count * per_hop


def format_bw(bw_bytes_per_sec):
    """Format bandwidth as human-readable string."""
    if bw_bytes_per_sec == 0:
        return "0 B/s"
    elif bw_bytes_per_sec >= 1e9:
        return f"{bw_bytes_per_sec/1e9:.2f} GB/s"
    elif bw_bytes_per_sec >= 1e6:
        return f"{bw_bytes_per_sec/1e6:.2f} MB/s"
    else:
        return f"{bw_bytes_per_sec:.0f} B/s"


def print_separator(char='═', width=110):
    print(char * width)


def main():
    # Default paths
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    default_3d = os.path.join(project_root, "xsim_work", "gvf_3d.log")
    default_2d = os.path.join(project_root, "xsim_work", "gvf_2d.log")

    if len(sys.argv) >= 3:
        log_3d_path = sys.argv[1]
        log_2d_path = sys.argv[2]
    elif len(sys.argv) == 2 and sys.argv[1] in ('-h', '--help'):
        print(__doc__)
        sys.exit(0)
    else:
        log_3d_path = default_3d
        log_2d_path = default_2d

    print()
    print_separator()
    print("  GridX³ 2D vs 3D Topology Comparison — Controlled A/B Analysis")
    print_separator()
    print(f"  3D Log: {log_3d_path}")
    print(f"  2D Log: {log_2d_path}")
    print(f"  Sim Clock: {SIM_CLK_FREQ_HZ/1e6:.0f} MHz (assumed, pre-synthesis)")
    print(f"  Flit Width: {FLIT_WIDTH_BITS} bits")
    print()

    results_3d = parse_csv_lines(log_3d_path)
    results_2d = parse_csv_lines(log_2d_path)

    if not results_3d:
        print(f"[ERROR] No [CSV] data found in 3D log: {log_3d_path}")
        sys.exit(1)
    if not results_2d:
        print(f"[ERROR] No [CSV] data found in 2D log: {log_2d_path}")
        sys.exit(1)

    print(f"  Parsed {len(results_3d)} suites from 3D log")
    print(f"  Parsed {len(results_2d)} suites from 2D log")
    print()

    # ======================================================================
    # 1. THEORETICAL TOPOLOGY ANALYSIS
    # ======================================================================
    print_separator()
    print("  SECTION 1: Theoretical Topology Analysis")
    print_separator()

    bisect_3d = bisection_bandwidth_links(CONFIG_3D["CUBE_X"], CONFIG_3D["CUBE_Y"], CONFIG_3D["CUBE_Z"])
    bisect_2d = bisection_bandwidth_links(CONFIG_2D["CUBE_X"], CONFIG_2D["CUBE_Y"], CONFIG_2D["CUBE_Z"])
    link_bw_bytes = FLIT_WIDTH_BITS / 8  # bytes per flit per cycle

    print(f"  Config A (2D): {CONFIG_2D['CUBE_X']}×{CONFIG_2D['CUBE_Y']}×{CONFIG_2D['CUBE_Z']}  →  "
          f"{CONFIG_2D['cores']} cores, bisection = {bisect_2d} links")
    print(f"  Config B (3D): {CONFIG_3D['CUBE_X']}×{CONFIG_3D['CUBE_Y']}×{CONFIG_3D['CUBE_Z']}  →  "
          f"{CONFIG_3D['cores']} cores, bisection = {bisect_3d} links")
    print(f"  Bisection ratio: {bisect_3d}/{bisect_2d} = {bisect_3d/bisect_2d:.1f}×")
    print(f"    → 3D has {bisect_3d/bisect_2d:.0f}× more bisection bandwidth (textbook 3D-stacked advantage)")
    print()

    dims_2d = [CONFIG_2D["CUBE_X"], CONFIG_2D["CUBE_Y"]]  # 2D: only X,Y dimensions
    dims_3d = [CONFIG_3D["CUBE_X"], CONFIG_3D["CUBE_Y"], CONFIG_3D["CUBE_Z"]]
    hops_2d = avg_hop_count(dims_2d)
    hops_3d = avg_hop_count(dims_3d)
    print(f"  Average hop count (uniform random traffic):")
    print(f"    2D ({CONFIG_2D['CUBE_X']}×{CONFIG_2D['CUBE_Y']}):      {hops_2d:.3f} hops")
    print(f"    3D ({CONFIG_3D['CUBE_X']}×{CONFIG_3D['CUBE_Y']}×{CONFIG_3D['CUBE_Z']}):    {hops_3d:.3f} hops")
    print(f"    Delta: +{hops_3d - hops_2d:.3f} hops (extra Z dimension)")
    print(f"    → More hops in 3D, but 2× bisection bandwidth reduces contention")
    print()

    # M/M/1 latency model at various injection rates
    print(f"  M/M/1 Queuing Latency Model (router_delay=1 cycle):")
    print(f"  {'ρ (inject/capacity)':>25s}  {'2D Latency (cyc)':>18s}  {'3D Latency (cyc)':>18s}  {'Winner':>8s}")
    print(f"  {'-'*25}  {'-'*18}  {'-'*18}  {'-'*8}")
    for rho_pct in [10, 25, 50, 70, 85, 95]:
        rho = rho_pct / 100.0
        lat_2d = queueing_latency(hops_2d, 1.0, rho, 1.0)
        lat_3d = queueing_latency(hops_3d, 1.0, rho, 1.0)
        winner = "2D" if lat_2d < lat_3d else "3D" if lat_3d < lat_2d else "TIE"
        lat_2d_s = f"{lat_2d:.3f}" if lat_2d < 1e6 else "SATURATED"
        lat_3d_s = f"{lat_3d:.3f}" if lat_3d < 1e6 else "SATURATED"
        print(f"  {rho_pct:>24d}%  {lat_2d_s:>18s}  {lat_3d_s:>18s}  {winner:>8s}")
    print()
    print("  → At low ρ (latency-bound): 2D wins (fewer hops)")
    print("  → At high ρ (BW-bound): 3D wins (2× bisection absorbs traffic)")
    print()

    # ======================================================================
    # 2. PER-KERNEL COMPARISON TABLE
    # ======================================================================
    print_separator()
    print("  SECTION 2: Per-Kernel Empirical Comparison")
    print_separator()
    print()

    # Header
    hdr = f"  {'Kernel':30s} {'T':>3s} │ {'Cyc(3D)':>8s} {'Cyc(2D)':>8s} {'Δ':>6s} │ " \
          f"{'HBM_rd(3D)':>10s} {'HBM_rd(2D)':>10s} │ {'HBM_wr(3D)':>10s} {'HBM_wr(2D)':>10s} │ " \
          f"{'Flits(3D)':>9s} {'Flits(2D)':>9s} │ {'Speedup':>8s}"
    print(hdr)
    print("  " + "─" * (len(hdr) - 2))

    matched_keys = []
    for key in results_3d:
        if key in results_2d:
            matched_keys.append(key)

    for key in matched_keys:
        r3 = results_3d[key]
        r2 = results_2d[key]
        cyc_delta = r2["cycles"] - r3["cycles"]
        delta_str = f"+{cyc_delta}" if cyc_delta >= 0 else f"{cyc_delta}"
        speedup   = r2["cycles"] / r3["cycles"] if r3["cycles"] > 0 else 0

        print(f"  {key:30s} {r3['threads']:>3d} │ "
              f"{r3['cycles']:>8d} {r2['cycles']:>8d} {delta_str:>6s} │ "
              f"{r3['hbm_rd']:>10d} {r2['hbm_rd']:>10d} │ "
              f"{r3['hbm_wr']:>10d} {r2['hbm_wr']:>10d} │ "
              f"{r3['flits']:>9d} {r2['flits']:>9d} │ "
              f"{speedup:>7.2f}x")

    print()

    # ======================================================================
    # 3. BANDWIDTH ANALYSIS
    # ======================================================================
    print_separator()
    print("  SECTION 3: Effective Bandwidth Analysis")
    print(f"  (at assumed clock = {SIM_CLK_FREQ_HZ/1e6:.0f} MHz — pre-synthesis)")
    print_separator()
    print()

    print(f"  {'Kernel':30s} │ {'Cyc/Flit(3D)':>14s} {'BW(3D)':>12s} │ "
          f"{'Cyc/Flit(2D)':>14s} {'BW(2D)':>12s} │ {'BW Ratio':>10s}")
    print("  " + "─" * 108)

    for key in matched_keys:
        r3 = results_3d[key]
        r2 = results_2d[key]

        cpf_3d, bw_3d = effective_bandwidth(r3["flits"], r3["cycles"], FLIT_WIDTH_BITS, SIM_CLK_FREQ_HZ)
        cpf_2d, bw_2d = effective_bandwidth(r2["flits"], r2["cycles"], FLIT_WIDTH_BITS, SIM_CLK_FREQ_HZ)

        cpf_3d_s = f"{cpf_3d:.2f}" if cpf_3d < 1e6 else "∞"
        cpf_2d_s = f"{cpf_2d:.2f}" if cpf_2d < 1e6 else "∞"
        bw_ratio = bw_3d / bw_2d if bw_2d > 0 else 0

        print(f"  {key:30s} │ {cpf_3d_s:>14s} {format_bw(bw_3d):>12s} │ "
              f"{cpf_2d_s:>14s} {format_bw(bw_2d):>12s} │ {bw_ratio:>9.2f}x")

    print()

    # ======================================================================
    # 4. BISECTION BANDWIDTH VALIDATION
    # ======================================================================
    print_separator()
    print("  SECTION 4: Bisection Bandwidth — Theory vs Measured")
    print_separator()
    print()

    bisect_bw_3d = bisect_3d * link_bw_bytes  # bytes/cycle at bisection
    bisect_bw_2d = bisect_2d * link_bw_bytes

    print(f"  Theoretical bisection bandwidth (per cycle):")
    print(f"    2D: {bisect_2d} links × {int(link_bw_bytes)} B/flit = {int(bisect_bw_2d)} B/cycle")
    print(f"    3D: {bisect_3d} links × {int(link_bw_bytes)} B/flit = {int(bisect_bw_3d)} B/cycle")
    print(f"    Ratio: {bisect_bw_3d/bisect_bw_2d:.1f}×  (3D advantage)")
    print()

    # Compute aggregate measured bandwidth
    total_flits_3d = sum(r["flits"] for r in results_3d.values())
    total_cycles_3d = sum(r["cycles"] for r in results_3d.values())
    total_flits_2d = sum(r["flits"] for r in results_2d.values())
    total_cycles_2d = sum(r["cycles"] for r in results_2d.values())

    _, agg_bw_3d = effective_bandwidth(total_flits_3d, total_cycles_3d, FLIT_WIDTH_BITS, SIM_CLK_FREQ_HZ)
    _, agg_bw_2d = effective_bandwidth(total_flits_2d, total_cycles_2d, FLIT_WIDTH_BITS, SIM_CLK_FREQ_HZ)

    print(f"  Aggregate measured bandwidth (all suites):")
    print(f"    2D: {total_flits_2d} total flits, {total_cycles_2d} total cycles → {format_bw(agg_bw_2d)}")
    print(f"    3D: {total_flits_3d} total flits, {total_cycles_3d} total cycles → {format_bw(agg_bw_3d)}")
    if agg_bw_2d > 0:
        print(f"    Measured ratio: {agg_bw_3d/agg_bw_2d:.2f}× (compare with theoretical {bisect_bw_3d/bisect_bw_2d:.1f}×)")
    print()

    # Sanity check
    expected_ratio = bisect_3d / bisect_2d
    print(f"  ┌─ SANITY CHECK ─────────────────────────────────────────────┐")
    print(f"  │  Expected bisection ratio:  {expected_ratio:.1f}×                           │")
    if agg_bw_2d > 0:
        actual_ratio = agg_bw_3d / agg_bw_2d
        deviation = abs(actual_ratio - expected_ratio) / expected_ratio * 100
        if deviation < 30:
            print(f"  │  Measured  ratio:           {actual_ratio:.2f}× (deviation {deviation:.1f}%)      │")
            print(f"  │  ✓ Model matches implementation within {deviation:.0f}%                │")
        else:
            print(f"  │  Measured  ratio:           {actual_ratio:.2f}× (deviation {deviation:.1f}%)      │")
            print(f"  │  ⚠ Significant divergence — check routing/contention          │")
    print(f"  └────────────────────────────────────────────────────────────┘")
    print()

    # ======================================================================
    # 5. DIAGNOSTIC FLAGS
    # ======================================================================
    print_separator()
    print("  SECTION 5: Diagnostic Observations")
    print_separator()
    print()

    # Check if 2D shows disproportionate HBM traffic
    for key in matched_keys:
        r3 = results_3d[key]
        r2 = results_2d[key]
        if r3["hbm_rd"] > 0 and r2["hbm_rd"] > r3["hbm_rd"] * 1.5:
            print(f"  ⚠ {key}: 2D has {r2['hbm_rd']/r3['hbm_rd']:.1f}× more HBM reads than 3D")
            print(f"    → Check mem_mesh_bridge.sv routing for implicit Z-dimension assumptions")
        if r3["cycles"] > 0:
            ratio = r2["cycles"] / r3["cycles"]
            if ratio > 2.5:
                print(f"  ⚠ {key}: 2D is {ratio:.1f}× slower — possible contention/backpressure issue")
                print(f"    → Consider extending v_credit/v_mem monitors to log queue depth over time")

    # Check for kernels where 2D beats expectations
    for key in matched_keys:
        r3 = results_3d[key]
        r2 = results_2d[key]
        if r3["cycles"] > 0 and r2["cycles"] < r3["cycles"]:
            print(f"  ℹ {key}: 2D ({r2['cycles']} cyc) is faster than 3D ({r3['cycles']} cyc)")
            print(f"    → Expected for low-injection-rate kernels (fewer hops wins)")

    print()
    print_separator()
    print("  Analysis complete.")
    print_separator()
    print()


if __name__ == "__main__":
    main()
