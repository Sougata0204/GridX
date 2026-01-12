import cocotb
from cocotb.triggers import RisingEdge
import logging

from test.helpers.memory import Memory
from test.helpers.setup import setup
from test.helpers.format import format_cycle
from test.utils import sig_to_int

logger = logging.getLogger("cocotb.test")

@cocotb.test()
async def test_matadd(dut):
    """Matrix Addition Test - Cocotb 2.0 Compatible"""
    
    # Setup Memory
    program_memory = Memory(dut=dut, addr_bits=8, data_bits=16, channels=4, name="program")
    data_memory = Memory(dut=dut, addr_bits=8, data_bits=8, channels=16, name="data")

    # Program: Matrix Addition with correct global addressing
    # global_idx = blockIdx * blockDim + threadIdx
    # Read A[global_idx], B[global_idx], write result to C[global_idx]
    #
    # R0 = 0
    # R1 = 8 (offset for B)
    # R2 = blockIdx * blockDim  (block offset)
    # R3 = R2 + threadIdx  (global thread index)
    # R4 = R3 (read address for A[global_idx])
    # R5 = A[R4]
    # R6 = R4 + 8 (read address for B[global_idx])
    # R7 = B[R6]
    # R8 = R5 + R7 (result)
    # R9 = R6 + 8 = global_idx + 16 (write address for C)
    # STR R9, R8
    program = [
        0b1001_0000_0000_0000, # CONST R0, #0
        0b1001_0001_0000_1000, # CONST R1, #8 (offset)
        0b0101_0010_1101_1110, # MUL R2, %blockIdx, %blockDim  -> R2 = blockIdx * blockDim
        0b0011_0011_0010_1111, # ADD R3, R2, %threadIdx        -> R3 = global thread index
        0b0011_0100_0000_0011, # ADD R4, R0, R3                -> R4 = global_idx (read addr A)
        0b0111_0101_0100_0000, # LDR R5, R4                    -> R5 = A[global_idx]
        0b0011_0110_0100_0001, # ADD R6, R4, R1                -> R6 = global_idx + 8 (read addr B)
        0b0111_0111_0110_0000, # LDR R7, R6                    -> R7 = B[global_idx]
        0b0011_1000_0101_0111, # ADD R8, R5, R7                -> R8 = A + B
        0b0011_1001_0110_0001, # ADD R9, R6, R1                -> R9 = global_idx + 16 (write addr C)
        0b1000_0000_1001_1000, # STR R9, R8                    -> C[global_idx] = R8
        0b1111_0000_0000_0000, # RET
    ]

    # Data: 16 elements each for A and B (2 blocks × 8 threads with 16-core GPU)
    data = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,  # Matrix A (16 elements)
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15   # Matrix B (16 elements)
    ]

    # Device Control: 16 threads = 2 blocks × 8 threads/block (for 16-core GPU)
    threads = 16

    await setup(
        dut=dut,
        program_memory=program_memory,
        program=program,
        data_memory=data_memory,
        data=data,
        threads=threads
    )

    data_memory.display(24)

    cycles = 0
    # Cocotb 2.0: Use sig_to_int for comparison
    while sig_to_int(dut.done) != 1:
        data_memory.run()
        program_memory.run()

        await cocotb.triggers.ReadOnly()
        format_cycle(dut, cycles)
        
        await RisingEdge(dut.clk)
        cycles += 1
        
        # Safety limit
        if cycles > 10000:
            raise Exception("Test timeout - exceeded 10000 cycles")

    # CANONICAL FIX: Post-done delay for memory write visibility
    # gpu.done means "kernel execution complete" but NOT "all writes externally visible"
    # Wait for final memory writes to propagate in simulation
    POST_DONE_DELAY_CYCLES = 10
    for _ in range(POST_DONE_DELAY_CYCLES):
        data_memory.run()
        program_memory.run()
        await RisingEdge(dut.clk)

    logger.info(f"Completed in {cycles} cycles (+ {POST_DONE_DELAY_CYCLES} post-done)")
    data_memory.display(24)

    expected_results = [a + b for a, b in zip(data[0:8], data[8:16])]
    for i, expected in enumerate(expected_results):
        result = data_memory.memory[i + 16]
        assert result == expected, f"Result mismatch at index {i}: expected {expected}, got {result}"
    
    logger.info("Matrix addition test PASSED!")