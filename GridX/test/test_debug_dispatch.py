"""
Debug Test: Full setup with memory, monitor parallel execution
"""
import cocotb
from cocotb.triggers import RisingEdge
from cocotb.clock import Clock
import logging

from test.helpers.memory import Memory
from test.helpers.setup import setup
from test.utils import sig_to_int, CLOCK_PERIOD_NS, CLOCK_UNIT

logger = logging.getLogger("cocotb.test.debug")


@cocotb.test()
async def test_debug_full_execution(dut):
    """Full test with memory, monitoring parallel execution"""
    
    # Setup Memory
    program_memory = Memory(dut=dut, addr_bits=8, data_bits=16, channels=1, name="program")
    data_memory = Memory(dut=dut, addr_bits=8, data_bits=8, channels=4, name="data")

    # Same program as matadd
    program = [
        0b1001_0000_0000_0000, # CONST R0, #0
        0b1001_0001_0000_1000, # CONST R1, #8
        0b0011_0010_0000_1111, # ADD R2, R0, %threadIdx
        0b0111_0011_0010_0000, # LDR R3, R2
        0b0011_0100_0010_0001, # ADD R4, R2, R1
        0b0111_0101_0100_0000, # LDR R5, R4
        0b0011_0110_0011_0101, # ADD R6, R3, R5
        0b0011_0111_0100_0001, # ADD R7, R4, R1
        0b1000_0000_0111_0110, # STR R7, R6
        0b1111_0000_0000_0000, # RET
    ]

    data = [
        0, 1, 2, 3, 4, 5, 6, 7,  # Matrix A
        0, 1, 2, 3, 4, 5, 6, 7   # Matrix B
    ]

    threads = 8

    await setup(
        dut=dut,
        program_memory=program_memory,
        program=program,
        data_memory=data_memory,
        data=data,
        threads=threads
    )

    state_names = {
        0: "IDLE", 1: "FETCH", 2: "DECODE", 3: "REQUEST",
        4: "WAIT", 5: "EXECUTE", 6: "UPDATE", 7: "DONE"
    }
    
    last_c0_state = -1
    last_c1_state = -1
    c0_done_cycle = None
    c1_done_cycle = None
    
    cycles = 0
    max_cycles = 300
    
    while cycles < max_cycles:
        data_memory.run()
        program_memory.run()
        
        await RisingEdge(dut.clk)
        cycles += 1
        
        try:
            c0_state = sig_to_int(dut.cores[0].core_instance.core_state)
            c1_state = sig_to_int(dut.cores[1].core_instance.core_state)
            c0_pc = sig_to_int(dut.cores[0].core_instance.current_pc)
            c1_pc = sig_to_int(dut.cores[1].core_instance.current_pc)
            c0_done = sig_to_int(dut.cores[0].core_instance.done)
            c1_done = sig_to_int(dut.cores[1].core_instance.done)
            
            # Track when cores complete
            if c0_done and c0_done_cycle is None:
                c0_done_cycle = cycles
                logger.info(f"Cycle {cycles}: Core 0 DONE")
                
            if c1_done and c1_done_cycle is None:
                c1_done_cycle = cycles
                logger.info(f"Cycle {cycles}: Core 1 DONE")
            
            # Log important state transitions
            if c0_state != last_c0_state:
                if c0_state == 7:  # DONE
                    logger.info(f"Cycle {cycles}: Core0 -> DONE (PC={c0_pc})")
                elif last_c0_state == -1 or c0_state < last_c0_state:
                    logger.info(f"Cycle {cycles}: Core0 -> {state_names.get(c0_state, c0_state)} (PC={c0_pc})")
                last_c0_state = c0_state
                
            if c1_state != last_c1_state:
                if c1_state == 7:  # DONE
                    logger.info(f"Cycle {cycles}: Core1 -> DONE (PC={c1_pc})")
                elif last_c1_state == -1 or c1_state < last_c1_state:
                    logger.info(f"Cycle {cycles}: Core1 -> {state_names.get(c1_state, c1_state)} (PC={c1_pc})")
                last_c1_state = c1_state
                
        except Exception as e:
            pass

        if sig_to_int(dut.done) == 1:
            logger.info(f"Cycle {cycles}: GPU DONE")
            break

    # Wait for writes to complete
    for _ in range(20):
        data_memory.run()
        await RisingEdge(dut.clk)
    
    logger.info(f"=== RESULTS ===")
    logger.info(f"Core 0 done at cycle: {c0_done_cycle}")
    logger.info(f"Core 1 done at cycle: {c1_done_cycle}")
    
    # Check memory
    logger.info(f"Memory results at addresses 16-23:")
    for i in range(16, 24):
        logger.info(f"  [{i}] = {data_memory.memory[i]}")
    
    # Verify
    expected = [0, 2, 4, 6, 8, 10, 12, 14]
    actual = data_memory.memory[16:24]
    logger.info(f"Expected: {expected}")
    logger.info(f"Actual:   {actual}")
    
    cocotb.log.info("Debug full execution complete")
