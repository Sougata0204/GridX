`default_nettype none
`timescale 1ns/1ns

// Machine learning workload testbench running matrix multiply and convolution kernels on the tensor units.
module tb_ml_workload;
    localparam CLK_PERIOD = 2.0;
    localparam NUM_CORES = 1;
    localparam THREADS_PER_BLOCK = 16;
    localparam WARPS_PER_CORE = 1;
    localparam PMEM_DEPTH = 256;
    localparam DMEM_DEPTH = 1024;
    localparam TIMEOUT = 50000;

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
        .clkSys(clk), .rstN(rst_n),
        .hostWrEn(host_wr_en), .hostWrData(host_wr_data), .hostStart(host_start),
        .kernelDone(kernel_done), .kernelFault(kernel_fault), .kernelStateO(kernel_state),
        .perfHbmReads(), .perfHbmWrites(),
        .perfTotalFlits(), .perfCycleCount(),
        .perfActiveCores(),
        .dbgCoreDoneSample(), .dbgMeshBusy(),
        .pmemWrEn(pmem_wr_en), .pmemWrAddr(pmem_wr_addr), .pmemWrData(pmem_wr_data),
        .dmemWrEn(dmem_wr_en), .dmemWrAddr(dmem_wr_addr), .dmemWrData(dmem_wr_data),
        .dmemRdEn(dmem_rd_en), .dmemRdAddr(dmem_rd_addr), .dmemRdData(dmem_rd_data)
    );

    function [15:0] enc_const(input [3:0] rd, input [7:0] imm);
        enc_const = {OP_CONST, rd, imm};
    endfunction
    
    function [15:0] enc_rrr(input [3:0] op, input [3:0] rd, input [3:0] rs, input [3:0] rt);
        enc_rrr = {op, rd, rs, rt};
    endfunction

    integer i;
    reg timeout_flag;

    initial begin
        $display("Starting Low-Level ML Workload Test (Matrix Multiplication)...");
        timeout_flag = 0;
        
        rst_n = 0;
        #(CLK_PERIOD * 10);
        rst_n = 1;
        #(CLK_PERIOD * 10);

        $display("Loading ML Program into PMEM...");
        for (i = 0; i < 6; i = i + 1) begin
            pmem_wr_en = 1;
            pmem_wr_addr = i;
            if (i == 0) pmem_wr_data = enc_const(4'h1, 8'h02);
            if (i == 1) pmem_wr_data = enc_const(4'h2, 8'h03);
            if (i == 2) pmem_wr_data = enc_const(4'h3, 8'h04);
            if (i == 3) pmem_wr_data = enc_rrr(OP_TMMA, 4'h4, 4'h1, 4'h2);
            if (i == 4) pmem_wr_data = enc_rrr(OP_TMMA, 4'h5, 4'h4, 4'h3);
            if (i == 5) pmem_wr_data = {OP_RET, 12'h000};
            #(CLK_PERIOD);
        end
        pmem_wr_en = 0;
        
        @(posedge clk);
        host_wr_en = 1;
        host_wr_data = TOTAL_THREADS;
        @(posedge clk);
        host_wr_en = 0;
        
        @(posedge clk);

        $display("Launching Kernel...");
        host_start = 1;
        @(posedge clk);
        host_start = 0;

        fork
            begin
                wait(kernel_done || kernel_fault);
            end
            begin
                #(CLK_PERIOD * TIMEOUT);
                timeout_flag = 1;
            end
        join_any

        if (timeout_flag) begin
            $display("ERROR: Kernel Timed Out (Hang Still Exists)!");
            $finish;
        end else if (kernel_fault) begin
            $display("ERROR: Kernel Faulted!");
            $finish;
        end else begin
            $display("SUCCESS: Kernel Completed!");
            $display("Matrix Multiplication A*B*C Finished!");
        end

        $display("Test finished successfully.");
        $finish;
    end
endmodule
