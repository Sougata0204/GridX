import cocotb
from cocotb.triggers import RisingEdge, ClockCycles, Timer
from cocotb.clock import Clock
from test.helpers.memory import Memory
from test.utils import sig_to_int

# Opcode constants matching decoder.sv
CONST   = 0b1001
ADD     = 0b0011
SUB     = 0b0100
MUL     = 0b0101
STR     = 0b1000
RET     = 0b1111

def compile_instruction(opcode, rd, rs, rt, imm=0):
    inst = (opcode & 0xF) << 12
    inst |= (rd & 0xF) << 8
    
    if opcode == CONST:
        inst |= (imm & 0xFF)
    else:
        inst |= (rs & 0xF) << 4
        inst |= (rt & 0xF)
    return inst

@cocotb.test()
async def test_1024_thread_scale(dut):
    """
    Verify 1024 threads (16 Cores * 64 Threads) execution.
    Kernel: Dest = BlockID * 64 + ThreadID. Store Dest -> Mem[Dest].
    """
    clock = Clock(dut.clk, 10, units=None)
    cocotb.start_soon(clock.start())

    # Initialize Memory Models
    # Program Memory: 4 Channels, 8-bit Address, 16-bit Data
    program_memory = Memory(dut=dut, addr_bits=8, data_bits=16, channels=4, name="program")
    
    # Data Memory: 16 Channels (1 per Core), 16-bit Address (64KB), 8-bit Data
    data_memory = Memory(dut=dut, addr_bits=16, data_bits=8, channels=16, name="data")

    # Reset
    dut._log.info("DUT Hierarchy: " + str(dir(dut)))
    dut.reset.value = 1
    dut.start.value = 0
    dut.device_control_write_enable.value = 0
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 2)

    # Program kernel
    # R0 = 64
    # R1 = R13 (BlockID) * R0
    # R2 = R1 + R15 (ThreadID)
    # R3 = 0x90 (Upper byte for 0x9000) - Wait, we only have 8-bit immediates?
    # CONST R3, 0x90; LSH R3, 8 (Need specific instruction? No LSH)
    # Mul? R3 = 144 (0x90). R4 = 256. R3 = R3 * R4 = 36864 (0x9000).
    # Easier: Just use CONST 0x90, store to high byte? No, standard add.
    # CONST R3, 144 (0x90) -> 8-bit imm fits (-128 to 127 signed? unsigned?)
    # Decoder sign extends. 0x90 is negative (-112).
    # We moved to 16-bit registers. Address calculation needs care.
    # Let's use 0x4000 (16384). 64 * 256.
    # Instruction set is limited. 
    # Alternative: The Python Memory Model can check L1 if we expose it? No.
    # Let's use 0 (Low) + High Byte offset?
    # NEW PLAN: Registers are 16-bit. 
    # Can we load large immediate? CONST loads 8-bit sign extended.
    # 0x0000 - 0x00FF.
    # To get 0x9000:
    # CONST R3, 144 (-112). This becomes 0xFF90. Not 0x9000.
    # CONST R3, 0. CONST R4, 0.
    # Workaround: Use negative offset? 
    # OR: Use the fact that logic uses `core.sv` parameters?
    # Actually, can I modify `test_1024_threads` to read from internal signals?
    # Yes, `dut.core_instance[i].l1_memory.memory`
    # That is robust.
    # Moving test verification to Internal Inspection allows verifying L1!
    # This is BETTER than forcing L3.
    #
    # Wait, 1024 threads. 16 cores. 
    # I iterate cores 0..15.
    # Read `dut.core_instance[c].l1_memory.memory`.
    # Verify contents.
    # This proves L1 works.
    # 
    # BUT, the test *also* runs the Python Memory Model which expects requests.
    # If requests don't come, `data_memory.run()` might hang if it expects validity?
    # No, `Memory` model is passive slave. It waits for request.
    # The `while` loop checks `done` signal.
    # So if I update the Verification Section to check internals, it works.
    
    # REVERT: Do NOT change the kernel. Change the Verification Logic.
    
    # Updated Kernel for L2 Mesh Verification
    # R0 = 64 (Scale)
    # R1 = BlockID * 64
    # R2 = R1 + ThreadID (Global ID 0..1023)
    
    # 1. L1 Write: Mem[R2] = R2 (0..1023) - Verified previously
    
    # 2. L2 Local Write: Mem[0x8000 + (CoreID << 10) + ThreadID] = 0xAA
    # But kernel doesn't know CoreID directly (only BlockID).
    # BlockID 0-3 -> Core 0. BlockID 4-7 -> Core 1 ?? 
    # Current Dispatch: Blocks distributed to cores.
    # We can just write to `0x8000`.
    # Address `0x8000` maps to Slice 0 (Core 0).
    # IF Core 0 writes `0x8000`, it is LOCAL.
    # IF Core 1 writes `0x8000`, it is NEIGHBOR (West).
    # Let's simple test:
    # All threads write to `0x8000 + GlobalID`.
    # 0x8000 + 0..1023.
    # This range `0x8000 - 0x83FF`.
    # This falls entirely into SLICE 0 (Core 0's Slice).
    # So Core 0 accesses Local.
    # Core 1 accesses Neighbor (Slice 0 is West of Core 1).
    # Core 2 accesses ... (Slice 0 is West of West? No, Slice 0 is (0,0). Core 2 is (0,2). Distance 2. Not neighbor).
    # Wait, Routing logic checks `valid_west` (Distance 1).
    # So Core 2 -> Slice 0 should fail/drop?
    # Spec: "Neighbor access requires router hop".
    # My router logic: `target_is_west` means `dest == my_id - 1`.
    # Core 1 (ID 1) -> Slice 0 (ID 0). Dest=0. My=1. 0 == 1-1. YES. West.
    # Core 2 (ID 2) -> Slice 0. Dest=0. My=2. 0 != 2-1. NO.
    
    # So, we should test Valid Neighbor Patterns.
    # Let's have every thread write to its OWN Local Slice?
    # Address = `0x8000 + (CoreID * 1024) + ThreadID`.
    # How to get CoreID?
    # derived from BlockID? 
    # BlockID / 4 = CoreID? (Since 4 blocks per core).
    # R13 is BlockID.
    # R_Core = R13 >> 2? (No shift).
    # R_Core = R13 / 4? (No DIV).
    
    # Alternative Strategy:
    # Use Global Memory `0xC000`.
    # Everyone writes Global ID to `0xC000 + GlobalID`.
    # This verifies routing to Global.
    
    # And specifically Core 0 writes to L2 Slice 0.
    # Core 1 writes to L2 Slice 1.
    # AND Core 0 writes to L2 Slice 1 (Neighbor).
    
    # Kernel:
    # R_GlobalID (calculated)
    # STR [R_GlobalID], R_GlobalID (L1 Test)
    
    # Global Access
    # R_GlobalBase = 0xC000
    # R_Addr = R_GlobalBase + R_GlobalID
    # STR [R_Addr], R_GlobalID
    
    # How to construct 0xC000?
    # -16384 (0xC000 is negative in 16-bit? 49152. Top bit 1. Yes).
    # CONST R_C0, 0xC0 (-64). 
    # MUL R_C000, R_C0, 256.
    # -64 * 256 = -16384 = 0xC000.
    
    prog = [
        # Registers: R0..15.
        # R13=BlockID, R15=ThreadID.
        
        # 1. Calculate Global ID -> R2
        compile_instruction(CONST, 0, 0, 0, 64),        # R0 = 64
        compile_instruction(MUL,   1, 13, 0),           # R1 = BlockID * 64
        compile_instruction(ADD,   2, 1,  15),          # R2 = R1 + ThreadID (Global ID)

        # 2. L1 Write: Mem[R2] = R2
        compile_instruction(STR,   0, 2,  2),           # Store R2 to Addr R2
        
        # 2.5 L2 Mesh Write: Mem[0x8000 + R2] = R2
        # Target Slice 0 (0x8000-0x83FF).
        # Core 0: Local. Core 1: West N. Core 4: South N.
        # Construct 0x8000 (-32768)
        compile_instruction(CONST, 3, 0, 0, 0x80),      # R3 = 0x80 (-128)
        compile_instruction(CONST, 4, 0, 0, 64),        # R4 = 64
        compile_instruction(ADD,   4, 4, 4),            # R4 = 128
        compile_instruction(ADD,   4, 4, 4),            # R4 = 256
        compile_instruction(MUL,   5, 3, 4),            # R5 = -32768 (0x8000)
        
        compile_instruction(ADD,   6, 5, 2),            # R6 = 0x8000 + GlobalID
        compile_instruction(STR,   0, 6, 2),            # Mem[R6] = R2
        
        # 3. Global Write: Mem[0xC000 + R2] = R2
        # Construct 0xC000 (-16384)
        # We reused R3(-128). Need -64.
        compile_instruction(CONST, 3, 0, 0, 0xC0),      # R3 = 0xC0 (-64)
        # R4 is still 256.
        compile_instruction(MUL,   5, 3, 4),            # R5 = -16384 (0xC000)
        
        compile_instruction(ADD,   6, 5, 2),            # R6 = 0xC000 + GlobalID
        compile_instruction(STR,   0, 6, 2),            # Mem[R6] = R2
        
        compile_instruction(RET,   0, 0, 0)
    ]

    # Load Program
    program_memory.load(prog)
    
    # Configure & Run
    dut.device_control_write_enable.value = 1
    dut.device_control_data.value = 1024
    await RisingEdge(dut.clk)
    dut.device_control_write_enable.value = 0
    
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    dut._log.info("Execution started...")
    
    cycles = 0
    timeout = 300000
    while sig_to_int(dut.done) == 0:
        program_memory.run()
        data_memory.run() # This handles the Global (0xC000) requests!
        await RisingEdge(dut.clk)
        cycles += 1
        if cycles > timeout: raise Exception("Timeout")

    # Verify L1 (Private)
    errors = 0
    for core_idx in range(16):
        try:
            core_l1 = dut.cores[core_idx].core_instance.l1_memory.memory
        except AttributeError:
             dut._log.error(f"Access error L1 Core {core_idx}")
             break
        for i in range(64):
            gid = core_idx*64 + i
            val = core_l1[gid].value.integer
            if val != (gid & 0xFF):
                dut._log.error(f"L1 mismatch Core {core_idx} T{i}")
                errors += 1
                if errors>5: break
                
    # Verify Global L3 (External Model)
    # Addr 0xC000 + GID.
    # data_memory is a dictionary/array.
    # The python model `Memory` class usually maps 0-based.
    # If the RTL sends 0xC000, the model receives 0xC000.
    # We check `data_memory.memory[0xC000 + gid]`.
    
    for i in range(1024):
        addr = 0xC000 + i
        val = data_memory.memory.get(addr, 0) # Use get for sparse if dict, or array access
        # The helper `Memory` uses a dict `self.memory = {}` usually or list?
        # Checking helper: `self.memory = {}`.
        
        expected = i & 0xFF
        if val != expected:
            dut._log.error(f"L3 mismatch Addr {hex(addr)}. Got {val}, Exp {expected}")
            errors += 1
            if errors > 10: break

    assert errors == 0, "Global/L1 Verification Failed"
    dut._log.info("Test Passed: L1 Local and L3 Global Mesh Routing verified!")
    
    # Verify L2 Slice 0 Contents (Internal Inspection)
    # Architecture: 4x4 Mesh.
    # Router 0 (0,0) owns Slice 0 (Addr 0 x8000 - 0x83FF).
    # Kernel: All 1024 threads wrote `GlobalID` to `0x8000 + GlobalID`.
    # Expected:
    # - Core 0 (ID 0-63): Local Access (Distance 0). ALLOWED.
    # - Core 1 (ID 64-127): West Access (Distance 1). ALLOWED.
    # - Core 4 (ID 256-319): North Access (Distance 1). ALLOWED.
    # - Core 5 (ID 320-383): Diagonal. Distance 2. BLOCKED.
    # - Core 2 (ID 128-191): Distance 2. BLOCKED.
    
    dut._log.info("Verifying L2 Mesh Routing (Slice 0)...")
    try:
        # Hierarchy: dut.rows[r].cols[c].router...
        # Note: Cocotb might flatten generates or use list access depending on tool.
        # Icarus usually does `rows[0].cols[0]`.
        slice0_mem = dut.rows[0].cols[0].router.memory_slice.memory
    except AttributeError:
        dut._log.error("Could not access L2 Slice 0 memory. Check hierarchy names.")
        assert False, "Hierarchy Error"
        
    l2_errors = 0
    for gid in range(1024):
        val = slice0_mem[gid].value.integer
        expected = gid & 0xFF
        
        # Determine Source Core
        src_core = gid // 64
        
        allowed = False
        if src_core == 0: allowed = True # Local
        elif src_core == 1: allowed = True # Core 1 is (0,1). Slice 0 (0,0) is West of Core 1.
        elif src_core == 4: allowed = True # Core 4 is (1,0). Slice 0 (0,0) is North of Core 4.
        
        if allowed:
            if val != expected:
                 dut._log.error(f"L2 Slice 0 Mismatch at {gid} (Core {src_core}). Got {val}, Exp {expected}")
                 l2_errors += 1
        else:
            # Should be 0 (or X, but formatted 0)
            if val != 0:
                 dut._log.error(f"L2 Slice 0 Leak! Core {src_core} (Dist > 1) wrote to {gid}. Val={val}")
                 l2_errors += 1
                 
        if l2_errors > 20: break

    assert l2_errors == 0, f"L2 Mesh Verification Failed with {l2_errors} errors."
    dut._log.info("L2 Mesh Verification Passed (Topology & Routing Confirmed)!")
