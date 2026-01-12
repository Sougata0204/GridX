"""
UPG-001 Test 1: test_tile_visibility
Intent: Tile not readable before READY, readable after
Pass Criteria:
  - early_read_blocks: true
  - post_ready_read_ok: true  
  - data_integrity: true
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
async def test_early_read_blocks(dut):
    """Verify LSU read is blocked when tile is in IDLE state"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    dut.sram_base_reg.value = 0x00
    dut.sram_limit_reg.value = 0x7F
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    # Verify initial state is IDLE
    tile_0_state = int(dut.tile_state[0].value)
    assert tile_0_state == TILE_IDLE, f"Expected IDLE (0), got {tile_0_state}"

    # Attempt LSU read while tile is IDLE
    dut.core_read_valid[0].value = 1
    dut.core_read_address[0].value = 0x10  # Within SRAM region, tile 0
    await RisingEdge(dut.clk)

    # LSU must stall because tile is not READY
    lsu_stall = int(dut.lsu_must_stall[0].value)
    assert lsu_stall == 1, f"Expected stall when tile IDLE, got stall={lsu_stall}"

    dut.core_read_valid[0].value = 0
    await RisingEdge(dut.clk)

    cocotb.log.info("✓ early_read_blocks: PASSED - LSU correctly stalled when tile IDLE")


@cocotb.test()
async def test_loading_state_blocks(dut):
    """Verify LSU read is blocked when tile is in LOADING state"""
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

    # Trigger TILE_LD to move tile 0 from IDLE → LOADING
    dut.tile_ld_valid.value = 1
    dut.tile_ld_id.value = 0
    await RisingEdge(dut.clk)
    dut.tile_ld_valid.value = 0
    await RisingEdge(dut.clk)

    # Verify state is LOADING
    tile_0_state = int(dut.tile_state[0].value)
    assert tile_0_state == TILE_LOADING, f"Expected LOADING (1), got {tile_0_state}"

    # Attempt LSU read while tile is LOADING
    dut.core_read_valid[0].value = 1
    dut.core_read_address[0].value = 0x10
    await RisingEdge(dut.clk)

    # LSU must still stall
    lsu_stall = int(dut.lsu_must_stall[0].value)
    assert lsu_stall == 1, f"Expected stall when tile LOADING, got stall={lsu_stall}"

    dut.core_read_valid[0].value = 0
    await RisingEdge(dut.clk)

    cocotb.log.info("✓ loading_state_blocks: PASSED - LSU correctly stalled when tile LOADING")


@cocotb.test()
async def test_post_ready_read_ok(dut):
    """Verify LSU read is allowed after tile transitions to READY"""
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

    # IDLE → LOADING via TILE_LD
    dut.tile_ld_valid.value = 1
    dut.tile_ld_id.value = 0
    await RisingEdge(dut.clk)
    dut.tile_ld_valid.value = 0
    await RisingEdge(dut.clk)

    # LOADING → READY via DMA write complete
    dut.dma_write_done.value = 1
    await RisingEdge(dut.clk)
    dut.dma_write_done.value = 0
    await RisingEdge(dut.clk)

    # Verify state is READY
    tile_0_state = int(dut.tile_state[0].value)
    assert tile_0_state == TILE_READY, f"Expected READY (2), got {tile_0_state}"

    # Attempt LSU read - should NOT stall
    dut.core_read_valid[0].value = 1
    dut.core_read_address[0].value = 0x10
    await RisingEdge(dut.clk)

    lsu_stall = int(dut.lsu_must_stall[0].value)
    assert lsu_stall == 0, f"Expected no stall when tile READY, got stall={lsu_stall}"

    dut.core_read_valid[0].value = 0
    await RisingEdge(dut.clk)

    cocotb.log.info("✓ post_ready_read_ok: PASSED - LSU read allowed when tile READY")


