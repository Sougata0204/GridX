"""
UPG-001 Test 2: test_tile_fence_ordering
Intent: TILE_FENCE blocks until tile is fully valid
Pass Criteria:
  - compute_blocks_before_ready: true
  - fence_releases_after_dma: true
  - no_partial_use: true
"""
import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock

# Tile states matching sram_controller.sv
TILE_IDLE = 0
TILE_LOADING = 1
TILE_READY = 2
TILE_IN_USE = 3
TILE_EVICTING = 4


@cocotb.test()
async def test_fence_blocks_before_ready(dut):
    """Verify TILE_FENCE does not release when tile is not READY"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    dut.sram_base_reg.value = 0x00
    dut.sram_limit_reg.value = 0x7F
    dut.dma_write_done.value = 0
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    # Start TILE_LD to move to LOADING state
    dut.tile_ld_valid.value = 1
    dut.tile_ld_id.value = 0
    await RisingEdge(dut.clk)
    dut.tile_ld_valid.value = 0
    await RisingEdge(dut.clk)

    # Verify in LOADING state
    assert int(dut.tile_state[0].value) == TILE_LOADING

    # Issue TILE_FENCE while still LOADING
    dut.tile_fence_valid.value = 1
    dut.tile_fence_id.value = 0
    await RisingEdge(dut.clk)

    # TILE_FENCE should NOT be done (tile not READY yet)
    fence_done = int(dut.tile_fence_done.value)
    assert fence_done == 0, f"FENCE should block while LOADING, got done={fence_done}"

    dut.tile_fence_valid.value = 0
    await RisingEdge(dut.clk)

    cocotb.log.info("✓ fence_blocks_before_ready: PASSED - TILE_FENCE blocked during LOADING")


@cocotb.test()
async def test_fence_releases_after_dma(dut):
    """Verify TILE_FENCE releases after DMA completes and tile is READY"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    dut.sram_base_reg.value = 0x00
    dut.sram_limit_reg.value = 0x7F
    dut.dma_write_done.value = 0
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    # IDLE → LOADING
    dut.tile_ld_valid.value = 1
    dut.tile_ld_id.value = 0
    await RisingEdge(dut.clk)
    dut.tile_ld_valid.value = 0
    await RisingEdge(dut.clk)

    # LOADING → READY via DMA complete
    dut.dma_write_done.value = 1
    await RisingEdge(dut.clk)
    dut.dma_write_done.value = 0
    await RisingEdge(dut.clk)

    # Verify in READY state
    assert int(dut.tile_state[0].value) == TILE_READY

    # Issue TILE_FENCE when READY
    dut.tile_fence_valid.value = 1
    dut.tile_fence_id.value = 0
    await RisingEdge(dut.clk)

    # TILE_FENCE should complete (tile is READY)
    fence_done = int(dut.tile_fence_done.value)
    assert fence_done == 1, f"FENCE should release when READY, got done={fence_done}"

    dut.tile_fence_valid.value = 0
    await RisingEdge(dut.clk)

    cocotb.log.info("✓ fence_releases_after_dma: PASSED - TILE_FENCE completed when tile READY")


@cocotb.test()
async def test_fence_blocks_during_in_use(dut):
    """Verify TILE_FENCE causes IN_USE → READY transition, then releases"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    dut.sram_base_reg.value = 0x00
    dut.sram_limit_reg.value = 0x7F
    dut.dma_write_done.value = 0
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    # IDLE → LOADING → READY
    dut.tile_ld_valid.value = 1
    dut.tile_ld_id.value = 0
    await RisingEdge(dut.clk)
    dut.tile_ld_valid.value = 0
    dut.dma_write_done.value = 1
    await RisingEdge(dut.clk)
    dut.dma_write_done.value = 0
    await RisingEdge(dut.clk)

    # READY → IN_USE via first read
    dut.core_read_valid[0].value = 1
    dut.core_read_address[0].value = 0x10
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.core_read_valid[0].value = 0
    await RisingEdge(dut.clk)

    # Verify in IN_USE state
    assert int(dut.tile_state[0].value) == TILE_IN_USE, "Expected IN_USE state"

    # Issue TILE_FENCE while IN_USE
    dut.tile_fence_valid.value = 1
    dut.tile_fence_id.value = 0
    await RisingEdge(dut.clk)

    # Fence triggers IN_USE → READY, then releases
    # After transition, fence should complete
    await RisingEdge(dut.clk)  # Allow state transition
    
    state = int(dut.tile_state[0].value)
    fence_done = int(dut.tile_fence_done.value)
    
    assert state == TILE_READY, f"Expected READY after FENCE, got {state}"
    assert fence_done == 1, f"FENCE should release after transition to READY"

    dut.tile_fence_valid.value = 0
    await RisingEdge(dut.clk)

    cocotb.log.info("✓ fence_blocks_during_in_use: PASSED - TILE_FENCE transitions IN_USE → READY")


@cocotb.test()
async def test_no_partial_use(dut):
    """Verify tile cannot be used partially (no reads during LOADING)"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    dut.sram_base_reg.value = 0x00
    dut.sram_limit_reg.value = 0x7F
    dut.dma_write_done.value = 0
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    # IDLE → LOADING
    dut.tile_ld_valid.value = 1
    dut.tile_ld_id.value = 0
    await RisingEdge(dut.clk)
    dut.tile_ld_valid.value = 0
    await RisingEdge(dut.clk)

    # Simulate DMA writing data over multiple cycles
    for cycle in range(5):
        # During each cycle of LOADING, attempt read
        dut.core_read_valid[0].value = 1
        dut.core_read_address[0].value = 0x10
        await RisingEdge(dut.clk)

        # Every read must be stalled
        lsu_stall = int(dut.lsu_must_stall[0].value)
        assert lsu_stall == 1, f"Cycle {cycle}: Partial read allowed during LOADING!"

        dut.core_read_valid[0].value = 0
        await RisingEdge(dut.clk)

    # Complete DMA
    dut.dma_write_done.value = 1
    await RisingEdge(dut.clk)
    dut.dma_write_done.value = 0
    await RisingEdge(dut.clk)

    # Now read should work
    dut.core_read_valid[0].value = 1
    dut.core_read_address[0].value = 0x10
    await RisingEdge(dut.clk)

    lsu_stall = int(dut.lsu_must_stall[0].value)
    assert lsu_stall == 0, "Read should succeed after DMA complete"

    dut.core_read_valid[0].value = 0
    await RisingEdge(dut.clk)

    cocotb.log.info("✓ no_partial_use: PASSED - No partial reads during LOADING")


