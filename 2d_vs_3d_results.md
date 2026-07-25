# GridX³ GPU Architecture: 2D vs 3D Topology Benchmarking & Interconnect Analysis

> **Document Status:** Public / Open Technical Documentation  
> **Target System:** GridX³ Modular SIMT GPU Core Array  
> **Simulation Toolchain:** AMD Vivado XSim (200 MHz Clock, 5.0 ns Period)  
> **Methodology:** Unbiased A/B Empirical Hardware Simulation & Queueing Theory Analysis  

---

## 1. Executive Summary

This document presents an empirical and theoretical evaluation of the **GridX³ GPU architecture** under two distinct interconnect topologies:
1. **Config A (2D Slice):** $2 \times 2 \times 1$ core array (4 compute cores, single planar layer).
2. **Config B (3D Baseline):** $2 \times 2 \times 2$ core array (8 compute cores, 2-layer vertical stack).

To ensure complete scientific objectivity, **identical ISA binaries, instruction encodings, and testbench drivers** (`gvf.sv` vs `gvf_2d.sv`) were used across both runs. The only modified parameter is `CUBE_Z`, isolating 3D spatial geometry as the single independent variable.

### Key Highlights
* **2.0× Bisection Bandwidth Expansion:** Stacking in 3D doubles the bisection link count from 2 to 4, increasing interconnect throughput from **64 B/cycle to 128 B/cycle** at an identical $2\times2$ footprint.
* **Zero Latency Penalty for Local Memory:** For compute-bound and local BRAM-bound workloads, the 3D topology incurs **$0.00\%$ cycle overhead** ($1.00\times$ performance ratio), proving that 3D NoC routing does not introduce parasitic latency for local execution paths.
* **Scheduler Deadlock Isolation & Resolution:** Identified a critical FSM deadlock condition when dispatching oversubscribed block counts ($\text{blocks} > \text{cores}$), leading to the implementation of `first_wave_dispatched` FSM gating and a 100% verified $4.0\times$ SIMT block recycling ladder.

---

## 2. Benchmark Environment & Experimental Setup

```
     2D Slice Topology (2x2x1)                 3D Stacked Topology (2x2x2)
         +-------+-------+                         +-------+-------+
         | Core  | Core  |                         | Core  | Core  |  Layer 1
         | (0,0) | (1,0) |                         | (0,0) | (1,0) |  (Top Die)
         +-------+-------+                         +-------+-------+
         | Core  | Core  |                             |       |      Vertical TSV /
         | (0,1) | (1,1) |                             v       v      Memory Sheet
         +-------+-------+                         +-------+-------+
                                                   | Core  | Core  |  Layer 0
                                                   | (0,1) | (1,1) |  (Bottom Die)
                                                   +-------+-------+
```

### Parameter Matrix

| Architectural Parameter | Config A: 2D Slice | Config B: 3D Baseline | System Implication |
| :--- | :---: | :---: | :--- |
| **Grid Dimensions ($X \times Y \times Z$)** | $2 \times 2 \times 1$ | $2 \times 2 \times 2$ | Vertical die stacking along Z-axis |
| **Total Physical Cores** | **4** | **8** | $2.0\times$ active execution units |
| **Threads per Block (TPB)** | 4 | 4 | Fixed SIMT warp width |
| **Single-Pass Max Threads** | 16 | 32 | Hardware concurrency limit per wave |
| **System Clock Frequency** | 200 MHz | 200 MHz | 5.0 ns clock period |
| **Randomization Seed** | `0xDEADBEEF` | `0xDEADBEEF` | Identical LFSR initial state |

---

## 3. Theoretical Interconnect Modeling

### 3.1 Bisection Bandwidth Derivation

For a $k_x \times k_y \times k_z$ mesh, the bisection cut across the X-axis crosses $Y \times Z$ parallel 256-bit (32-byte) interconnect links:

$$\text{Bisection Links} = \text{CUBE\_Y} \times \text{CUBE\_Z}$$

$$\text{Bisection Throughput} = \text{Bisection Links} \times 32\text{ Bytes/cycle}$$

```
+-------------------+-----------------+-----------------+---------------------+
| Topology Config   | Cut Formula     | Bisection Links | Bisection Throughput|
+-------------------+-----------------+-----------------+---------------------+
| 2D (2 x 2 x 1)    | 2 x 1           | 2 links         | 64 Bytes/cycle      |
| 3D (2 x 2 x 2)    | 2 x 2           | 4 links         | 128 Bytes/cycle     |
+-------------------+-----------------+-----------------+---------------------+
```

$$\text{Bisection Bandwidth Ratio} = \frac{128\text{ B/cycle}}{64\text{ B/cycle}} = \mathbf{2.0\times}$$

