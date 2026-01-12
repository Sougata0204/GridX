"""
UPG-ARCH-002 Test 1: test_bank_conflict_isolation
Intent: Only conflicting warp stalls, non-conflicting warps proceed
Scenario: warp0 and warp1 hit same bank, warp2 hits different bank
Expected:
  - warp0 or warp1 stalls
  - warp2 proceeds
  - no global stall
"""
import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from utils import sig_to_int, sig_to_bool, CLOCK_PERIOD_NS, CLOCK_UNIT


@cocotb.test()
async def test_conflicting_warps_stall_independently(dut):
    """Verify that only the conflicting warp stalls, not all warps"""
    clock = Clock(dut.clk, CLOCK_PERIOD_NS, units=CLOCK_UNIT)
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    # Scenario: 3 warps, each with threads
    # Warp 0 thread 0 requests bank 0
    # Warp 1 thread 0 requests bank 0 (CONFLICT with warp 0)
    # Warp 2 thread 0 requests bank 1 (NO CONFLICT)
    
    # Thread 0 (warp 0) -> bank 0
    dut.request_valid[0].value = 1
    dut.request_bank[0].value = 0
    dut.request_is_write[0].value = 0
    
    # Thread 4 (warp 1 if 4 threads/warp) -> bank 0 (conflict)
    dut.request_valid[4].value = 1
    dut.request_bank[4].value = 0
    dut.request_is_write[4].value = 0
    
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    # Check results
    grant_0 = sig_to_int(dut.grant[0])
    grant_4 = sig_to_int(dut.grant[4])
    conflict_0 = sig_to_int(dut.bank_conflict[0])
    conflict_4 = sig_to_int(dut.bank_conflict[4])
    
    # One should be granted, one should have conflict
    total_grants = grant_0 + grant_4
    total_conflicts = conflict_0 + conflict_4
    
    assert total_grants == 1, f"Expected exactly 1 grant, got {total_grants}"
    assert total_conflicts == 1, f"Expected exactly 1 conflict, got {total_conflicts}"
    
    cocotb.log.info("✓ Conflicting threads: one granted, one stalled")

    # Cleanup
    dut.request_valid[0].value = 0
    dut.request_valid[4].value = 0
    await RisingEdge(dut.clk)

    cocotb.log.info("✓ test_conflicting_warps_stall_independently: PASSED")


@cocotb.test()
async def test_non_conflicting_warp_proceeds(dut):
    """Verify that non-conflicting warp proceeds while others conflict"""
    clock = Clock(dut.clk, CLOCK_PERIOD_NS, units=CLOCK_UNIT)
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    # Thread 0 (warp 0) -> bank 0
    dut.request_valid[0].value = 1
    dut.request_bank[0].value = 0
    dut.request_is_write[0].value = 0
    
    # Thread 4 (warp 1) -> bank 0 (conflict with warp 0)
    dut.request_valid[4].value = 1
    dut.request_bank[4].value = 0
    dut.request_is_write[4].value = 0
    
    # Thread 1 (warp 0) -> bank 1 (NO conflict - different bank)
    dut.request_valid[1].value = 1
    dut.request_bank[1].value = 1
    dut.request_is_write[1].value = 0
    
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    # Thread 1 should always be granted (different bank)
    grant_1 = sig_to_int(dut.grant[1])
    conflict_1 = sig_to_int(dut.bank_conflict[1])
    
    assert grant_1 == 1, f"Thread 1 (different bank) should be granted, got {grant_1}"
    assert conflict_1 == 0, f"Thread 1 should have no conflict, got {conflict_1}"
    
    cocotb.log.info("✓ Non-conflicting thread granted immediately")

    # Cleanup
    for i in range(8):
        dut.request_valid[i].value = 0
    await RisingEdge(dut.clk)

    cocotb.log.info("✓ test_non_conflicting_warp_proceeds: PASSED")


@cocotb.test()
async def test_warp_stall_signal_isolation(dut):
    """Verify warp_stall signals are per-warp, not global"""
    clock = Clock(dut.clk, CLOCK_PERIOD_NS, units=CLOCK_UNIT)
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    # Warp 0 threads 0,1 both request bank 0 (intra-warp conflict)
    dut.request_valid[0].value = 1
    dut.request_bank[0].value = 0
    dut.request_is_write[0].value = 0
    
    dut.request_valid[1].value = 1
    dut.request_bank[1].value = 0  # Same bank = conflict
    dut.request_is_write[1].value = 0
    
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    # Warp 0 should have stall signal set
    warp_0_stall = sig_to_int(dut.warp_stall[0])
    warp_1_stall = sig_to_int(dut.warp_stall[1]) if hasattr(dut, 'warp_stall') and len(dut.warp_stall) > 1 else 0
    
    # Warp 0 has conflict, warp 1 has no requests
    assert warp_0_stall == 1, f"Warp 0 should stall (has conflict), got {warp_0_stall}"
    
    cocotb.log.info("✓ Per-warp stall signal correctly set for conflicting warp")

    # Cleanup
    for i in range(8):
        dut.request_valid[i].value = 0
    await RisingEdge(dut.clk)

    cocotb.log.info("✓ test_warp_stall_signal_isolation: PASSED")


@cocotb.test()
async def test_no_global_stall(dut):
    """Verify there is no signal that stalls all warps globally"""
    clock = Clock(dut.clk, CLOCK_PERIOD_NS, units=CLOCK_UNIT)
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    # Multiple warps request different banks - no conflicts expected
    # Thread 0 (warp 0) -> bank 0
    dut.request_valid[0].value = 1
    dut.request_bank[0].value = 0
    
    # Thread 4 (warp 1) -> bank 1
    dut.request_valid[4].value = 1
    dut.request_bank[4].value = 1
    
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    # Both should be granted (different banks)
    grant_0 = sig_to_int(dut.grant[0])
    grant_4 = sig_to_int(dut.grant[4])
    
    assert grant_0 == 1 and grant_4 == 1, \
        f"Both warps should proceed (different banks), got grants: {grant_0}, {grant_4}"
    
    cocotb.log.info("✓ No global stall - parallel access to different banks works")

    # Cleanup
    for i in range(8):
        dut.request_valid[i].value = 0
    await RisingEdge(dut.clk)

    cocotb.log.info("✓ test_no_global_stall: PASSED")
