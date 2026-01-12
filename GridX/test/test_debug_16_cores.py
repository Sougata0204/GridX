"""
Debug Test: 16 Core Dispatch Monitor
Check if simulation is just slow or stuck
"""
import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock
import logging

from test.utils import sig_to_int, CLOCK_PERIOD_NS, CLOCK_UNIT

logger = logging.getLogger("cocotb.test.debug")


@cocotb.test()
async def test_debug_16_core_start(dut):
    """Monitor 16 core dispatch signals"""
    clock = Clock(dut.clk, CLOCK_PERIOD_NS, units=CLOCK_UNIT)
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)
    
    # Set for 128 threads (16 blocks × 8 threads)
    dut.device_control_write_enable.value = 1
    dut.device_control_data.value = 128
    await RisingEdge(dut.clk)
    
    # Start
    dut.start.value = 1
    await RisingEdge(dut.clk)

    cores_started = set()
    
    # Run for 20 cycles and check progress
    for cycle in range(20):
        await RisingEdge(dut.clk)
        logger.info(f"Cycle {cycle}")
        
        for i in range(16):
            try:
                if sig_to_int(dut.cores[i].core_instance.start):
                    if i not in cores_started:
                        cores_started.add(i)
                        logger.info(f"  Core {i} STARTED")
            except:
                pass
                
    logger.info(f"Total cores started: {len(cores_started)}")
    
    if len(cores_started) == 16:
        cocotb.log.info("✓ 16 cores started successfully")
    else:
        cocotb.log.error(f"Only {len(cores_started)}/16 cores started")
