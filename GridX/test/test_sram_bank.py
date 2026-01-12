import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock

@cocotb.test()
async def test_sram_bank_basic(dut):
    """Test basic read/write operations on SRAM bank"""
    # Setup clock
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    dut.enable.value = 0
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    dut.enable.value = 1
    await RisingEdge(dut.clk)

    # Test write
    dut.write_valid.value = 1
    dut.write_address.value = 0x10
    dut.write_data.value = 0xDEADBEEF12345678
    await RisingEdge(dut.clk)
    
    assert dut.write_ready.value == 1, "Write should complete in 1 cycle"
    dut.write_valid.value = 0
    await RisingEdge(dut.clk)

    # Test read
    dut.read_valid.value = 1
    dut.read_address.value = 0x10
    await RisingEdge(dut.clk)
    
    assert dut.read_ready.value == 1, "Read should complete in 1 cycle"
    assert dut.read_data.value == 0xDEADBEEF12345678, f"Read data mismatch: {hex(dut.read_data.value)}"
    dut.read_valid.value = 0
    
    cocotb.log.info("SRAM bank basic test PASSED")


@cocotb.test()
async def test_sram_bank_power_gating(dut):
    """Test power gating behavior of SRAM bank"""
    # Setup clock
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    dut.enable.value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    # Write data while enabled
    dut.write_valid.value = 1
    dut.write_address.value = 0x20
    dut.write_data.value = 0xCAFEBABE
    await RisingEdge(dut.clk)
    dut.write_valid.value = 0
    await RisingEdge(dut.clk)

    # Disable bank (power gate)
    dut.enable.value = 0
    dut.read_valid.value = 1
    dut.read_address.value = 0x20
    await RisingEdge(dut.clk)
    
    # Should not respond when disabled
    assert dut.read_ready.value == 0, "Bank should not respond when power gated"
    
    # Re-enable
    dut.enable.value = 1
    await RisingEdge(dut.clk)
    
    # Now should respond
    assert dut.read_ready.value == 1, "Bank should respond when enabled"
    # Note: In simulation, data is retained. Real power gating would lose data.
    
    cocotb.log.info("SRAM bank power gating test PASSED")


@cocotb.test()
async def test_sram_bank_concurrent_access(dut):
    """Test simultaneous read and write to different addresses"""
    # Setup clock
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    dut.enable.value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    # Write initial data
    dut.write_valid.value = 1
    dut.write_address.value = 0x30
    dut.write_data.value = 0x1111111111111111
    await RisingEdge(dut.clk)
    dut.write_valid.value = 0
    await RisingEdge(dut.clk)

    # Simultaneous read (0x30) and write (0x31)
    dut.read_valid.value = 1
    dut.read_address.value = 0x30
    dut.write_valid.value = 1
    dut.write_address.value = 0x31
    dut.write_data.value = 0x2222222222222222
    await RisingEdge(dut.clk)

    assert dut.read_ready.value == 1, "Read should succeed"
    assert dut.write_ready.value == 1, "Write should succeed"
    assert dut.read_data.value == 0x1111111111111111, "Read data mismatch"

    dut.read_valid.value = 0
    dut.write_valid.value = 0
    await RisingEdge(dut.clk)

    # Verify second write
    dut.read_valid.value = 1
    dut.read_address.value = 0x31
    await RisingEdge(dut.clk)
    assert dut.read_data.value == 0x2222222222222222, "Second location data mismatch"

    cocotb.log.info("SRAM bank concurrent access test PASSED")
