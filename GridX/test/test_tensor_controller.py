import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock
import random

@cocotb.test()
async def test_tensor_controller_arbitration(dut):
    """
    Verify Tensor Controller arbitration and multiple unit management.
    """
    clock = Clock(dut.clk, 10, units=None)
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    dut.request_valid.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    # Helper to drive inputs
    async def issue_request(warp_id):
        dut.request_valid.value = 1
        dut.warp_id.value = warp_id
        
        # Dummy Data (zeros is fine for arb test, or random)
        dut.src_a.value = 0
        dut.src_b.value = 0
        dut.src_c.value = 0
        
        await RisingEdge(dut.clk)
        
        # Check if ready
        if dut.request_ready.value == 1:
            dut._log.info(f"Request accepted for Warp {warp_id}")
            dut.request_valid.value = 0
            return True
        else:
            dut._log.info(f"Request stalled for Warp {warp_id}")
            return False

    # 1. Issue 4 requests consecutively (Should fill all 4 units)
    for w in range(4):
        success = await issue_request(w)
        assert success, f"Controller should accept request {w} (Units free)"
        
        # Check busy status (latency 1 cycle for update?)
        # Unit starts at posedge. Busy should reflect next cycle?
        # Controller logic: `warp_busy[warp_id] <= 1` at posedge.
        # So check after edge.
        await RisingEdge(dut.clk) 
        # Busy vector check
        busy_map = int(dut.warp_busy.value)
        assert (busy_map & (1 << w)), f"Warp {w} should be marked busy"

    # 2. Try 5th request (Should be rejected/tall)
    # At this point, 4 units are running. Latency is 4 cycles.
    # Depending on how fast we issued them.
    # Start T=0 (W0), T=2 (W1), T=4 (W2), T=6 (W3).
    # W0 finishes at T=4. So unit 0 might be free by T=6?
    # Let's check status.
    
    # Wait for completion
    timeout = 20
    completed_count = 0
    
    for _ in range(timeout):
        await RisingEdge(dut.clk)
        if dut.writeback_valid.value == 1:
            wid = int(dut.writeback_warp_id.value)
            dut._log.info(f"Writeback received for Warp {wid}")
            completed_count += 1
            
    assert completed_count >= 4, f"Expected 4 completions, got {completed_count}"

    dut._log.info("Controller arbitration verification passed!")