@cocotb.test()
async def test_fence_ordering_with_multiple_tiles(dut):
    """Verify TILE_FENCE correctly tracks per-tile state"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    dut.sram_base_reg.value = 0x00
    dut.sram_limit_reg.value = 0x7F
    dut.dma_write_done.value = 0
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    # Load tile 0
    dut.tile_ld_valid.value = 1
    dut.tile_ld_id.value = 0
    await RisingEdge(dut.clk)
    dut.tile_ld_valid.value = 0
    dut.dma_write_done.value = 1
    await RisingEdge(dut.clk)
    dut.dma_write_done.value = 0
    await RisingEdge(dut.clk)

    # Tile 0 should be READY, tile 1 should be IDLE
    assert int(dut.tile_state[0].value) == TILE_READY, "Tile 0 should be READY"
    assert int(dut.tile_state[1].value) == TILE_IDLE, "Tile 1 should be IDLE"

    # FENCE on tile 0 should succeed
    dut.tile_fence_valid.value = 1
    dut.tile_fence_id.value = 0
    await RisingEdge(dut.clk)
    assert int(dut.tile_fence_done.value) == 1, "FENCE on READY tile 0 should succeed"

    # FENCE on tile 1 (IDLE) should fail
    dut.tile_fence_id.value = 1
    await RisingEdge(dut.clk)
    assert int(dut.tile_fence_done.value) == 0, "FENCE on IDLE tile 1 should block"

    dut.tile_fence_valid.value = 0
    await RisingEdge(dut.clk)

    cocotb.log.info("✓ fence_ordering_with_multiple_tiles: PASSED - Per-tile fence tracking correct")


@cocotb.test()
async def test_compute_blocks_before_ready(dut):
    """Integration test: Verify compute cannot proceed before tile is ready"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    dut.sram_base_reg.value = 0x00
    dut.sram_limit_reg.value = 0x7F
    dut.dma_write_done.value = 0
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    # Track stall cycles
    stall_cycles = 0
    work_cycles = 0

    # Start loading tile
    dut.tile_ld_valid.value = 1
    dut.tile_ld_id.value = 0
    await RisingEdge(dut.clk)
    dut.tile_ld_valid.value = 0

    # Simulate compute trying to read while DMA in progress
    dut.core_read_valid[0].value = 1
    dut.core_read_address[0].value = 0x10

    for _ in range(10):  # 10 cycles of DMA
        await RisingEdge(dut.clk)
        if int(dut.lsu_must_stall[0].value) == 1:
            stall_cycles += 1
        else:
            work_cycles += 1

    # Complete DMA
    dut.dma_write_done.value = 1
    await RisingEdge(dut.clk)
    dut.dma_write_done.value = 0

    # Continue for a few more cycles
    for _ in range(5):
        await RisingEdge(dut.clk)
        if int(dut.lsu_must_stall[0].value) == 1:
            stall_cycles += 1
        else:
            work_cycles += 1

    dut.core_read_valid[0].value = 0
    await RisingEdge(dut.clk)

    cocotb.log.info(f"  Stall cycles: {stall_cycles}, Work cycles: {work_cycles}")
    assert stall_cycles > 0, "Expected stalls during LOADING"
    assert work_cycles > 0, "Expected work cycles after READY"

    cocotb.log.info("✓ compute_blocks_before_ready: PASSED - Compute stalled until tile ready")
