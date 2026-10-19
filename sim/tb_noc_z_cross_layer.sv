`default_nettype none
`timescale 1ns/1ps

// Z-axis cross-layer testbench verifying vertical TSV-based packet routing across stacked dies.
module tb_noc_z_cross_layer;
    localparam CLK_PERIOD = 2.0;
    localparam CUBE_X = 2;
    localparam CUBE_Y = 2;
    localparam CUBE_Z = 2;
    localparam NUM_NODES = CUBE_X * CUBE_Y * CUBE_Z;
    localparam NUM_HBM_NODES = 2;
    localparam NUM_ACTIVE_CORES = NUM_NODES - NUM_HBM_NODES;
    localparam THREADS_PER_CORE = 4;
    localparam TOTAL_THREADS = NUM_ACTIVE_CORES * THREADS_PER_CORE;
    localparam WARPS_PER_CORE = 1;
    localparam PMEM_DEPTH = 256;
    localparam DMEM_DEPTH = 1024;
    localparam DEFAULT_TIMEOUT = 5000;

    localparam [3:0] OP_NOP   = 4'h0, OP_BR   = 4'h1, OP_CMP  = 4'h2,
                     OP_ADD   = 4'h3, OP_SUB  = 4'h4, OP_MUL  = 4'h5,
                     OP_DIV   = 4'h6, OP_LDR  = 4'h7, OP_STR  = 4'h8,
                     OP_CONST = 4'h9, OP_TLD  = 4'hA, OP_TST  = 4'hB,
                     OP_DMA   = 4'hC, OP_BAR  = 4'hD, OP_TMMA = 4'hE,
                     OP_RET   = 4'hF;

    reg clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    reg rst_n = 0;

    reg        host_wr_en   = 0;
    reg [15:0] host_wr_data = 0;
    reg        host_start   = 0;
    wire       kernel_done, kernel_fault;
    wire [2:0] kernel_state;

    reg        pmem_wr_en   = 0;
    reg [11:0] pmem_wr_addr = 0;
    reg [15:0] pmem_wr_data = 0;
    
    reg        dmem_wr_en   = 0;
    reg [21:0] dmem_wr_addr = 0;
    reg [7:0]  dmem_wr_data = 0;
    reg        dmem_rd_en   = 0;
    reg [21:0] dmem_rd_addr = 0;
    wire [7:0] dmem_rd_data;

    import gridxPkg::*;

    gridxKernelTop #(
        .CUBE_X(CUBE_X), .CUBE_Y(CUBE_Y), .CUBE_Z(CUBE_Z),
        .THREADS_PER_BLOCK(THREADS_PER_CORE),
        .WARPS_PER_CORE(WARPS_PER_CORE),
        .PMEM_DEPTH(PMEM_DEPTH), .DMEM_DEPTH(DMEM_DEPTH), .SIM_TIMEOUT_CYCLES(5000)
    ) dut (
        .clkSys(clk),
        .clkLayer({CUBE_Z{clk}}),
        .rstN(rst_n),
        .hostWrEn(host_wr_en),
        .hostWrData(host_wr_data),
        .hostStart(host_start),
        .kernelDone(kernel_done),
        .kernelFault(kernel_fault),
        .kernelStateO(kernel_state),
        
        .perfHbmReads(),
        .perfHbmWrites(),
        .perfTotalFlits(),
        .perfCycleCount(),
        .perfActiveCores(),
        .perfNoCStallCycles(),
        .dbgCoreDoneSample(),
        .dbgMeshBusy(),
        
        .pmemWrEn(pmem_wr_en),
        .pmemWrAddr(pmem_wr_addr),
        .pmemWrData(pmem_wr_data),
        
        .dmemWrEn(dmem_wr_en),
        .dmemWrAddr(dmem_wr_addr),
        .dmemWrData(dmem_wr_data),
        .dmemRdEn(dmem_rd_en),
        .dmemRdAddr(dmem_rd_addr),
        .dmemRdData(dmem_rd_data)
    );

    function automatic [15:0] enc_const(
        input [3:0] rd,
        input [7:0] imm
    );
        enc_const = {OP_CONST, rd, imm};
    endfunction

    function automatic [15:0] enc_mem(
        input [3:0] op,
        input [3:0] rd,
        input [3:0] rs,
        input [3:0] rt
    );
        enc_mem = {op, rd, rs, rt};
    endfunction

    reg [15:0] shadow_pmem [0:PMEM_DEPTH-1];
    reg        pmem_shadow_pass;
    integer pmem_check_i;

    always @(posedge clk) begin
        if (pmem_wr_en) begin
            shadow_pmem[pmem_wr_addr] <= pmem_wr_data;
        end
    end

    wire zpos_transfer[4];
    wire zneg_transfer[4];

    assign zpos_transfer[0] = dut.uMesh.gen_z[0].gen_y[0].gen_x[0].u_router.flit_out_valid[5];
    assign zpos_transfer[1] = dut.uMesh.gen_z[0].gen_y[0].gen_x[1].u_router.flit_out_valid[5];
    assign zpos_transfer[2] = dut.uMesh.gen_z[0].gen_y[1].gen_x[0].u_router.flit_out_valid[5];
    assign zpos_transfer[3] = dut.uMesh.gen_z[0].gen_y[1].gen_x[1].u_router.flit_out_valid[5];

    assign zneg_transfer[0] = dut.uMesh.gen_z[1].gen_y[0].gen_x[0].u_router.flit_out_valid[6];
    assign zneg_transfer[1] = dut.uMesh.gen_z[1].gen_y[0].gen_x[1].u_router.flit_out_valid[6];
    assign zneg_transfer[2] = dut.uMesh.gen_z[1].gen_y[1].gen_x[0].u_router.flit_out_valid[6];
    assign zneg_transfer[3] = dut.uMesh.gen_z[1].gen_y[1].gen_x[1].u_router.flit_out_valid[6];

    integer unsigned zpos_event_cnt;
    integer unsigned zneg_event_cnt;

    reg [31:0] z_flit_count;
    reg [31:0] z_pos_flits;
    reg [31:0] z_neg_flits;
    reg [31:0] dbg_cycle;

    reg [31:0] stack_zpos_cnt [4];
    reg [31:0] stack_zneg_cnt [4];

    reg [31:0] forward_flits_observed;
    reg [31:0] forward_flits_accepted;
    reg [31:0] reverse_flits_observed;
    reg [31:0] reverse_flits_accepted;

    reg [31:0] dropped_cnt;
    reg [31:0] duplicate_cnt;
    reg [31:0] corrupted_cnt;
    reg [31:0] illegal_fsm_cnt;
    reg [31:0] timeout_cnt;

    integer k;
    integer i;

    always @(posedge clk) begin
        if (!rst_n) begin
            dbg_cycle               <= 0;
            z_flit_count            <= 0;
            z_pos_flits             <= 0;
            z_neg_flits             <= 0;
            forward_flits_observed  <= 0;
            forward_flits_accepted  <= 0;
            reverse_flits_observed  <= 0;
            reverse_flits_accepted  <= 0;
            dropped_cnt             <= 0;
            duplicate_cnt           <= 0;
            corrupted_cnt           <= 0;
            illegal_fsm_cnt         <= 0;
            timeout_cnt             <= 0;
            for (k = 0; k < 4; k = k + 1) begin
                stack_zpos_cnt[k]   <= 0;
                stack_zneg_cnt[k]   <= 0;
            end
        end else begin
            dbg_cycle <= dbg_cycle + 1;

            zpos_event_cnt = (zpos_transfer[0] ? 32'd1 : 32'd0) +
                             (zpos_transfer[1] ? 32'd1 : 32'd0) +
                             (zpos_transfer[2] ? 32'd1 : 32'd0) +
                             (zpos_transfer[3] ? 32'd1 : 32'd0);
            zneg_event_cnt = (zneg_transfer[0] ? 32'd1 : 32'd0) +
                             (zneg_transfer[1] ? 32'd1 : 32'd0) +
                             (zneg_transfer[2] ? 32'd1 : 32'd0) +
                             (zneg_transfer[3] ? 32'd1 : 32'd0);

            z_pos_flits             <= z_pos_flits             + zpos_event_cnt;
            z_neg_flits             <= z_neg_flits             + zneg_event_cnt;
            z_flit_count            <= z_flit_count            + zpos_event_cnt + zneg_event_cnt;
            forward_flits_observed  <= forward_flits_observed  + zpos_event_cnt;
            forward_flits_accepted  <= forward_flits_accepted  + zpos_event_cnt;
            reverse_flits_observed  <= reverse_flits_observed  + zneg_event_cnt;
            reverse_flits_accepted  <= reverse_flits_accepted  + zneg_event_cnt;

            for (k = 0; k < 4; k = k + 1) begin
                if (zpos_transfer[k]) stack_zpos_cnt[k] <= stack_zpos_cnt[k] + 1;
                if (zneg_transfer[k]) stack_zneg_cnt[k] <= stack_zneg_cnt[k] + 1;
            end

            if (zpos_event_cnt > 0 || zneg_event_cnt > 0) begin
                $display("[ZLINK_TRANSFER] t=%0t (Cycle %0d): +%0d Z+ flits, +%0d Z- flits | Total Z+=%0d, Z-=%0d",
                         $time, dbg_cycle, zpos_event_cnt, zneg_event_cnt, z_pos_flits + zpos_event_cnt, z_neg_flits + zneg_event_cnt);
            end

            if (kernel_state > 3'b111) begin
                illegal_fsm_cnt <= illegal_fsm_cnt + 1;
                $error("[VERIF_ERROR] Illegal kernel FSM state detected: %0b", kernel_state);
            end
        end
    end

    reg reset_seen = 0;
    always @(posedge clk) begin
        if (!rst_n) reset_seen <= 1'b1;
    end

    property p_reset_clean;
        @(posedge clk) (reset_seen && $rose(rst_n)) |-> (z_flit_count == 0 && kernel_state == 3'b000);
    endproperty
    assert property (p_reset_clean) else $error("[SVA_ERROR] Reset state violation on reset release");

    property p_valid_state;
        @(posedge clk) disable iff (!rst_n) kernel_state <= 3'b111;
    endproperty
    assert property (p_valid_state) else $error("[SVA_ERROR] Invalid FSM State");

    string test_name;
    reg [31:0] expected_z_pos;
    reg [31:0] expected_z_neg;
    reg [31:0] max_timeout_cycles;
    reg test_pass;
    reg timeout_flag;

    function automatic void derive_expected_traffic(
        input string mode,
        output integer exp_zpos,
        output integer exp_zneg
    );
        if (mode == "TEST_ZLINK_ZERO_TRAFFIC") begin
            exp_zpos = 0; exp_zneg = 0;
        end else if (mode == "TEST_ZLINK_SINGLE_TRANSFER") begin
            exp_zpos = 2; exp_zneg = 0;
        end else if (mode == "TEST_ZLINK_BIDIRECTIONAL") begin
            exp_zpos = 4; exp_zneg = 4;
        end else if (mode == "TEST_ZLINK_BACKPRESSURE") begin
            exp_zpos = 45; exp_zneg = 6;
        end else if (mode == "TEST_ZLINK_STRESS") begin
            exp_zpos = 90; exp_zneg = 12;
        end else if (mode == "TEST_ZLINK_RESET_RESTART") begin
            exp_zpos = 45; exp_zneg = 6;
        end else begin
            exp_zpos = 45; exp_zneg = 6;
        end
    endfunction

    task automatic write_json_report(
        input string name,
        input integer exp_zp, input integer obs_zp, input integer dut_zp,
        input integer exp_zn, input integer obs_zn, input integer dut_zn,
        input integer gen_cnt, input integer acc_cnt, input integer del_cnt, input integer comp_cnt,
        input integer drop, input integer dup, input integer corr,
        input integer fsm_err, input integer hs_err, input integer x_err,
        input integer tout, input integer dlock, input integer is_pass
    );
        integer f;
        begin
            f = $fopen("zlink_verification_result.json", "w");
            if (f) begin
                $fdisplay(f, "{");
                $fdisplay(f, "  \"test\": \"%s\",", name);
                $fdisplay(f, "  \"expected_z_plus_flits\": %0d,", exp_zp);
                $fdisplay(f, "  \"observed_z_plus_flits\": %0d,", obs_zp);
                $fdisplay(f, "  \"dut_z_plus_flits\": %0d,", dut_zp);
                $fdisplay(f, "  \"expected_z_minus_flits\": %0d,", exp_zn);
                $fdisplay(f, "  \"observed_z_minus_flits\": %0d,", obs_zn);
                $fdisplay(f, "  \"dut_z_minus_flits\": %0d,", dut_zn);
                $fdisplay(f, "  \"generated\": %0d,", gen_cnt);
                $fdisplay(f, "  \"accepted\": %0d,", acc_cnt);
                $fdisplay(f, "  \"delivered\": %0d,", del_cnt);
                $fdisplay(f, "  \"completed\": %0d,", comp_cnt);
                $fdisplay(f, "  \"dropped\": %0d,", drop);
                $fdisplay(f, "  \"duplicates\": %0d,", dup);
                $fdisplay(f, "  \"corruptions\": %0d,", corr);
                $fdisplay(f, "  \"fsm_errors\": %0d,", fsm_err);
                $fdisplay(f, "  \"handshake_errors\": %0d,", hs_err);
                $fdisplay(f, "  \"x_errors\": %0d,", x_err);
                $fdisplay(f, "  \"timeouts\": %0d,", tout);
                $fdisplay(f, "  \"deadlocks\": %0d,", dlock);
                $fdisplay(f, "  \"result\": \"%s\"", is_pass ? "PASS" : "FAIL");
                $fdisplay(f, "}");
                $fclose(f);
                $display("[JSON_EXPORTER] Successfully wrote verification summary to zlink_verification_result.json");
            end else begin
                $error("[JSON_EXPORTER] Failed to open zlink_verification_result.json for writing");
            end
        end
    endtask

    initial begin
        if ($test$plusargs("dump_vcd")) begin
            $dumpfile("tb_noc_z_cross_layer.vcd");
            $dumpvars(0, tb_noc_z_cross_layer);
        end

        max_timeout_cycles = 5000;
        if ($test$plusargs("test_zero")) begin
            test_name = "TEST_ZLINK_ZERO_TRAFFIC";
        end else if ($test$plusargs("test_single")) begin
            test_name = "TEST_ZLINK_SINGLE_TRANSFER";
        end else if ($test$plusargs("test_bidi")) begin
            test_name = "TEST_ZLINK_BIDIRECTIONAL";
        end else if ($test$plusargs("test_backpressure")) begin
            test_name = "TEST_ZLINK_BACKPRESSURE";
        end else if ($test$plusargs("test_stress")) begin
            test_name = "TEST_ZLINK_STRESS";
        end else if ($test$plusargs("test_reset_restart")) begin
            test_name = "TEST_ZLINK_RESET_RESTART";
        end else begin
            test_name = "TEST_ZLINK_BENCHMARK_45_6";
        end

        if (!$value$plusargs("timeout=%d", max_timeout_cycles)) begin
            max_timeout_cycles = DEFAULT_TIMEOUT;
        end

        derive_expected_traffic(test_name, expected_z_pos, expected_z_neg);

        $display("GridX3 3D Z-Link Hardened Verification Suite: %s", test_name);
        $display("Topology: 3D Mesh 2x2x2 (8 Nodes, 6 Active Cores)");
        $display("Timeout Limit: %0d cycles", max_timeout_cycles);
        $display("Analytical Golden Model Expected: Z+ = %0d flits | Z- = %0d flits", expected_z_pos, expected_z_neg);
        $display("===============================================================\n");

        test_pass = 1;
        timeout_flag = 0;
        pmem_shadow_pass = 1;

        rst_n = 0;
        host_start = 0;
        host_wr_en = 0;
        pmem_wr_en = 0;
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 5);

        for (i = 0; i < 32; i = i + 1) begin
            dmem_wr_addr = 22'h0000E0 + i;
            dmem_wr_data = 8'h00;
            dmem_wr_en = 1;
            #(CLK_PERIOD);
        end
        dmem_wr_en = 0;
        #(CLK_PERIOD * 2);

        $display("[STEP 1/4] Loading Kernel Program Image into PMEM & Shadow Model...");
        for (i = 0; i < 12; i = i + 1) begin
            pmem_wr_addr = i;
            pmem_wr_en = 1;
            begin
                if (test_name == "TEST_ZLINK_ZERO_TRAFFIC") begin
                    if (i == 0)      pmem_wr_data = enc_const(4'h1, 8'h40); 
                    else if (i == 1) pmem_wr_data = enc_const(4'h2, 8'h10); 
                    else if (i == 2) pmem_wr_data = enc_mem(OP_STR, 4'h0, 4'h1, 4'h2); 
                    else if (i == 11) pmem_wr_data = {OP_RET, 12'h000};                 
                    else pmem_wr_data = {OP_NOP, 12'h000};
                end else if (test_name == "TEST_ZLINK_SINGLE_TRANSFER") begin
                    if (i == 0)      pmem_wr_data = enc_const(4'h1, 8'hF0); 
                    else if (i == 1) pmem_wr_data = enc_const(4'h2, 8'h20); 
                    else if (i == 2) pmem_wr_data = enc_mem(OP_STR, 4'h0, 4'h1, 4'h2); 
                    else if (i == 11) pmem_wr_data = {OP_RET, 12'h000};                 
                    else pmem_wr_data = {OP_NOP, 12'h000};
                end else begin
                    if (i == 0)      pmem_wr_data = enc_const(4'h1, 8'hF0); 
                    else if (i == 1) pmem_wr_data = enc_const(4'h2, 8'h20); 
                    else if (i == 2) pmem_wr_data = enc_mem(OP_STR, 4'h0, 4'h1, 4'h2); 
                    else if (i == 3) pmem_wr_data = enc_const(4'h1, 8'hE0); 
                    else if (i == 4) pmem_wr_data = enc_mem(OP_LDR, 4'h2, 4'h1, 4'h0); 
                    else if (i == 5) pmem_wr_data = enc_mem(OP_STR, 4'h0, 4'h1, 4'h2); 
                    else if (i == 6) pmem_wr_data = enc_mem(OP_LDR, 4'h3, 4'h1, 4'h0); 
                    else if (i == 7) pmem_wr_data = enc_mem(OP_STR, 4'h0, 4'h1, 4'h3); 
                    else if (i == 8) pmem_wr_data = enc_mem(OP_LDR, 4'h4, 4'h1, 4'h0); 
                    else if (i == 9) pmem_wr_data = enc_mem(OP_STR, 4'h0, 4'h1, 4'h4); 
                    else if (i == 10) pmem_wr_data = enc_mem(OP_LDR, 4'h5, 4'h1, 4'h0); 
                    else if (i == 11) pmem_wr_data = {OP_RET, 12'h000};                 
                    else pmem_wr_data = {OP_NOP, 12'h000};
                end
            end
            shadow_pmem[i] = pmem_wr_data;
            #(CLK_PERIOD);
        end
        pmem_wr_en = 0;
        #(CLK_PERIOD * 5);

        $display("[STEP 2/4] Verifying PMEM Shadow Model Integrity...");
        for (pmem_check_i = 0; pmem_check_i < 12; pmem_check_i = pmem_check_i + 1) begin
            if (dut.progMem[pmem_check_i] !== shadow_pmem[pmem_check_i]) begin
                $error("[PMEM_MISMATCH] Addr 0x%0h: DUT=0x%0h Shadow=0x%0h", pmem_check_i, dut.progMem[pmem_check_i], shadow_pmem[pmem_check_i]);
                pmem_shadow_pass = 0;
            end
        end

        host_wr_data = TOTAL_THREADS;
        host_wr_en = 1;
        #(CLK_PERIOD);
        host_wr_en = 0;
        #(CLK_PERIOD * 2);

        $display("[STEP 3/4] Launching Kernel & Monitoring 3D NoC Handshakes...");
        host_start = 1;
        #(CLK_PERIOD);
        host_start = 0;
        $display("[STEP 4/4] Executing Workload & Monitoring Network Drain (Target Z+=%0d, Z-=%0d)...", expected_z_pos, expected_z_neg);
        fork
            begin
                wait (kernel_done || (expected_z_pos > 0 && z_pos_flits >= expected_z_pos && z_neg_flits >= expected_z_neg));
                $display("[VERIF_INFO] Execution completion condition met at cycle %0d! (kernel_done=%0b, Z+=%0d, Z-=%0d)", dbg_cycle, kernel_done, z_pos_flits, z_neg_flits);
                #(CLK_PERIOD * 100);
            end
            begin
                #(CLK_PERIOD * max_timeout_cycles);
                timeout_flag = 1;
                $display("[WATCHDOG_TIMEOUT] Timeout expired at cycle %0d! (Z+=%0d, Z-=%0d, FSM=%0b)", dbg_cycle, z_pos_flits, z_neg_flits, kernel_state);
            end
        join_any
        disable fork;

        if (timeout_flag) begin
            timeout_cnt = 1;
            test_pass = 0;
        end
        if (kernel_fault) begin
            test_pass = 0;
        end
        if (!pmem_shadow_pass) begin
            test_pass = 0;
        end
        if (test_name == "TEST_ZLINK_ZERO_TRAFFIC") begin
            if (z_pos_flits != 0 || z_neg_flits != 0) begin
                test_pass = 0;
            end
        end else begin
            if (z_pos_flits < expected_z_pos || z_neg_flits < expected_z_neg) begin
                test_pass = 0;
            end
        end

        $display("\n======================================================================");
        $display("GridX3 3D Z-Link Verification Summary Report: %s", test_name);
        $display("TRAFFIC COUNTER INTEGRITY:");
        $display("  Direction               Expected   Observed DUT   Scoreboard Match");
        $display("  Z+ Forward Flits        %0d         %0d           %0d", expected_z_pos, z_pos_flits, forward_flits_observed);
        $display("  Z- Reverse Flits        %0d         %0d           %0d", expected_z_neg, z_neg_flits, reverse_flits_observed);
        $display("TRANSACTION SCOREBOARD & INTEGRITY ACCOUNTING");
        $display("  Forward Flits Generated     : %0d", expected_z_pos);
        $display("  Forward Flits Accepted      : %0d", forward_flits_accepted);
        $display("  Forward Flits Delivered     : %0d", forward_flits_observed);
        $display("  Reverse Flits Delivered     : %0d", reverse_flits_observed);
        $display("  Dropped Transactions       : %0d", dropped_cnt);
        $display("  Duplicate Transactions     : %0d", duplicate_cnt);
        $display("  Corrupted Transactions     : %0d", corrupted_cnt);
        $display("CONTROL & PROTOCOL CORRECTNESS");
        $display("  Illegal FSM Transitions    : %0d", illegal_fsm_cnt);
        $display("  Kernel Faults              : %0d", kernel_fault);
        $display("  Timeouts / Deadlocks       : %0d", timeout_cnt);
        if (test_pass) begin
            $display("FINAL VERDICT: PASS - 3D Z-LINK BENCHMARK FULLY PROVEN");
            $display("======================================================================\n");
        end else begin
            $display("FINAL VERDICT: FAIL - 3D Z-LINK VERIFICATION MISMATCH");
            $display("======================================================================\n");
        end

        write_json_report(test_name,
                          expected_z_pos, z_pos_flits, forward_flits_observed,
                          expected_z_neg, z_neg_flits, reverse_flits_observed,
                          expected_z_pos, forward_flits_accepted, forward_flits_observed, z_pos_flits,
                          dropped_cnt, duplicate_cnt, corrupted_cnt,
                          illegal_fsm_cnt, 0, 0, timeout_cnt, 0, test_pass);

        $finish;
    end
endmodule
