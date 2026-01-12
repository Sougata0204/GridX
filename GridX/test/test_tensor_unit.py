import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock
import random

def to_signed(val, bits):
    """Convert unsigned bit representation to signed integer"""
    if val & (1 << (bits - 1)):
        return val - (1 << bits)
    return val

def from_signed(val, bits):
    """Convert signed integer to unsigned bit representation"""
    if val < 0:
        return val + (1 << bits)
    return val & ((1 << bits) - 1)

def matrix_multiply(A, B, C):
    """
    Compute D = A * B + C for 4x4 matrices.
    A, B are 4x4 lists of INT16.
    C is 4x4 list of INT32.
    Returns D (4x4 INT32).
    """
    D = [[0]*4 for _ in range(4)]
    for i in range(4):
        for j in range(4):
            sum_val = 0
            for k in range(4):
                sum_val += A[i][k] * B[k][j]
            D[i][j] = sum_val + C[i][j]
            
            # Saturate or overflow check?
            # SystemVerilog logic uses 32-bit accumulation.
            # Max possible value: 4 * (-2^15 * -2^15) + 2^31
            # 4 * 2^30 = 2^32.
            # So sums can exceed 32-bit signed range if we are unlucky (overflow).
            # But standard logic just wraps. Python handles arbitrary precision.
            # We should mask to 32-bit signed for comparison.
    
    # Mask to 32-bit
    D_masked = [[0]*4 for _ in range(4)]
    for i in range(4):
        for j in range(4):
            val = D[i][j]
            # Simulate 32-bit wrapping
            val = val & 0xFFFFFFFF
            D_masked[i][j] = to_signed(val, 32)
            
    return D_masked

@cocotb.test()
async def test_tensor_math(dut):
    """
    Verify 4x4 INT16 Matrix Multiply-Accumulate (MMA) correctness.
    """
    clock = Clock(dut.clk, 10, units=None)
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    dut.start.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    num_tests = 10
    
    for t in range(num_tests):
        # Generate Random Inputs
        # 16-bit signed: -32768 to 32767
        # Keep values smaller to avoid overflow for basic testing? 
        # Or test full range? Hardware logic wraps, Python refs should match wrap.
        A = [[random.randint(-128, 127) for _ in range(4)] for _ in range(4)]
        B = [[random.randint(-128, 127) for _ in range(4)] for _ in range(4)]
        C = [[random.randint(-1000, 1000) for _ in range(4)] for _ in range(4)]

        # Drive Inputs
        # Dut input is packed array [3:0][3:0]
        # In cocotb/VPI, handling 2D packed arrays can be tricky.
        # Often appear as flattened vectors or list of handles.
        # Let's try iterating.
        
        # Pack Inputs into Integers
        # [3:0][3:0][15:0] implies [0][0] is LSB, [3][3] is MSB (standard Verilog packing)
        val_a = 0
        val_b = 0
        val_c = 0
        
        for i in range(4):
            for j in range(4):
                shift = (i * 4 + j) * 16   # 16 bits per element
                shift_c = (i * 4 + j) * 32 # 32 bits per element
                
                # Mask to correct width
                val_a |= (from_signed(A[i][j], 16) & 0xFFFF) << shift
                val_b |= (from_signed(B[i][j], 16) & 0xFFFF) << shift
                val_c |= (from_signed(C[i][j], 32) & 0xFFFFFFFF) << shift_c

        dut.matrix_a.value = val_a
        dut.matrix_b.value = val_b
        dut.matrix_c.value = val_c

        # Start Pulse
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0

        # Wait for Done
        await RisingEdge(dut.done)
        
        # Verify Output
        D_ref = matrix_multiply(A, B, C)
        
        # Unpack Output
        # dut.matrix_d is a 512-bit packed integer (16 x 32-bit)
        val_d = int(dut.matrix_d.value)
        
        errors = 0
        for i in range(4):
            for j in range(4):
                shift_c = (i * 4 + j) * 32
                # Extract 32 bits
                chunk = (val_d >> shift_c) & 0xFFFFFFFF
                signed_val = to_signed(chunk, 32)
                
                if signed_val != D_ref[i][j]:
                    dut._log.error(f"Mismatch at [{i}][{j}]: Result {signed_val} != Ref {D_ref[i][j]}")
                    errors += 1
        
        assert errors == 0, f"Test {t} failed with {errors} mismatches"
        
        dut._log.info(f"Test {t} Passed")
        await RisingEdge(dut.clk)

    dut._log.info("All Tensor Unit tests passed!")
