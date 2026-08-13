# GridX³ — 3D GPU System-on-Chip Architecture

GridX³ is a high-performance, 3D-mesh-interconnected GPU System-on-Chip (SoC) designed for massive parallel compute, scalable deep learning, and advanced rendering tasks. By leveraging a highly scalable 3D Network-on-Chip (NoC) architecture and a powerful SIMT (Single Instruction, Multiple Thread) core design, GridX³ eliminates traditional memory and communication bottlenecks found in conventional 2D GPU layouts.

## Architectural Overview

The core philosophy of GridX³ is to scale compute and memory bandwidth in three dimensions. The architecture is composed of the following primary subsystems:

1. **Compute Cores (SIMT Architecture)**
   - **Multi-Warp Schedulers**: Hardware-level context switching with zero overhead, supporting configurable thread blocks and warps per core.
   - **Tensor & ALU Pipelines**: Specialized execution units for dense matrix multiplications and general-purpose parallel scalar/vector arithmetic.
   - **SIMT Stack**: Hardware management of branch divergence, convergence, and thread masking.

2. **3D Network-on-Chip (NoC) Memory Mesh**
   - **X, Y, Z Routing**: Packets navigate a 3D coordinate space to access distributed L2 caches, HBM controllers, and peer cores.
   - **Virtual Channels & Credit Management**: Prevents deadlock and ensures high-priority traffic (like synchronization and configuration) is never blocked by bulk memory transfers.

3. **Memory Subsystem**
   - **L1/L2 Cache Hierarchy**: Tightly coupled local memory for high-speed scratchpad access, backed by a distributed L2 mesh.
   - **HBM3 Controllers**: Multiple high-bandwidth memory interfaces strategically placed around the 3D grid to provide massive global memory bandwidth.
   - **DMA & Shell Controllers**: Offload data movement from host to device memory with minimal CPU intervention.

4. **System Control & Power Management**
   - **DCR (Device Control Register)**: Unified interface for host-to-device configuration and kernel launching.
   - **GC6 Power FSM**: Fine-grained clock gating and power state management to minimize idle power draw.
   - **Kernel FSM & Watchdog**: Robust lifecycle management of compute kernels, including stall tracking and automatic fault recovery.

## Simulation & Verification Analysis

GridX³ includes a comprehensive, cycle-accurate verification suite that stress-tests the architecture through sequential execution stages. Below is the simulation time analysis demonstrating the functional correctness of the core dispatch, memory, and kernel FSM logic:

### 1. Full-Suite Execution Overview
The testbench sweeps through varying thread block sizes, memory hazards, and ALUs. Because the `perf_cycle_count` register resets per launch, it provides precise benchmarking per kernel. In a macro view, this multi-launch sequence appears as a dense block of activity, proving the robust resetting and parking of the Kernel FSM.

![Simulation Overview](docs/images/sim_overview.png)
*(Please upload your full overview screenshot here)*

### 2. Kernel FSM & Dispatch Sequencing
Zooming into a single launch window reveals the cycle-accurate progression of the hardware (Reset 0 -> Configured 1 -> Launch 2 -> Running 3). The `blocksDispatched` and `totalBlocks` registers operate entirely independently, with dispatch incrementing cleanly per core assignment.

![FSM and Dispatch Trace](docs/images/fsm_dispatch.png)
*(Please upload your zoomed FSM/Dispatch screenshot here)*

### 3. Core Activation & Walking-Bit Dispatch
The dispatcher operates on a clean, synchronous walking-bit logic. `coreResetW` and `coreStart` assert sequentially as work is distributed, proving that the multi-core scheduler is immune to cross-domain glitching.

![Core Activation Sequence](docs/images/core_activation.png)
*(Please upload your core execution screenshot here)*

## Repository Structure

```text
GridX/
├── src/                          # RTL Source Files
│   ├── alu.sv                    # Arithmetic Logic Unit
│   ├── core.sv                   # Top-level Compute Core
│   ├── decoder.sv                # Instruction Decoder
│   ├── fetcher.sv                # Instruction Fetch & PC Management
│   ├── gpu.sv                    # Multi-core GPU Module
│   ├── gridx_kernel_top.sv       # Top-level SoC Module
│   ├── hbm3_ctrl.sv              # High-Bandwidth Memory Controller
│   ├── kernel_fsm.sv             # Kernel Lifecycle State Machine
│   ├── lsu.sv                    # Load/Store Unit
│   ├── lsu_arbiter.sv            # Memory Request Arbiter
│   ├── pc.sv                     # Program Counter Logic
│   ├── perf_boost_controller.sv  # Performance Monitoring & Boost
│   ├── scheduler.sv              # Warp & Thread Scheduler
│   ├── simt_stack.sv             # Branch Divergence Stack
│   ├── tensor_unit.sv            # Matrix Multiplication Engine
│   └── ...                       # Additional interconnect and control modules
├── memory_mesh/                  # 3D NoC Subsystem
│   └── src/
│       ├── mem_mesh_top.sv       # 3D Router Top
│       ├── mem_mesh_router.sv    # XYZ Router Node
│       └── mem_mesh_arbiter.sv   # Router Arbiter
├── sim/                          # Simulation Testbenches
│   ├── tb_gridx_top.sv           # Full SoC Testbench
│   └── tb_gridx_kernel_top.sv    # Kernel Integration Testbench
└── scripts/                      # Build & Simulation Scripts
    ├── run_sim.tcl               # Vivado Simulation Runner
    ├── compile_xsim.tcl          # XSim Compiler
    └── run_linter.tcl            # Static RTL Analysis (Linter)
```

## Getting Started

### Prerequisites
- **Xilinx Vivado** (2022.2 or newer recommended)
- SystemVerilog 2012 compatible simulator
- Windows (Powershell/CMD) or Linux environment

### Running Simulations

The project includes automated Tcl scripts for compilation and simulation.

**To run the full SoC testbench (Recommended):**
```bash
vivado -mode batch -source scripts/run_sim.tcl
```
This will elaborate the design, compile the testbenches, and run the complete verification suite, including reset sequences, DCR configuration, SAXPY kernel execution, and memory readbacks.

**To run the kernel integration testbench only:**
```bash
vivado -mode batch -source scripts/compile_xsim.tcl -tclargs tb_gridx_kernel_top run . all
```

### Configuration Options
You can configure the simulation debug levels via environment variables:
```bash
# Windows PowerShell
$env:XILINX_DEBUG_LEVEL="none"  # Disable debug overhead (default)
$env:XILINX_DEBUG_LEVEL="all"   # Enable full tracing
```

## Contribution Guidelines

We welcome contributions to optimize the architecture, expand the instruction set, or improve the memory mesh routing algorithms.

### Submitting a Pull Request
1. **Fork the Repository** and create a feature branch (`feature/your-feature-name`).
2. **Adhere to Code Style**: Maintain the `default_nettype none` directive and standard SystemVerilog formatting rules utilized throughout the `src/` directory.
3. **Run the Linter**: Ensure zero elaboration warnings before submitting.
   ```bash
   vivado -mode batch -source scripts/run_linter.tcl
   ```
4. **Pass All Tests**: Verify that `tb_gridx_top.sv` outputs `ALL TESTS PASSED`.
5. **Open a PR**: Provide a clear description of the architectural change, performance impact, and any added test cases.

## License

Copyright (c) 2026. All Rights Reserved.
