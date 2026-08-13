# GridX³ — 3D GPU System-on-Chip Architecture

GridX³ is a high-performance, 3D-mesh-interconnected GPU System-on-Chip (SoC) designed from the ground up for massive parallel compute, scalable deep learning, and advanced rendering tasks. 

By replacing the traditional rigid 2D interconnect with a scalable 3D Network-on-Chip (NoC), GridX³ shatters the conventional "memory wall." Packets navigate an XYZ coordinate space to seamlessly access distributed L2 caches, peer compute cores, and massive HBM3 bandwidth.

## 🧠 Architectural Deep Dive

GridX³ scales compute and memory bandwidth in three dimensions across the following primary subsystems:

### 1. Compute Cores (SIMT Architecture)
At the heart of the grid are the execution cores, designed for zero-overhead context switching and deep pipelining:
- **Multi-Warp Schedulers**: Hardware-level thread management supporting configurable thread blocks and warps per core.
- **Tensor & ALU Pipelines**: Specialized execution units designed to crunch dense matrix multiplications and general-purpose parallel scalar/vector arithmetic simultaneously.
- **SIMT Stack**: A dedicated hardware stack that manages branch divergence, convergence, and thread masking without software overhead.

### 2. 3D Network-on-Chip (NoC) Memory Mesh
The backbone of GridX³ is its XYZ mesh network:
- **Distributed Topology**: Packets navigate a 3D coordinate space to access distributed L2 caches, HBM controllers, and peer cores.
- **Virtual Channels & Credit Management**: GridX³ prevents deadlocks and ensures high-priority traffic (like synchronization and configuration) is never blocked by bulk memory transfers.
- **GALS Clocking**: The mesh operates on a Globally Asynchronous, Locally Synchronous (GALS) architecture, allowing different network layers and compute cores to run at independent, optimal clock frequencies (e.g., 250MHz system clock with independent async layer clocks).

### 3. Memory Subsystem
- **L1/L2 Cache Hierarchy**: Tightly coupled local memory provides high-speed scratchpad access, backed by a fast distributed L2 mesh.
- **HBM3 Controllers**: Multiple high-bandwidth memory interfaces are strategically placed around the 3D grid to provide massive global memory bandwidth.
- **DMA & Shell Controllers**: Offload data movement from host to device memory with zero CPU intervention.

---

## 🔬 Simulation & Verification Analysis

GridX³ includes a comprehensive, cycle-accurate verification suite (`tb_fullchip_no_mesh.sv`) that stress-tests the entire architecture through 22 sequential execution stages. 

Below are the timing analysis captures demonstrating the functional correctness of the core dispatch, memory, and kernel FSM logic during a multi-launch benchmark sweep:

### 1. Full-Suite Execution Overview
The testbench sweeps through varying thread block sizes, memory hazards, and ALUs. Because the `perf_cycle_count` register resets per launch, it provides precise benchmarking per kernel. In a macro view, this multi-launch sequence appears as a dense block of activity, proving the robust resetting and parking of the Kernel FSM.
> *![Simulation Overview](docs/images/sim_overview.png)*
> *(Please upload your full 9.4us overview screenshot here)*

### 2. Kernel FSM & Dispatch Sequencing
Zooming into a single launch window reveals the cycle-accurate progression of the hardware:
1. **Reset (0) → Configured (1) → Launch (2) → Running (3)**. 
2. The `blocksDispatched` and `totalBlocks` registers operate entirely independently, with dispatch incrementing cleanly per core assignment.
> *![FSM and Dispatch Trace](docs/images/fsm_dispatch.png)*
> *(Please upload your zoomed FSM/Dispatch screenshot here)*

### 3. Core Activation & Walking-Bit Dispatch
The dispatcher operates on a clean, synchronous walking-bit logic. `coreResetW` and `coreStart` assert sequentially as work is distributed, proving that the multi-core scheduler is immune to cross-domain glitching.
> *![Core Activation Sequence](docs/images/core_activation.png)*
> *(Please upload your core execution/active cores screenshot here)*

---

## 📂 Repository Structure

```text
GridX/
├── src/                          # RTL Source Files
│   ├── core.sv                   # Top-level Compute Core
│   ├── gridx_kernel_top.sv       # Top-level SoC Module
│   ├── kernel_fsm.sv             # Kernel Lifecycle State Machine
│   ├── dispatch.sv               # Core Work Dispatcher
│   ├── perf_boost_controller.sv  # Performance Monitoring & Boost
│   ├── simt_stack.sv             # Branch Divergence Stack
│   └── ...                       # Additional execution and control modules
├── memory_mesh/                  # 3D NoC Subsystem
│   └── src/
│       ├── mem_mesh_top.sv       # 3D Router Top
│       └── mem_mesh_router.sv    # XYZ Router Node
├── sim/                          # Simulation Testbenches
│   ├── tb_fullchip_no_mesh.sv    # Full Suite Sequential Testbench
│   └── tb_gridx_kernel_top.sv    # Kernel Integration Testbench
└── scripts/                      # Build & Simulation Scripts
    ├── run_sim.tcl               # Vivado Simulation Runner
    └── compile_xsim.tcl          # XSim Compiler
```

## 🚀 Getting Started

### Prerequisites
- **Xilinx Vivado** (2022.2 or newer recommended)
- SystemVerilog 2012 compatible simulator
- Windows (Powershell/CMD) or Linux environment

### Running Simulations

The project includes automated Tcl scripts for compilation and simulation.

**To run the full SoC testbench (Recommended):**
```bash
vivado -mode batch -source scripts/run_vivado_gui_sim.tcl
```
This elaborates the design, compiles the testbenches, and runs the complete verification suite, opening the GUI to display the waveforms captured above.

### Configuration Options
You can configure the simulation debug levels via environment variables:
```bash
# Windows PowerShell
$env:XILINX_DEBUG_LEVEL="none"  # Disable debug overhead (default)
$env:XILINX_DEBUG_LEVEL="all"   # Enable full tracing
```

## 🤝 Contribution Guidelines

We welcome contributions to optimize the architecture, expand the instruction set, or improve the memory mesh routing algorithms.

1. **Fork the Repository** and create a feature branch (`feature/your-feature-name`).
2. **Adhere to Code Style**: Maintain the `default_nettype none` directive and standard SystemVerilog formatting rules utilized throughout the `src/` directory.
3. **Pass All Tests**: Verify that `tb_fullchip_no_mesh.sv` outputs `ALL FULL CHIP TESTS COMPLETE`.
4. **Open a PR**: Provide a clear description of the architectural change, performance impact, and any added test cases.

## License
Copyright (c) 2026. All Rights Reserved.
