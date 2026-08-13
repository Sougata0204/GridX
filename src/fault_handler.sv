
`default_nettype none
`timescale 1ns/1ns
import gridxPkg::*;

module faultHandler #(
    parameter FIFO_DEPTH     = FAULT_FIFO_DEPTH_DEFAULT,
    parameter ADDR_WIDTH     = 32,
    parameter MAX_WARP_ID    = 31,
    parameter MAX_CORE_ID    = 15,
    parameter THREAD_LANES   = 6
) (
    input  wire                    clk,
    input  wire                    rstN,

    input  wire                    faultValidI,
    input  wire [ADDR_WIDTH-1:0]  faultAddrI,
    input  wire [1:0]             faultTypeI,
    input  wire [4:0]             faultWarpIdI,
    input  wire [3:0]             faultCoreIdI,
    input  wire [THREAD_LANES-1:0] faultThreadMaskI,

    input  wire [1:0]             dcrFaultModeI,
    input  wire                   dcrFaultClearI,

    output reg                    faultInterruptO,
    output reg                    faultKillKernelO,
    output wire [THREAD_LANES-1:0] faultMaskThreadO,

    output wire [31:0]            dcrFaultHeadO,
    output wire [31:0]            dcrFaultHeadMetaO,
    output reg  [31:0]            dcrFaultDropCountO,
    output wire [7:0]             dcrFaultFifoDepthO,
    output wire                   fifoEmptyO,
    output wire                   fifoFullO
);
    localparam PTR_BITS = $clog2(FIFO_DEPTH);

    reg [ADDR_WIDTH-1:0]  fifoAddr   [FIFO_DEPTH-1:0];
    reg [1:0]             fifoType   [FIFO_DEPTH-1:0];
    reg [4:0]             fifoWarp   [FIFO_DEPTH-1:0];
    reg [3:0]             fifoCore   [FIFO_DEPTH-1:0];
    reg [THREAD_LANES-1:0] fifoTmask [FIFO_DEPTH-1:0];
    reg                   fifoOvf    [FIFO_DEPTH-1:0];
    reg [PTR_BITS:0] head;
    reg [PTR_BITS:0] tail;
    reg [PTR_BITS:0] count;
    wire [PTR_BITS-1:0] headIdx = head[PTR_BITS-1:0];
    wire [PTR_BITS-1:0] tailIdx = tail[PTR_BITS-1:0];
    assign fifoEmptyO = (count == 0);
    assign fifoFullO  = (count >= FIFO_DEPTH);
    assign dcrFaultFifoDepthO = FIFO_DEPTH[7:0];

    assign dcrFaultHeadO = fifoEmptyO ? 32'h0 : fifoAddr[headIdx][31:0];
    assign dcrFaultHeadMetaO = fifoEmptyO ? 32'h0 : {
        14'b0,
        fifoOvf[headIdx],
        fifoTmask[headIdx],
        fifoCore[headIdx],
        fifoWarp[headIdx],
        fifoType[headIdx]
    };

    reg [THREAD_LANES-1:0] maskReg;
    assign faultMaskThreadO = maskReg;
    integer i;
    always @(posedge clk or negedge rstN) begin
        if (!rstN) begin
            head                   <= 0;
            tail                   <= 0;
            count                  <= 0;
            faultInterruptO      <= 1'b0;
            faultKillKernelO    <= 1'b0;
            dcrFaultDropCountO <= 0;
            maskReg               <= {THREAD_LANES{1'b0}};
            for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
                fifoAddr[i]  <= 0;
                fifoType[i]  <= 0;
                fifoWarp[i]  <= 0;
                fifoCore[i]  <= 0;
                fifoTmask[i] <= 0;
                fifoOvf[i]   <= 0;
            end
        end else begin
            faultInterruptO   <= 1'b0;
            faultKillKernelO <= 1'b0;
            maskReg            <= {THREAD_LANES{1'b0}};

            if (dcrFaultClearI) begin
                head                   <= 0;
                tail                   <= 0;
                count                  <= 0;
                dcrFaultDropCountO <= 0;
            end else if (faultValidI) begin

                if (!fifoFullO) begin
                    fifoAddr[tailIdx]  <= faultAddrI;
                    fifoType[tailIdx]  <= faultTypeI;
                    fifoWarp[tailIdx]  <= faultWarpIdI;
                    fifoCore[tailIdx]  <= faultCoreIdI;
                    fifoTmask[tailIdx] <= faultThreadMaskI;
                    fifoOvf[tailIdx]   <= 1'b0;
                    tail  <= tail + 1;
                    count <= count + 1;
                end else begin

                    dcrFaultDropCountO <= dcrFaultDropCountO + 1;
                end

                case (dcrFaultModeI)
                    FAULT_MODE_FATAL: begin
                        faultKillKernelO <= 1'b1;
                        faultInterruptO   <= 1'b1;
                    end
                    FAULT_MODE_RECOVER: begin
                        maskReg          <= faultThreadMaskI;
                        faultInterruptO <= 1'b1;
                    end
                    FAULT_MODE_BOTH: begin

                        if (dcrFaultModeI[0]) begin
                            maskReg          <= faultThreadMaskI;
                            faultInterruptO <= 1'b1;
                        end else begin
                            faultKillKernelO <= 1'b1;
                            faultInterruptO   <= 1'b1;
                        end
                    end
                    default: begin
                        faultKillKernelO <= 1'b1;
                        faultInterruptO   <= 1'b1;
                    end
                endcase
            end
        end
    end
`ifdef VERILATOR
    always @(posedge clk) begin
        if (rstN && faultValidI)
            $display("[FAULT] addr=%h type=%d warp=%d core=%d", faultAddrI, faultTypeI, faultWarpIdI, faultCoreIdI);
        if (rstN && fifoFullO && faultValidI)
            $display("[FAULT] FIFO OVERFLOW, dropping fault, total drops=%d", dcrFaultDropCountO + 1);
    end
`endif
endmodule
