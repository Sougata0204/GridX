import cocotb
from cocotb.triggers import RisingEdge
from cocotb.clock import Clock
from test.helpers.memory import Memory
from test.utils import sig_to_int, CLOCK_PERIOD_NS, CLOCK_UNIT
import logging

logger = logging.getLogger("cocotb.test.debug")

@cocotb.test()
async def test_debug_scheduler_trace(dut):
    """
    Trace scheduler state transitions and warp switching on Core 0.
    """
    clock = Clock(dut.clk, CLOCK_PERIOD_NS, units=CLOCK_UNIT)
    cocotb.start_soon(clock.start())

    # Minimal Memory Setup
    program_memory = Memory(dut=dut, addr_bits=8, data_bits=16, channels=4, name="program")
    data_memory = Memory(dut=dut, addr_bits=8, data_bits=8, channels=16, name="data")

    # Simple program: LOAD (cause wait) -> RET
    program = [
        0b0000_0000_0000_0000, # NOP (to see fetch)
        0b1001_0000_0000_0000, # CONST R0, #0
        0b0111_0001_0000_0000, # LDR R1, R0 (Read Addr 0) -> triggers WAIT
        0b1111_0000_0000_0000, # RET
    ]
    program_memory.load(program)

    # Reset
    dut.reset.value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    # Start with 32 threads (2 blocks)
    dut.device_control_write_enable.value = 1
    dut.device_control_data.value = 32
    await RisingEdge(dut.clk)
    dut.device_control_write_enable.value = 0
    
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    # Trace loop
    for i in range(200):
        await RisingEdge(dut.clk)
        
        try:
            # Core 0
            c0 = dut.cores[0].core_instance
            c0_start = sig_to_int(c0.start)
            c0_done = sig_to_int(c0.done)
            c0_state = sig_to_int(c0.active_core_state)
            
            # Core 1
            c1 = dut.cores[1].core_instance
            c1_start = sig_to_int(c1.start)
            c1_done = sig_to_int(c1.done)
            c1_state = sig_to_int(c1.active_core_state)
            
            logger.info(f"C{i} | C0: S={c0_start} D={c0_done} St={c0_state} | C1: S={c1_start} D={c1_done} St={c1_state}")
        except Exception as e:
             logger.info(f"C{i} | Error: {e}")
             
        # Step memory
        data_memory.run()
        program_memory.run()

    cocotb.log.info("Trace finished")