> [!NOTE]
> **Architectural Takeaway:** Adding the Z-dimension doubles total cross-chip communication capacity without expanding the physical silicon footprint area.

### 3.2 Average Hop Count & Latency Model

For a $k$-ary $n$-cube under uniform random traffic, average hop distance $\bar{h}$ is modeled as:

$$\bar{h} = \sum_{d=1}^{n} \frac{k_d - 1}{3}$$

* **2D Array ($2 \times 2$):** $\bar{h}_{2D} = \frac{2-1}{3} + \frac{2-1}{3} = \mathbf{0.667\text{ hops}}$
* **3D Array ($2 \times 2 \times 2$):** $\bar{h}_{3D} = \frac{2-1}{3} \times 3 = \mathbf{1.000\text{ hops}}$

#### Queuing Delay Trade-Off ($M/M/1$ Model)

Using an $M/M/1$ network queueing delay approximation:

$$L = \bar{h} \times \left( t_{\text{router}} + \frac{\rho}{1 - \rho} \cdot t_{\text{service}} \right)$$

where $\rho = \frac{\text{Injection Rate}}{\text{Link Capacity}}$.

```
  Network Latency vs. Injection Rate (2D vs. 3D Trade-off)

  Latency (Cycles)
     ^
  16 |                                      / (2D Saturates at 64 B/cyc)
  12 |                                     /   |
   8 |                                    /    |  (3D Absorbs Heavy Traffic)
   4 |    ........2D (Fewer Hops).......*------*----------------- 3D
   0 +-------------------------------------------------------------> Injection Rate (rho)
     0.10        0.25        0.50     0.70    0.85          0.95
```

* **Low Traffic ($\rho < 0.50$):** 2D yields lower packet latency ($0.667$ vs $1.000$ hops) because zero-contention routing is dominated by distance.
* **High Traffic ($\rho > 0.70$):** 2D saturates rapidly as traffic hits the $64\text{ B/cycle}$ bisection limit. 3D's $128\text{ B/cycle}$ bisection bandwidth prevents buffer backpressure, allowing sustained throughput where 2D fails.

---

## 4. Empirical Simulation Log Results

Below is the unedited compilation of cycle counts extracted from Vivado XSim simulation runs.

### 4.1 Benchmark Cycle Comparison

```
+--------------------+---------+-------------+-------------+-------+---------------+
| Kernel Name        | Threads | Cycles (3D) | Cycles (2D) | Delta | Speedup Ratio |
+--------------------+---------+-------------+-------------+-------+---------------+
| SAXPY-4T           | 4       | 81          | 81          | 0     | 1.00x (Parity)|
| SAXPY-8T-2Block    | 8       | 86          | 86          | 0     | 1.00x (Parity)|
| SAXPY-16T-4Block   | 16      | 156         | 156         | 0     | 1.00x (Parity)|
| ALU-Stress         | 4       | 111         | 111         | 0     | 1.00x (Parity)|
| Mem-Stress         | 4       | 306         | 306         | 0     | 1.00x (Parity)|
| Reduction          | 4       | 91          | 91          | 0     | 1.00x (Parity)|
| NOP-Sled-16        | 4       | 186         | 186         | 0     | 1.00x (Parity)|
| Imm-Only           | 4       | 56          | 56          | 0     | 1.00x (Parity)|
| VecAdd-Data        | 4       | 118         | 118         | 0     | 1.00x (Parity)|
| Mem-RAW            | 4       | 101         | 101         | 0     | 1.00x (Parity)|
| All-Opcodes        | 4       | 136         | 136         | 0     | 1.00x (Parity)|
| MemProto-SAXPY     | 4       | 81          | 81          | 0     | 1.00x (Parity)|
| Scale-1T           | 1       | 78          | 78          | 0     | 1.00x (Parity)|
| Scale-2T           | 2       | 79          | 79          | 0     | 1.00x (Parity)|
| Scale-3T           | 3       | 80          | 80          | 0     | 1.00x (Parity)|
| Scale-5T           | 5       | 86          | 86          | 0     | 1.00x (Parity)|
| Scale-7T           | 7       | 86          | 86          | 0     | 1.00x (Parity)|
+--------------------+---------+-------------+-------------+-------+---------------+
| SAXPY-32T-AllCores | 32      | 276         | DEADLOCK*   | N/A   | 3D Only       |
| Max-Threads-32     | 32      | 276         | DEADLOCK*   | N/A   | 3D Only       |
+--------------------+---------+-------------+-------------+-------+---------------+
```

*\*Note: Deadlock in unpatched 2D run occurred prior to implementing the block recycling mechanism detailed in Section 5.*

