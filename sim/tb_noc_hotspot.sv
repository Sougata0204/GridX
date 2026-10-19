`default_nettype none
`timescale 1ns/1ps

// NoC hotspot testbench injecting concentrated traffic patterns to verify router backpressure and fairness.
module tb_noc_hotspot;
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
    localparam TIMEOUT = 200000;

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
        .PMEM_DEPTH(PMEM_DEPTH), .DMEM_DEPTH(DMEM_DEPTH), .SIM_TIMEOUT_CYCLES(TIMEOUT)
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

    function [15:0] enc_const(
        input [3:0] rd,
        input [7:0] imm
    );
        enc_const = {OP_CONST, rd, imm};
    endfunction

    function [15:0] enc_mem(
        input [3:0] op,
        input [3:0] rd,
        input [3:0] rs,
        input [3:0] rt
    );
        enc_mem = {op, rd, rs, rt};
    endfunction

    reg timeout_flag;

    reg [31:0] dbg_cycle;
    always @(posedge clk) begin
        if (!rst_n) dbg_cycle <= 0;
        else dbg_cycle <= dbg_cycle + 1;
    end

    always @(posedge clk) begin
        if (dbg_cycle > 20 && dbg_cycle < 10000) begin
            if (dut.dmRdValid[0])
                $display("[DBG %0d] Core0 dmRdValid addr=0x%0x", dbg_cycle, dut.dmRdAddr[0]);
            if (dut.dmWrValid[0])
                $display("[DBG %0d] Core0 dmWrValid addr=0x%0x data=0x%0x", dbg_cycle, dut.dmWrAddr[0], dut.dmWrData[0]);
            if (dut.dmRdReady[0])
                $display("[DBG %0d] Core0 dmRdReady data=0x%0x", dbg_cycle, dut.dmRdData[0]);
            if (dut.dmWrReady[0])
                $display("[DBG %0d] Core0 dmWrReady", dbg_cycle);
            if (dut.meshBrRdValid[0])
                $display("[DBG %0d] Core0 meshBrRdValid addr=0x%0x", dbg_cycle, dut.meshBrRdAddr[0]);
            if (dut.meshBrRdReady[0])
                $display("[DBG %0d] Core0 meshBrRdReady data=0x%0x", dbg_cycle, dut.meshBrRdData[0]);
            for (integer i=0; i<8; i=i+1) begin
                if (dut.meshFlitInValid[i])
                    $display("[DBG %0d] meshFlitInValid[%0d] type=%0d vc=%0d src=%0d dest=%0d tag=%0d", dbg_cycle, i,
                        dut.meshFlitIn[i].flit_type, dut.meshFlitIn[i].vc_id,
                        dut.meshFlitIn[i].data[250:245], dut.meshFlitIn[i].data[116:111], dut.meshFlitIn[i].data[125:121]);
                if (dut.meshFlitOutValid[i])
                    $display("[DBG %0d] meshFlitOutValid[%0d] type=%0d vc=%0d src=%0d dest=%0d tag=%0d", dbg_cycle, i,
                        dut.meshFlitOut[i].flit_type, dut.meshFlitOut[i].vc_id,
                        dut.meshFlitOut[i].data[250:245], dut.meshFlitOut[i].data[116:111], dut.meshFlitOut[i].data[125:121]);
            end
        end
    end

    always @(posedge clk) begin
        if (dbg_cycle > 350 && dbg_cycle < 500) begin
            $display("[RTR %0d] Node(1,1,1) LOCAL vc2: fifo=%0d, ds_cred[YNEG][2]=%0d, ds_cred[LOCAL][2]=%0d, ovc_YNEG_vc2=%0d",
                dbg_cycle,
                dut.uMesh.gen_z[1].gen_y[1].gen_x[1].u_router.fifo_count[0][2],
                dut.uMesh.gen_z[1].gen_y[1].gen_x[1].u_router.downstream_credits[4][2],
                dut.uMesh.gen_z[1].gen_y[1].gen_x[1].u_router.downstream_credits[0][2],
                dut.uMesh.gen_z[1].gen_y[1].gen_x[1].u_router.ovc_state[4][2]);
            $display("[RTR %0d] Node(1,0,1) YPOS_vc2: fifo=%0d, ds_cred[ZNEG][2]=%0d, ovc_ZNEG_vc2=%0d",
                dbg_cycle,
                dut.uMesh.gen_z[1].gen_y[0].gen_x[1].u_router.fifo_count[3][2],
                dut.uMesh.gen_z[1].gen_y[0].gen_x[1].u_router.downstream_credits[6][2],
                dut.uMesh.gen_z[1].gen_y[0].gen_x[1].u_router.ovc_state[6][2]);
            $display("[RTR %0d] Node(1,0,0) ZPOS_vc2: fifo=%0d, ds_cred[LOCAL][2]=%0d, ovc_LOCAL_vc2=%0d",
                dbg_cycle,
                dut.uMesh.gen_z[0].gen_y[0].gen_x[1].u_router.fifo_count[5][2],
                dut.uMesh.gen_z[0].gen_y[0].gen_x[1].u_router.downstream_credits[0][2],
                dut.uMesh.gen_z[0].gen_y[0].gen_x[1].u_router.ovc_state[0][2]);

            $display("[REQ %0d] Node(0,0,0) LOCAL_vc0: fifo=%0d, ds_cred[XPOS]=%0d, ovc_XPOS=%0d",
                dbg_cycle,
                dut.uMesh.gen_z[0].gen_y[0].gen_x[0].u_router.fifo_count[0][0],
                dut.uMesh.gen_z[0].gen_y[0].gen_x[0].u_router.downstream_credits[1][0],
                dut.uMesh.gen_z[0].gen_y[0].gen_x[0].u_router.ovc_state[1][0]);
            $display("[REQ %0d] Node(1,0,0) XNEG_vc0: fifo=%0d, ds_cred[YPOS]=%0d, ovc_YPOS=%0d, lck=%0d, s1v=%0d, s1r=%0d, s2r=%b, vac=%b, s2v=%0d",
                dbg_cycle,
                dut.uMesh.gen_z[0].gen_y[0].gen_x[1].u_router.fifo_count[2][0],
                dut.uMesh.gen_z[0].gen_y[0].gen_x[1].u_router.downstream_credits[3][0],
                dut.uMesh.gen_z[0].gen_y[0].gen_x[1].u_router.ovc_state[3][0], dut.uMesh.gen_z[0].gen_y[0].gen_x[1].u_router.ovc_lock_in_port[3][0], dut.uMesh.gen_z[0].gen_y[0].gen_x[1].u_router.s1_valid[2][0], dut.uMesh.gen_z[0].gen_y[0].gen_x[1].u_router.s1_ready[2][0], dut.uMesh.gen_z[0].gen_y[0].gen_x[1].u_router.s2_ready[2][0], dut.uMesh.gen_z[0].gen_y[0].gen_x[1].u_router.va_grant_comb[2][0], dut.uMesh.gen_z[0].gen_y[0].gen_x[1].u_router.s2_va_grant[2][0]);
            $display("[REQ %0d] Node(1,1,0) YNEG_vc0: fifo=%0d, ds_cred[ZPOS]=%0d, ovc_ZPOS=%0d, lck=%0d, s1v=%0d, s1r=%0d, s2r=%b, vac=%b, s2v=%0d, s1_out=%0d, is_head=%0d, bf0=%0d, bf1=%0d, bf2=%0d, bf3=%0d",
                dbg_cycle,
                dut.uMesh.gen_z[0].gen_y[1].gen_x[1].u_router.fifo_count[6][0],
                dut.uMesh.gen_z[0].gen_y[1].gen_x[1].u_router.downstream_credits[5][0],
                dut.uMesh.gen_z[0].gen_y[1].gen_x[1].u_router.ovc_state[5][0], dut.uMesh.gen_z[0].gen_y[1].gen_x[1].u_router.ovc_lock_in_port[5][0], dut.uMesh.gen_z[0].gen_y[1].gen_x[1].u_router.s1_valid[6][0], dut.uMesh.gen_z[0].gen_y[1].gen_x[1].u_router.s1_ready[6][0], dut.uMesh.gen_z[0].gen_y[1].gen_x[1].u_router.s2_ready[6][0], dut.uMesh.gen_z[0].gen_y[1].gen_x[1].u_router.va_grant_comb[6][0], dut.uMesh.gen_z[0].gen_y[1].gen_x[1].u_router.s2_va_grant[6][0], dut.uMesh.gen_z[0].gen_y[1].gen_x[1].u_router.s1_out_port[6][0], dut.uMesh.gen_z[0].gen_y[1].gen_x[1].u_router.s1_is_head[6][0], dut.uMesh.gen_z[1].gen_y[1].gen_x[1].u_router.fifo_count[6][0], dut.uMesh.gen_z[0].gen_y[1].gen_x[1].u_router.buffer_data[4][0][0].flit_type, dut.uMesh.gen_z[0].gen_y[1].gen_x[1].u_router.buffer_data[4][0][1].flit_type, dut.uMesh.gen_z[0].gen_y[1].gen_x[1].u_router.buffer_data[4][0][2].flit_type, dut.uMesh.gen_z[0].gen_y[1].gen_x[1].u_router.buffer_data[4][0][3].flit_type);
            $display("[CDC %0d] Node(1,1,1)->(1,1,0) CDC: wrEn=%b wrVc=%0d rdEmpty=%b rdEn=%b rdVc=%0d ds_cred_zpos=%0d", 
                dbg_cycle, 
                dut.uMesh.gen_z[0].gen_y[1].gen_x[1].link_zp_gals.u_zp_fwd.u_credit_fifo.wrEn, 
                dut.uMesh.gen_z[0].gen_y[1].gen_x[1].link_zp_gals.u_zp_fwd.u_credit_fifo.wrData, 
                dut.uMesh.gen_z[0].gen_y[1].gen_x[1].link_zp_gals.u_zp_fwd.u_credit_fifo.rdEmpty, 
                dut.uMesh.gen_z[0].gen_y[1].gen_x[1].link_zp_gals.u_zp_fwd.u_credit_fifo.rdEn, 
                dut.uMesh.gen_z[0].gen_y[1].gen_x[1].link_zp_gals.u_zp_fwd.u_credit_fifo.rdData, 
                dut.uMesh.gen_z[0].gen_y[1].gen_x[1].u_router.downstream_credits[5][0]);
            $display("[N111 %0d] Node(1,1,1) ZNEG_vc0: fifo=%0d, ds_cred[LOCAL]=%0d, ovc_LOCAL=%0d, lck=%0d, s1v=%0d, s1r=%0d, s2r=%b, vac=%b, s2v=%0d",
                dbg_cycle,
                dut.uMesh.gen_z[1].gen_y[1].gen_x[1].u_router.fifo_count[6][0],
                dut.uMesh.gen_z[1].gen_y[1].gen_x[1].u_router.downstream_credits[0][0],
                dut.uMesh.gen_z[1].gen_y[1].gen_x[1].u_router.ovc_state[0][0], dut.uMesh.gen_z[1].gen_y[1].gen_x[1].u_router.ovc_lock_in_port[0][0], dut.uMesh.gen_z[1].gen_y[1].gen_x[1].u_router.s1_valid[6][0], dut.uMesh.gen_z[1].gen_y[1].gen_x[1].u_router.s1_ready[6][0], dut.uMesh.gen_z[1].gen_y[1].gen_x[1].u_router.s2_ready[6][0], dut.uMesh.gen_z[1].gen_y[1].gen_x[1].u_router.va_grant_comb[6][0], dut.uMesh.gen_z[1].gen_y[1].gen_x[1].u_router.s2_va_grant[6][0]);
        end
    end

    initial begin
        $display("GridX NoC Hotspot Stress Test");
        $display("Config: %0dx%0dx%0d (%0d Nodes, %0d Active Cores), %0d Threads", CUBE_X, CUBE_Y, CUBE_Z, NUM_NODES, NUM_ACTIVE_CORES, TOTAL_THREADS);

        timeout_flag = 1'b0;
        rst_n = 0;
        host_start = 0;
        host_wr_en = 0;
        pmem_wr_en = 0;
        
        #(CLK_PERIOD * 10);
        rst_n = 1;
        #(CLK_PERIOD * 10);

        for (integer i = 0; i < 32; i = i + 1) begin
            dmem_wr_addr = 22'h0000E0 + i;
            dmem_wr_data = 8'h00;
            dmem_wr_en = 1;
            #(CLK_PERIOD);
        end
        dmem_wr_en = 0;
        #(CLK_PERIOD * 2);

        $display("Loading NoC Hotspot Stress Kernel...");
        for (integer i = 0; i < PMEM_DEPTH; i = i + 1) begin
            pmem_wr_addr = i;
            pmem_wr_en = 1;
            
            if (i == 0) pmem_wr_data = enc_const(4'h1, 8'hF0);
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
            
            #(CLK_PERIOD);
        end
        pmem_wr_en = 0;
        #(CLK_PERIOD * 5);

        host_wr_data = TOTAL_THREADS;
        host_wr_en = 1;
        #(CLK_PERIOD);
        host_wr_en = 0;
        #(CLK_PERIOD * 2);

        $display("Starting execution of %0d threads...", TOTAL_THREADS);
        host_start = 1;
        #(CLK_PERIOD);
        host_start = 0;

        fork
            begin
                wait (kernel_done == 1'b1 || kernel_fault == 1'b1 || (dut.perfTotalFlits >= 40));
                #(CLK_PERIOD * 100);
            end
            begin
                #(CLK_PERIOD * (TIMEOUT - 100));
                timeout_flag = 1'b1;
            end
        join_any
        disable fork;

        if (dut.perfTotalFlits == 0) begin
            $fatal(1, "FAIL: Kernel completed but MemoryMesh/NoC saw zero flits. Traffic didn't route!");
        end
        if (dut.perfActiveCores != NUM_ACTIVE_CORES) begin
            $fatal(1, "FAIL: Expected %0d active cores, got %0d", NUM_ACTIVE_CORES, dut.perfActiveCores);
        end

        if (timeout_flag) begin
            $display("========== NOC TIMEOUT ==========");
            $display("Kernel State     = %0d", kernel_state);
            $display("Total Cycles     = %0d", dut.perfCycleCount);
            $display("Total NoC Flits  = %0d", dut.perfTotalFlits);
            $display("NoC Stall Cycles = %0d", dut.perfNoCStallCycles);
            $display("Active Cores     = %0d", dut.perfActiveCores);
            $fatal(1, "FAIL: Simulation timed out. NoC might be deadlocked.");
        end else if (kernel_fault) begin
            $display("========== NOC FAULT ==========");
            $fatal(1, "FAIL: Kernel raised a fault.");
        end else begin
            $display("SUCCESS: Kernel Completed!");
            $display("");
            $display("PERFORMANCE:");
            $display("Total Cycles     = %0d", dut.perfCycleCount);
            $display("Total NoC Flits  = %0d", dut.perfTotalFlits);
            $display("NoC Stall Cycles = %0d", dut.perfNoCStallCycles);
            $display("Active Cores     = %0d", dut.perfActiveCores);
            $display("");
            $display("VERDICT:");
            $display("PASS - actual NoC traffic observed");
            $display("PASS - all %0d cores active", NUM_ACTIVE_CORES);
            $display("PASS - no fault");
            $display("PASS - no timeout");
        end

        $finish;
    end
endmodule
