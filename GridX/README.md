# GridX

**A Research-Oriented SIMT GPU Architecture with Tensor Acceleration and Explicit 3D Logical Memory Hierarchy**

[![Status](https://img.shields.io/badge/status-active_research-blue)]()
[![Maturity](https://img.shields.io/badge/maturity-RTL_verified-green)]()
[![License](https://img.shields.io/badge/license-open_source-brightgreen)]()

---

## Overview

**GridX** is a research-focused, RTL-level GPU architecture project exploring how modern AI-oriented GPUs can be built using explicit, deterministic memory hierarchies, SIMT execution, and mesh-based near-core memory systems.

The project prioritizes **architectural correctness**, **locality**, **determinism**, and **power-aware design** over raw performance metrics. It is not intended to compete with commercial GPUs, but to serve as a transparent and educational exploration of real GPU design principles.

### What This Is
- A SIMT GPU microarchitecture written in SystemVerilog
- An explicit L1 / L2 / L3 memory hierarchy without cache magic
- A mesh-based near-core shared memory system
- A tensor-accelerated compute architecture
- A correctness-first research platform

### What This Is Not
- A commercial GPU
- A drop-in CUDA-compatible device
- A synthesis-ready production chip
- A performance-benchmarked accelerator

---

## Architecture

### Execution Model: SIMT

The GPU executes threads in warps using a **Single Instruction, Multiple Threads (SIMT)** model. Warps are statically scheduled, deterministic, and free from OS-style context switching.

| Parameter | Value |
|-----------|-------|
| Cores | 16 |
| Warps per Core | 2 |
| Threads per Warp | 8 |
| **Total Hardware Threads** | **256** |

### Compute Units

| Unit | Specification |
|------|---------------|
| **Scalar Pipeline** | 16-bit ALU for integer and control operations |
| **Tensor Units** | 4 units per core, 4×4 INT16 matrix multiply |

> **Design Goal**: High-throughput, locality-aware AI computation without reliance on large global memory bandwidth.

---

## 3D Logical Memory Hierarchy

### Philosophy
- Explicit hierarchy over implicit caches
- Locality-first design
- Deterministic access paths
- Logical 3D before physical 3D

### Memory Levels

```
┌─────────────────────────────────────────────────────────────┐
│                    L3: Global Tile Buffer                   │
│                      (Shared, via L2)                       │
└─────────────────────────────────────────────────────────────┘
                              ▲
                              │ Vertical Access
┌─────────────────────────────────────────────────────────────┐
│                    L2: 4×4 Mesh (16KB)                      │
│  ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐                         │
│  │ R00 │──│ R01 │──│ R02 │──│ R03 │  ← Row 0                │
│  └──┬──┘  └──┬──┘  └──┬──┘  └──┬──┘                         │
│     │        │        │        │                            │
│  ┌──┴──┐  ┌──┴──┐  ┌──┴──┐  ┌──┴──┐                         │
│  │ R04 │──│ R05 │──│ R06 │──│ R07 │  ← Row 1                │
│  └──┬──┘  └──┬──┘  └──┬──┘  └──┬──┘                         │
│     │        │        │        │       (1KB per Slice)      │
│  ┌──┴──┐  ┌──┴──┐  ┌──┴──┐  ┌──┴──┐                         │
│  │ R08 │──│ R09 │──│ R10 │──│ R11 │  ← Row 2                │
│  └──┬──┘  └──┬──┘  └──┬──┘  └──┬──┘                         │
│     │        │        │        │                            │
│  ┌──┴──┐  ┌──┴──┐  ┌──┴──┐  ┌──┴──┐                         │
│  │ R12 │──│ R13 │──│ R14 │──│ R15 │  ← Row 3                │
│  └─────┘  └─────┘  └─────┘  └─────┘                         │
│         Horizontal Neighbor Access (1 Hop Max)              │
└─────────────────────────────────────────────────────────────┘
                              ▲
                              │ Per-Core Connection
┌─────────────────────────────────────────────────────────────┐
│              L1: Core Local Memory (32KB each)              │
│                    (Private, 1-Cycle)                       │
└─────────────────────────────────────────────────────────────┘
```

### Address Map

| Level | Address Range | Size | Scope |
|-------|---------------|------|-------|
| **L1** | `0x0000 - 0x7FFF` | 32KB | Private per core |
| **L2** | `0x8000 - 0xBFFF` | 16KB (16 × 1KB slices) | Mesh shared |
| **L3** | `0xC000 - 0xFFFF` | 16KB window | Global |

### L2 Mesh Routing Rules

- **Local slice access**: Fastest (no routing)
- **Neighbor slice access**: Single hop only (N/S/E/W)
- **Diagonal or multi-hop**: **Forbidden**
- **Routing algorithm**: XY deterministic
- **Arbitration**: Round-robin (5-way: Core + 4 neighbors)

---

## Verification

### Philosophy
- Mathematical invariants over random testing
- Bounded behavior proofs
- Determinism validation

### Test Strategy

| Category | Tests |
|----------|-------|
| **Unit Tests** | ALU, Tensor Unit, L2 Slice, L2 Mesh Router |
| **System Tests** | Address-to-slice mapping, Mesh neighbor legality, Hierarchy priority, Bounded fairness |

### Simulator Support

| Simulator | Scale | Status |
|-----------|-------|--------|
| **Verilator** | Full system (16-core) | Primary |
| **Icarus Verilog** | Unit-scale only | Supported |

> **Note**: Event-driven simulators combined with Python VPI (cocotb) become unstable at full 16-core mesh scale. This is a known tooling limitation and does not indicate RTL errors.

---

## Getting Started

### Requirements
- `sv2v` - SystemVerilog to Verilog converter
- `iverilog` - Icarus Verilog (unit tests)
- `verilator` - Verilator (full system)
- `cocotb` - Python verification framework

### Quick Start

```bash
# Compile RTL
sv2v -w build/sim.v src/*.sv
iverilog -g2012 -o build/sim.vvp build/sim.v

# Run unit tests (with cocotb)
export COCOTB_TEST_MODULES="test.test_tensor_unit"
vvp -M $COCOTB_LIBS -m cocotbvpi_icarus build/sim.vvp
```

---

## Design Principles

| Principle | Description |
|-----------|-------------|
| **Correctness before performance** | Prove it works, then optimize |
| **Explicit over implicit** | No hidden cache behaviors |
| **Bounded latency** | Predictable access times |
| **Scalable topology** | Mesh design scales with cores |
| **Power awareness** | Sleep states, clock gating ready |
| **Research transparency** | Decisions documented honestly |

---

## Project Structure

```
GridX/
├── src/
│   ├── gpu.sv                 # Top-level module
│   ├── core.sv                # Compute core
│   ├── l2_mesh_router.sv      # L2 mesh router/arbiter
│   ├── l2_slice.sv            # L2 SRAM slice (1KB)
│   ├── tensor_controller.sv   # Tensor unit controller
│   ├── tensor_unit.sv         # 4×4 INT16 MMA
│   ├── scheduler.sv           # Warp scheduler
│   ├── decoder.sv             # Instruction decoder
│   └── ...
├── test/
│   ├── test_1024_threads.py   # System verification
│   ├── test_tensor_unit.py    # Tensor unit tests
│   └── helpers/
└── build/
```

---

## Future Work

### Planned
- Additional tensor dataflows
- Enhanced scheduler policies
- Formal verification extensions
- Performance counter instrumentation

### Explicitly Out of Scope
- Commercial benchmarking
- CUDA compatibility
- Fabrication tape-out claims

---

## Intended Audience

- Hardware architecture learners
- Systems engineers
- Computer architecture researchers
- Students exploring GPU design
- Open-source hardware enthusiasts

---

## Engineering Statement

> This project is a living architecture exploration. It is designed to evolve publicly, with decisions documented honestly and tradeoffs explained clearly.
>
> The goal is not to claim perfection, but to demonstrate disciplined architectural thinking, real RTL implementation, and a deep understanding of modern GPU design principles.

---

*GridX — correctness before scale, math before metrics, architecture before optimization.*