@cocotb.test()
async def test_in_use_read_ok(dut):
    """Verify LSU read continues to work when tile is IN_USE"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset and setup
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

    # First read triggers READY → IN_USE
    dut.core_read_valid[0].value = 1
    dut.core_read_address[0].value = 0x10
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)  # State transition happens

    # Verify state is IN_USE
    tile_0_state = int(dut.tile_state[0].value)
    assert tile_0_state == TILE_IN_USE, f"Expected IN_USE (3), got {tile_0_state}"

    # Subsequent reads should still work
    lsu_stall = int(dut.lsu_must_stall[0].value)
    assert lsu_stall == 0, f"Expected no stall when tile IN_USE, got stall={lsu_stall}"

    dut.core_read_valid[0].value = 0
    await RisingEdge(dut.clk)

    cocotb.log.info("✓ in_use_read_ok: PASSED - LSU read allowed when tile IN_USE")


@cocotb.test()
async def test_evicting_state_blocks(dut):
    """Verify LSU read is blocked when tile is in EVICTING state"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset and setup
    dut.reset.value = 1
    dut.sram_base_reg.value = 0x00
    dut.sram_limit_reg.value = 0x7F
    dut.dma_write_done.value = 0
    dut.dma_read_done.value = 0
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

    # READY → EVICTING via TILE_ST
    dut.tile_st_valid.value = 1
    dut.tile_st_id.value = 0
    await RisingEdge(dut.clk)
    dut.tile_st_valid.value = 0
    await RisingEdge(dut.clk)

    # Verify state is EVICTING
    tile_0_state = int(dut.tile_state[0].value)
    assert tile_0_state == TILE_EVICTING, f"Expected EVICTING (4), got {tile_0_state}"

    # Attempt LSU read - should stall
    dut.core_read_valid[0].value = 1
    dut.core_read_address[0].value = 0x10
    await RisingEdge(dut.clk)

    lsu_stall = int(dut.lsu_must_stall[0].value)
    assert lsu_stall == 1, f"Expected stall when tile EVICTING, got stall={lsu_stall}"

    dut.core_read_valid[0].value = 0
    await RisingEdge(dut.clk)

    cocotb.log.info("✓ evicting_state_blocks: PASSED - LSU correctly stalled when tile EVICTING")


@cocotb.test()
async def test_data_integrity_full_lifecycle(dut):
    """Verify data integrity through complete tile lifecycle"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    dut.sram_base_reg.value = 0x00
    dut.sram_limit_reg.value = 0x7F
    dut.dma_write_done.value = 0
    dut.dma_read_done.value = 0
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    # Full lifecycle: IDLE → LOADING → READY → IN_USE → READY → EVICTING → IDLE
    states_observed = []

    # IDLE
    states_observed.append(int(dut.tile_state[0].value))

    # → LOADING
    dut.tile_ld_valid.value = 1
    dut.tile_ld_id.value = 0
    await RisingEdge(dut.clk)
    dut.tile_ld_valid.value = 0
    await RisingEdge(dut.clk)
    states_observed.append(int(dut.tile_state[0].value))

    # → READY
    dut.dma_write_done.value = 1
    await RisingEdge(dut.clk)
    dut.dma_write_done.value = 0
    await RisingEdge(dut.clk)
    states_observed.append(int(dut.tile_state[0].value))

    # → IN_USE (via first read)
    dut.core_read_valid[0].value = 1
    dut.core_read_address[0].value = 0x10
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    states_observed.append(int(dut.tile_state[0].value))
    dut.core_read_valid[0].value = 0
    await RisingEdge(dut.clk)

    # → READY (via TILE_FENCE)
    dut.tile_fence_valid.value = 1
    dut.tile_fence_id.value = 0
    await RisingEdge(dut.clk)
    dut.tile_fence_valid.value = 0
    await RisingEdge(dut.clk)
    states_observed.append(int(dut.tile_state[0].value))

    # → EVICTING
    dut.tile_st_valid.value = 1
    dut.tile_st_id.value = 0
    await RisingEdge(dut.clk)
    dut.tile_st_valid.value = 0
    await RisingEdge(dut.clk)
    states_observed.append(int(dut.tile_state[0].value))

    # → IDLE
    dut.dma_read_done.value = 1
    await RisingEdge(dut.clk)
    dut.dma_read_done.value = 0
    await RisingEdge(dut.clk)
    states_observed.append(int(dut.tile_state[0].value))

    expected = [TILE_IDLE, TILE_LOADING, TILE_READY, TILE_IN_USE, TILE_READY, TILE_EVICTING, TILE_IDLE]
    assert states_observed == expected, f"State sequence mismatch: {states_observed} != {expected}"

    cocotb.log.info("✓ data_integrity_full_lifecycle: PASSED - Complete state machine verified")
    cocotb.log.info(f"  States observed: {states_observed}")
