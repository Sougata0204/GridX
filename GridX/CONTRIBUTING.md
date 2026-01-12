# Contributing to GridX

Thank you for your interest in contributing to GridX! This document provides guidelines for contributing to the project.

##  Project Philosophy

Before contributing, please understand our core principles:

- **Correctness over performance** — We prioritize provably correct behavior
- **Explicit over implicit** — No hidden cache magic or undefined behavior
- **Research transparency** — All architectural decisions should be documented

##  Getting Started

### Prerequisites

```bash
# Required tools
- sv2v (SystemVerilog to Verilog converter)
- iverilog (Icarus Verilog) or verilator
- Python 3.10+
- cocotb (pip install cocotb)
```

### Setting Up Development Environment

```bash
git clone https://github.com/YOUR_USERNAME/GridX.git
cd GridX
pip install -r requirements.txt  # if available
```

### Running Tests

```bash
# Compile RTL
sv2v -w build/sim.v src/*.sv
iverilog -g2012 -o build/sim.vvp build/sim.v

# Run specific test
export COCOTB_TEST_MODULES="test.test_tensor_unit"
vvp -M $COCOTB_LIBS -m cocotbvpi_icarus build/sim.vvp
```

##  How to Contribute

### Reporting Bugs

1. Check existing issues first
2. Use the bug report template
3. Include:
   - Steps to reproduce
   - Expected vs actual behavior
   - Simulator version (iverilog/verilator)
   - Relevant log output

### Suggesting Enhancements

1. Check if the enhancement aligns with project philosophy
2. Use the feature request template
3. Explain the architectural rationale

### Code Contributions

1. **Fork** the repository
2. **Create a branch** (`git checkout -b feature/your-feature`)
3. **Make changes** following our style guide
4. **Test thoroughly** — all tests must pass
5. **Commit** with clear messages
6. **Push** and create a Pull Request

##  Code Style

### SystemVerilog

```systemverilog
// Module naming: snake_case
module l2_mesh_router #(
    parameter SLICE_ID = 0,     // Parameters: UPPER_CASE
    parameter ADDR_WIDTH = 16
) (
    input wire clk,             // Signals: snake_case
    input wire reset,
    output reg [7:0] data_out   // Aligned declarations
);
    // 4-space indentation
    // Comments for non-obvious logic
endmodule
```

### Python (Tests)

- Follow PEP 8
- Use type hints where helpful
- Document test purpose in docstring

##  Testing Requirements

All contributions must:

- [ ] Pass existing tests
- [ ] Include new tests for new functionality
- [ ] Not break the build (`sv2v` + `iverilog` must succeed)
- [ ] Follow the mathematical verification philosophy

## Pull Request Checklist

- [ ] Code follows style guidelines
- [ ] Self-reviewed the code
- [ ] Added comments for complex logic
- [ ] Updated documentation if needed
- [ ] All tests pass
- [ ] Commit messages are clear

## Architecture Changes

Major architectural changes require:

1. An implementation plan document
2. Discussion in an issue first
3. Clear rationale aligned with project principles
4. Verification strategy

## License

By contributing, you agree that your contributions will be licensed under the same license as the project.

## Questions?

Open a discussion or issue — we're happy to help!

---

*Thank you for helping make GridX better!*