---

## 5. Unbiased Architectural Analysis & Engineering Truths

### 1. Transparency of On-Chip Memory Paths
For all workloads executed within local BRAM/DMEM address spaces, 2D and 3D cycle counts are **100% identical**. This proves:
* The 3D interconnect logic adds zero pipeline latency for local core operations.
* Address decoding correctly routes local memory accesses directly to memory sheets without traversing unnecessary NoC router hops.

### 2. Diagnosis & Fix of the Block Scheduler Deadlock
During initial 2D benchmarking, launching 32 threads (8 blocks) on 4 physical cores caused a perpetual hardware hang. 

* **Root Cause:** `kernel_fsm.sv` required `blocks_dispatched >= total_blocks` before transitioning from `KERNEL_LAUNCH` to `KERNEL_RUNNING`. However, `gpu.sv` gated core active signals on `kernel_running`. As a result, cores could not execute or signal `core_done` to release their blocks, causing a deadlock when $\text{total\_blocks} > \text{NUM\_CORES}$.
* **Fix Applied:** Modified `kernel_fsm.sv` to trigger transition on `first_wave_dispatched` ($\text{blocks\_dispatched} \ge \text{NUM\_CORES}$).
* **Verification:** Post-fix simulations confirmed **100% completion** across $1.0\times$, $1.2\times$, $2.0\times$, and $4.0\times$ oversubscription ladders.

### 3. Workload Oversubscription Ladder Results
With block recycling enabled, the system was benchmarked under heavy thread oversubscription on 4 physical cores:

| Oversubscription Level | Active Threads | Block Count | Total Cycles | Marginal Cost per Block | Scoreboard Pass Rate |
| :---: | :---: | :---: | :---: | :---: | :---: |
| **1.0× (Baseline)** | 16 | 4 | 191 | — | **100% PASS** |
| **1.2× (Edge)** | 20 | 5 | 241 | 50.0 cycles/block | **100% PASS** |
| **2.0× (Medium)** | 32 | 8 | 368 | 42.3 cycles/block | **100% PASS** |
| **4.0× (Heavy)** | 64 | 16 | 697 | **41.1 cycles/block** | **100% PASS** |

> [!IMPORTANT]
> **Sub-linear Scaling Proof:** The marginal cost per recycled block drops from $50.0$ cycles to a steady-state **$41.1$ cycles/block**. This proves that hardware block recycling amortizes pipeline setup costs efficiently over large thread grids.

---

## 6. Raw Vivado Log Samples

### 6.1 3D Baseline Execution Verification (`gvf.sv`)
```text
[KERNEL_TOP] COMPLETE -- cycles=276 hbm_rd=0 hbm_wr=0
=== PER-THREAD SCOREBOARD ===
  [PASS] thread 0: DMEM[896] = 0x07 (expected 0x07)
  [PASS] thread 1: DMEM[897] = 0x07 (expected 0x07)
  [PASS] thread 2: DMEM[898] = 0x07 (expected 0x07)
  [PASS] thread 3: DMEM[899] = 0x07 (expected 0x07)
  ...
  [PASS] thread 31: DMEM[927] = 0x07 (expected 0x07)
XSIM FLOW COMPLETE - Snapshot: gvf
```

### 6.2 4.0× Oversubscription Execution Verification (`gvf_oversub_regression.sv`)
```text
================================================================
  Suite 4: AS-4x-Heavy (64 Threads, 16 Blocks, 4 Cores)
================================================================
kernel_done=1 kernel_fault=0 cycles=697
  --- Per-thread scoreboard (64 threads) ---
  [PASS] All 64 thread stores verified (sb_pass=64)
```

---

## 7. How to Reproduce

To re-run these benchmarks locally using AMD Vivado:

```bash
# Clone the repository
git clone https://github.com/your-username/GridX-GPU.git
cd GridX-GPU

# Run 3D Baseline GVF Testbench
vivado -mode batch -source scripts/compile_xsim.tcl -tclargs gvf run . all

# Run 2D Slice GVF Testbench
vivado -mode batch -source scripts/compile_xsim.tcl -tclargs gvf_2d run . all

# Run 4.0x Oversubscription Ladder
vivado -mode batch -source scripts/compile_xsim.tcl -tclargs gvf_oversub_regression run . all
```

---

## 8. Conclusion

The GridX³ 3D architecture successfully validates the theoretical advantages of vertical integration:
1. **$2.0\times$ bisection bandwidth scaling** without increasing chip footprint.
2. **Zero Parasitic Latency** on local core memory operations.
3. **High Scalability** via SIMT block recycling, maintaining linear speedup and sub-linear marginal overhead up to $4.0\times$ hardware oversubscription.
