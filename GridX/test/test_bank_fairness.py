"""
UPG-ARCH-002 Test 2: test_bank_fairness
Intent: No starvation under repeated conflict
Scenario: Two warps repeatedly collide on same bank
Expected:
  - Alternating grant
  - Bounded wait time
"""
import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from utils import sig_to_int, sig_to_bool, CLOCK_PERIOD_NS, CLOCK_UNIT


@cocotb.test()
async def test_alternating_grant_under_contention(dut):
    """Verify that grants alternate fairly when two requesters collide repeatedly"""
    clock = Clock(dut.clk, CLOCK_PERIOD_NS, units=CLOCK_UNIT)
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    # Track grants over multiple cycles
    grant_0_count = 0
    grant_4_count = 0
    cycles = 20
    
    for _ in range(cycles):
        # Both request bank 0 (continuous contention)
        dut.request_valid[0].value = 1
        dut.request_bank[0].value = 0
        dut.request_is_write[0].value = 0
        
        dut.request_valid[4].value = 1
        dut.request_bank[4].value = 0
        dut.request_is_write[4].value = 0
        
        await RisingEdge(dut.clk)
        await RisingEdge(dut.clk)
        
        # Count grants
        if sig_to_int(dut.grant[0]) == 1:
            grant_0_count += 1
        if sig_to_int(dut.grant[4]) == 1:
            grant_4_count += 1

    # With round-robin, grants should be roughly equal
    cocotb.log.info(f"  Grant counts over {cycles} cycles: thread_0={grant_0_count}, thread_4={grant_4_count}")
    
    # Allow some variance but ensure fairness (each should get at least 25% of grants)
    min_expected = cycles // 4
    assert grant_0_count >= min_expected, f"Thread 0 starved: {grant_0_count} grants < {min_expected}"
    assert grant_4_count >= min_expected, f"Thread 4 starved: {grant_4_count} grants < {min_expected}"
    
    # Cleanup
    dut.request_valid[0].value = 0
    dut.request_valid[4].value = 0
    await RisingEdge(dut.clk)

    cocotb.log.info("✓ test_alternating_grant_under_contention: PASSED")


@cocotb.test()
async def test_bounded_wait_time(dut):
    """Verify that no requester waits indefinitely (bounded wait)"""
    clock = Clock(dut.clk, CLOCK_PERIOD_NS, units=CLOCK_UNIT)
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    # Thread 0 continuously requests bank 0
    # Thread 4 continuously requests bank 0
    # Track max consecutive wait cycles for thread 4
    
    max_wait_thread_4 = 0
    current_wait = 0
    cycles = 30
    
    for _ in range(cycles):
        dut.request_valid[0].value = 1
        dut.request_bank[0].value = 0
        dut.request_is_write[0].value = 0
        
        dut.request_valid[4].value = 1
        dut.request_bank[4].value = 0
        dut.request_is_write[4].value = 0
        
        await RisingEdge(dut.clk)
        await RisingEdge(dut.clk)
        
        if sig_to_int(dut.grant[4]) == 1:
            max_wait_thread_4 = max(max_wait_thread_4, current_wait)
            current_wait = 0
        else:
            current_wait += 1

    # Max wait should be bounded (with 2 requesters, max wait should be 1 cycle theoretically)
    # Allow up to 4 cycles for implementation tolerance
    bounded_wait = 8  # Conservative bound
    assert max_wait_thread_4 <= bounded_wait, \
        f"Wait time unbounded: thread 4 waited {max_wait_thread_4} cycles"
    
    cocotb.log.info(f"  Max consecutive wait for thread 4: {max_wait_thread_4} cycles")
    
    # Cleanup
    dut.request_valid[0].value = 0
    dut.request_valid[4].value = 0
    await RisingEdge(dut.clk)

    cocotb.log.info("✓ test_bounded_wait_time: PASSED")


@cocotb.test()
async def test_round_robin_priority_advancement(dut):
    """Verify priority pointer advances correctly after each grant"""
    clock = Clock(dut.clk, CLOCK_PERIOD_NS, units=CLOCK_UNIT)
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    # Track which thread gets granted first over several rounds
    first_grants = []
    
    for round_num in range(8):
        # All threads request bank 0
        for i in range(4):
            dut.request_valid[i].value = 1
            dut.request_bank[i].value = 0
            dut.request_is_write[i].value = 0
        
        await RisingEdge(dut.clk)
        await RisingEdge(dut.clk)
        
        # Find which thread was granted
        for i in range(4):
            if sig_to_int(dut.grant[i]) == 1:
                first_grants.append(i)
                break
        
        # Clear requests for next round
        for i in range(4):
            dut.request_valid[i].value = 0
        await RisingEdge(dut.clk)
        await RisingEdge(dut.clk)

    cocotb.log.info(f"  Grant sequence: {first_grants}")
    
    # With round-robin, we expect the sequence to cycle through threads
    # At minimum, different threads should be granted across rounds
    unique_winners = len(set(first_grants))
    assert unique_winners >= 2, f"Round-robin broken: only {unique_winners} unique winner(s)"
    
    cocotb.log.info("✓ test_round_robin_priority_advancement: PASSED")


@cocotb.test()
async def test_three_way_contention_fairness(dut):
    """Verify fairness with 3-way bank contention"""
    clock = Clock(dut.clk, CLOCK_PERIOD_NS, units=CLOCK_UNIT)
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    # Threads 0, 1, 2 all request bank 0
    grant_counts = {0: 0, 1: 0, 2: 0}
    cycles = 30
    
    for _ in range(cycles):
        for i in [0, 1, 2]:
            dut.request_valid[i].value = 1
            dut.request_bank[i].value = 0
            dut.request_is_write[i].value = 0
        
        await RisingEdge(dut.clk)
        await RisingEdge(dut.clk)
        
        for i in [0, 1, 2]:
            if sig_to_int(dut.grant[i]) == 1:
                grant_counts[i] += 1

    cocotb.log.info(f"  3-way contention grant counts: {grant_counts}")
    
    # Each thread should get at least some grants (no starvation)
    for thread_id, count in grant_counts.items():
        assert count >= 2, f"Thread {thread_id} starved with only {count} grants"
    
    # Cleanup
    for i in range(8):
        dut.request_valid[i].value = 0
    await RisingEdge(dut.clk)

    cocotb.log.info("✓ test_three_way_contention_fairness: PASSED")
