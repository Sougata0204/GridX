// HBM3 Controller Stress Testbench
// exercises hbm3_ctrl directly with reads, writes, row hits, row misses
// and verifies all performance counters increment correctly

`default_nettype none
`timescale 1ns/1ns

module tb_hbm3_stress;

    reg clk = 0;
    always #2.5 clk = ~clk; // 4 GHz

    reg reset = 1;

    // request interface
    reg                    req_valid = 0;
    reg [31:0]             req_addr = 0;
    reg [511:0]            req_wdata = 0;
    reg                    req_write = 0;
    wire                   req_ready;

    // response interface
    wire                   resp_valid;
    wire [511:0]           resp_data;
    wire [31:0]            resp_addr;

    // phy interface
    wire [1:0]             phy_stack_sel;
    wire                   phy_channel_sel;
    wire [13:0]            phy_row_addr;
    wire [5:0]             phy_col_addr;
    wire [4:0]             phy_bank_addr;
    wire                   phy_activate;
    wire                   phy_read;
    wire                   phy_write_cmd;
    wire                   phy_precharge;
    wire [511:0]           phy_write_data;

    // phy read model
    reg [511:0]            phy_read_data = 0;
    reg                    phy_read_valid = 0;

    // perf counters
    wire [31:0]            total_reads;
    wire [31:0]            total_writes;
    wire [31:0]            row_hits;
    wire [31:0]            row_misses;
    wire                   controller_busy;

    hbm3_ctrl #(
        .NUM_STACKS(4),
        .CHANNELS_PER_STACK(2),
        .ADDR_WIDTH(32),
        .DATA_WIDTH(512),
        .ROW_BITS(14),
        .COL_BITS(6),
        .BANK_BITS(5),
        .tRCD(3),
        .tRP(3),
        .tCL(4),
        .tWR(3),
        .tRRD(2)
    ) dut (
        .clk(clk), .reset(reset),
        .req_valid(req_valid),
        .req_addr(req_addr),
        .req_wdata(req_wdata),
        .req_write(req_write),
        .req_ready(req_ready),
        .resp_valid(resp_valid),
        .resp_data(resp_data),
        .resp_addr(resp_addr),
        .phy_stack_sel(phy_stack_sel),
        .phy_channel_sel(phy_channel_sel),
        .phy_row_addr(phy_row_addr),
        .phy_col_addr(phy_col_addr),
        .phy_bank_addr(phy_bank_addr),
        .phy_activate(phy_activate),
        .phy_read(phy_read),
        .phy_write_cmd(phy_write_cmd),
        .phy_precharge(phy_precharge),
        .phy_write_data(phy_write_data),
        .phy_read_data(phy_read_data),
        .phy_read_valid(phy_read_valid),
        .total_reads(total_reads),
        .total_writes(total_writes),
        .row_hits(row_hits),
        .row_misses(row_misses),
        .controller_busy(controller_busy)
    );

    // PHY read model: return data 1 cycle after phy_read
    always @(posedge clk) begin
        if (reset) begin
            phy_read_valid <= 0;
            phy_read_data <= 0;
        end else begin
            phy_read_valid <= phy_read;
            if (phy_read)
                phy_read_data <= {16{32'hDEAD_BEEF}};
        end
    end

    integer tests_passed = 0;
    integer tests_failed = 0;

    task check(input integer cond, input [8*80-1:0] msg);
        if (cond) begin
            tests_passed = tests_passed + 1;
            $display("  [PASS] %0s", msg);
        end else begin
            tests_failed = tests_failed + 1;
            $display("  [FAIL] %0s", msg);
        end
    endtask

    // Wait for controller to be idle (not busy), then submit request
    // The HBM FSM accepts req_valid when in HBM_IDLE (controller_busy == 0)
    task submit_and_complete(input [31:0] addr, input is_write, input [511:0] wdata);
        integer timeout;
        // Wait until controller is idle
        timeout = 0;
        while (controller_busy && timeout < 500) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        // Present request for one cycle (controller sees it in IDLE and transitions)
        @(posedge clk);
        req_valid <= 1;
        req_addr <= addr;
        req_write <= is_write;
        req_wdata <= wdata;
        @(posedge clk);
        req_valid <= 0;
        // Wait for controller to finish processing
        timeout = 0;
        while (controller_busy && timeout < 500) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        // Extra settle cycle
        @(posedge clk);
    endtask

    integer i;
    reg [31:0] saved_reads, saved_writes, saved_hits, saved_misses;

    initial begin
        $display("[TB_HBM3_STRESS] GridX3 HBM3 Controller Stress Verification");
        $display("[TB_HBM3_STRESS] Clock: 4 GHz (250 ps period)");
        $display("");

        // reset
        reset = 1;
        repeat (10) @(posedge clk);
        reset = 0;
        repeat (5) @(posedge clk);

        $display("[TB_HBM3_STRESS] Test 1: Single Write");
        saved_writes = total_writes;
        submit_and_complete(32'h0000_0040, 1, {16{32'hCAFE_BABE}});
        check(total_writes == saved_writes + 1, "total_writes incremented by 1");
        $display("    total_reads=%0d total_writes=%0d", total_reads, total_writes);

        $display("[TB_HBM3_STRESS] Test 2: Single Read");
        saved_reads = total_reads;
        submit_and_complete(32'h0000_0040, 0, 512'd0);
        check(total_reads == saved_reads + 1, "total_reads incremented by 1");
        $display("    total_reads=%0d total_writes=%0d", total_reads, total_writes);

        $display("[TB_HBM3_STRESS] Test 3: Row Hit Test");
        submit_and_complete(32'h0010_0000, 1, {16{32'h1111_1111}});
        saved_hits = row_hits;
        submit_and_complete(32'h0010_0001, 1, {16{32'h2222_2222}});
        check(row_hits > saved_hits, "row_hits incremented on same-row access");
        $display("    row_hits=%0d row_misses=%0d", row_hits, row_misses);

        $display("[TB_HBM3_STRESS] Test 4: Row Miss Test");
        submit_and_complete(32'h0020_0000, 1, {16{32'h3333_3333}});
        saved_misses = row_misses;
        submit_and_complete(32'h0020_0040, 1, {16{32'h4444_4444}});
        check(row_misses > saved_misses, "row_misses incremented on different-row access");
        $display("    row_hits=%0d row_misses=%0d", row_hits, row_misses);

        $display("[TB_HBM3_STRESS] Test 5: Burst Write Stress (8 writes)");
        saved_writes = total_writes;
        for (i = 0; i < 8; i = i + 1) begin
            submit_and_complete(32'h0002_0000 + i, 1, {16{i[31:0]}});
        end
        check(total_writes == saved_writes + 8, "8 burst writes completed");
        $display("    total_writes=%0d", total_writes);

        $display("[TB_HBM3_STRESS] Test 6: Burst Read Stress (8 reads)");
        saved_reads = total_reads;
        for (i = 0; i < 8; i = i + 1) begin
            submit_and_complete(32'h0003_0000 + i, 0, 512'd0);
        end
        check(total_reads == saved_reads + 8, "8 burst reads completed");
        $display("    total_reads=%0d", total_reads);

        $display("[TB_HBM3_STRESS] Test 7: Mixed Read/Write Interleave");
        saved_reads = total_reads;
        saved_writes = total_writes;
        for (i = 0; i < 4; i = i + 1) begin
            submit_and_complete(32'h0004_0000 + i, 1, {16{(i[31:0] + 100)}});
            submit_and_complete(32'h0004_0000 + i, 0, 512'd0);
        end
        check(total_reads == saved_reads + 4, "4 interleaved reads completed");
        check(total_writes == saved_writes + 4, "4 interleaved writes completed");
        $display("    total_reads=%0d total_writes=%0d", total_reads, total_writes);

        $display("[TB_HBM3_STRESS] Test 8: Controller Idle Check");
        repeat (20) @(posedge clk);
        check(controller_busy == 0, "controller returns to IDLE");

        $display("[TB_HBM3_STRESS] Test 9: Counter Non-Zero Verification");
        check(total_reads > 0, "total_reads > 0 (HBM read path exercised)");
        check(total_writes > 0, "total_writes > 0 (HBM write path exercised)");
        check(row_hits + row_misses > 0, "row tracking active");

        // summary
        $display("[TB_HBM3_STRESS] Reads: %0d | Writes: %0d | Row Hits: %0d | Row Misses: %0d", total_reads, total_writes, row_hits, row_misses);
        $display("[TB_HBM3_STRESS] Total Tests: %0d | Passed: %0d | Failed: %0d", tests_passed + tests_failed, tests_passed, tests_failed);

        if (tests_failed == 0)
            $display("[TB_HBM3_STRESS] RESULT: ALL TESTS PASSED -- HBM3 PATH FULLY EXERCISED");
        else
            $display("[TB_HBM3_STRESS] RESULT: %0d TESTS FAILED", tests_failed);

        $finish;
    end

    // Watchdog
    integer wd = 0;
    always @(posedge clk) begin
        wd <= wd + 1;
        if (wd > 50000) begin
            $display("[TB_HBM3_STRESS] WATCHDOG TIMEOUT at %0d cycles", wd);
            $display("[TB_HBM3_STRESS] total_reads=%0d total_writes=%0d busy=%0b",
                     total_reads, total_writes, controller_busy);
            $finish;
        end
    end

endmodule
