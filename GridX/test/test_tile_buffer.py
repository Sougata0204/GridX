import cocotb
from cocotb.triggers import RisingEdge
from cocotb.clock import Clock

@cocotb.test()
async def test_tile_buffer_sequential_access(dut):
    """Test sequential access across multiple banks"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    dut.sram_base.value = 0x00
    dut.sram_limit.value = 0x7F
    for i in range(dut.NUM_BANKS.value):
        dut.bank_power_enable[i].value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    # Write to addresses 0-7 (should spread across 8 banks)
    for addr in range(8):
        # Enable write for requester 0
        dut.write_valid[0].value = 1
        dut.write_address[0].value = addr
        dut.write_data[0].value = 0x1000 + addr
        await RisingEdge(dut.clk)
        
        # Wait for ready
        while dut.write_ready[0].value != 1:
            await RisingEdge(dut.clk)
        dut.write_valid[0].value = 0
        await RisingEdge(dut.clk)

    cocotb.log.info("All sequential writes completed")

    # Read back and verify
    for addr in range(8):
        dut.read_valid[0].value = 1
        dut.read_address[0].value = addr
        await RisingEdge(dut.clk)
        
        while dut.read_ready[0].value != 1:
            await RisingEdge(dut.clk)
            
        expected = 0x1000 + addr
        actual = int(dut.read_data[0].value)
        assert actual == expected, f"Address {addr}: expected {hex(expected)}, got {hex(actual)}"
        dut.read_valid[0].value = 0
        await RisingEdge(dut.clk)

    cocotb.log.info("Sequential access test PASSED")


@cocotb.test()
async def test_tile_buffer_parallel_access(dut):
    """Test parallel access from multiple requesters to different banks"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    dut.sram_base.value = 0x00
    dut.sram_limit.value = 0x7F
    for i in range(dut.NUM_BANKS.value):
        dut.bank_power_enable[i].value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    # Parallel writes to different banks (no conflict expected)
    # Address 0 -> bank 0, Address 1 -> bank 1, etc.
    for i in range(min(4, dut.NUM_REQUESTERS.value)):
        dut.write_valid[i].value = 1
        dut.write_address[i].value = i  # Different banks
        dut.write_data[i].value = 0xABCD0000 + i
    
    await RisingEdge(dut.clk)
    
    # All should complete without conflict
    for i in range(min(4, dut.NUM_REQUESTERS.value)):
        assert dut.bank_conflict[i].value == 0, f"Unexpected conflict for requester {i}"
    
    await RisingEdge(dut.clk)
    
    for i in range(min(4, dut.NUM_REQUESTERS.value)):
        dut.write_valid[i].value = 0
    
    cocotb.log.info("Parallel no-conflict access test PASSED")


@cocotb.test()
async def test_tile_buffer_bank_conflict(dut):
    """Test bank conflict detection and resolution"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    dut.sram_base.value = 0x00
    dut.sram_limit.value = 0x7F
    for i in range(dut.NUM_BANKS.value):
        dut.bank_power_enable[i].value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    # Two requesters access the same bank (addresses 0 and 8 both map to bank 0)
    # Assuming 8 banks with low-order interleaving: addr % 8 = bank
    dut.write_valid[0].value = 1
    dut.write_address[0].value = 0  # Bank 0
    dut.write_data[0].value = 0x11111111
    
    dut.write_valid[1].value = 1
    dut.write_address[1].value = 8  # Also bank 0 (8 % 8 = 0)
    dut.write_data[1].value = 0x22222222
    
    await RisingEdge(dut.clk)
    
    # One should succeed, one should have conflict
    conflict_count = int(dut.bank_conflict[0].value) + int(dut.bank_conflict[1].value)
    assert conflict_count == 1, f"Expected exactly 1 conflict, got {conflict_count}"
    
    cocotb.log.info("Bank conflict detection test PASSED")


@cocotb.test()
async def test_tile_buffer_external_routing(dut):
    """Test that addresses outside SRAM region route to external"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    dut.sram_base.value = 0x00
    dut.sram_limit.value = 0x7F  # SRAM: 0x00-0x7F, External: 0x80+
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    # Access address in SRAM region
    dut.read_valid[0].value = 1
    dut.read_address[0].value = 0x10  # Within SRAM
    await RisingEdge(dut.clk)
    
    assert dut.external_read_valid[0].value == 0, "SRAM address should not route to external"
    dut.read_valid[0].value = 0
    await RisingEdge(dut.clk)

    # Access address in external region
    dut.read_valid[0].value = 1
    dut.read_address[0].value = 0x80  # External
    await RisingEdge(dut.clk)
    
    assert dut.external_read_valid[0].value == 1, "External address should route to external"
    assert dut.external_read_address[0].value == 0x80, "External address mismatch"
    
    cocotb.log.info("External routing test PASSED")
