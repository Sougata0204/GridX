
`default_nettype none
`timescale 1ns/1ns
import gridx_pkg::*;

module fault_handler #(
    parameter FIFO_DEPTH     = FAULT_FIFO_DEPTH_DEFAULT,
    parameter ADDR_WIDTH     = 32,
    parameter MAX_WARP_ID    = 31,
    parameter MAX_CORE_ID    = 15,
    parameter THREAD_LANES   = 6
) (
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire                    fault_valid_i,
    input  wire [ADDR_WIDTH-1:0]  fault_addr_i,
    input  wire [1:0]             fault_type_i,
    input  wire [4:0]             fault_warp_id_i,
    input  wire [3:0]             fault_core_id_i,
    input  wire [THREAD_LANES-1:0] fault_thread_mask_i,

    input  wire [1:0]             dcr_fault_mode_i,
    input  wire                   dcr_fault_clear_i,

    output reg                    fault_interrupt_o,
    output reg                    fault_kill_kernel_o,
    output wire [THREAD_LANES-1:0] fault_mask_thread_o,

    output wire [31:0]            dcr_fault_head_o,
    output wire [31:0]            dcr_fault_head_meta_o,
    output reg  [31:0]            dcr_fault_drop_count_o,
    output wire [7:0]             dcr_fault_fifo_depth_o,
    output wire                   fifo_empty_o,
    output wire                   fifo_full_o
);
    localparam PTR_BITS = $clog2(FIFO_DEPTH);

    reg [ADDR_WIDTH-1:0]  fifo_addr   [FIFO_DEPTH-1:0];
    reg [1:0]             fifo_type   [FIFO_DEPTH-1:0];
    reg [4:0]             fifo_warp   [FIFO_DEPTH-1:0];
    reg [3:0]             fifo_core   [FIFO_DEPTH-1:0];
    reg [THREAD_LANES-1:0] fifo_tmask [FIFO_DEPTH-1:0];
    reg                   fifo_ovf    [FIFO_DEPTH-1:0];
    reg [PTR_BITS:0] head;
    reg [PTR_BITS:0] tail;
    reg [PTR_BITS:0] count;
    wire [PTR_BITS-1:0] head_idx = head[PTR_BITS-1:0];
    wire [PTR_BITS-1:0] tail_idx = tail[PTR_BITS-1:0];
    assign fifo_empty_o = (count == 0);
    assign fifo_full_o  = (count >= FIFO_DEPTH);
    assign dcr_fault_fifo_depth_o = FIFO_DEPTH[7:0];

    assign dcr_fault_head_o = fifo_empty_o ? 32'h0 : fifo_addr[head_idx][31:0];
    assign dcr_fault_head_meta_o = fifo_empty_o ? 32'h0 : {
        14'b0,
        fifo_ovf[head_idx],
        fifo_tmask[head_idx],
        fifo_core[head_idx],
        fifo_warp[head_idx],
        fifo_type[head_idx]
    };

    reg [THREAD_LANES-1:0] mask_reg;
    assign fault_mask_thread_o = mask_reg;
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head                   <= 0;
            tail                   <= 0;
            count                  <= 0;
            fault_interrupt_o      <= 1'b0;
            fault_kill_kernel_o    <= 1'b0;
            dcr_fault_drop_count_o <= 0;
            mask_reg               <= {THREAD_LANES{1'b0}};
            for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
                fifo_addr[i]  <= 0;
                fifo_type[i]  <= 0;
                fifo_warp[i]  <= 0;
                fifo_core[i]  <= 0;
                fifo_tmask[i] <= 0;
                fifo_ovf[i]   <= 0;
            end
        end else begin
            fault_interrupt_o   <= 1'b0;
            fault_kill_kernel_o <= 1'b0;
            mask_reg            <= {THREAD_LANES{1'b0}};

            if (dcr_fault_clear_i) begin
                head                   <= 0;
                tail                   <= 0;
                count                  <= 0;
                dcr_fault_drop_count_o <= 0;
            end else if (fault_valid_i) begin

                if (!fifo_full_o) begin
                    fifo_addr[tail_idx]  <= fault_addr_i;
                    fifo_type[tail_idx]  <= fault_type_i;
                    fifo_warp[tail_idx]  <= fault_warp_id_i;
                    fifo_core[tail_idx]  <= fault_core_id_i;
                    fifo_tmask[tail_idx] <= fault_thread_mask_i;
                    fifo_ovf[tail_idx]   <= 1'b0;
                    tail  <= tail + 1;
                    count <= count + 1;
                end else begin

                    dcr_fault_drop_count_o <= dcr_fault_drop_count_o + 1;
                end

                case (dcr_fault_mode_i)
                    FAULT_MODE_FATAL: begin
                        fault_kill_kernel_o <= 1'b1;
                        fault_interrupt_o   <= 1'b1;
                    end
                    FAULT_MODE_RECOVER: begin
                        mask_reg          <= fault_thread_mask_i;
                        fault_interrupt_o <= 1'b1;
                    end
                    FAULT_MODE_BOTH: begin

                        if (dcr_fault_mode_i[0]) begin
                            mask_reg          <= fault_thread_mask_i;
                            fault_interrupt_o <= 1'b1;
                        end else begin
                            fault_kill_kernel_o <= 1'b1;
                            fault_interrupt_o   <= 1'b1;
                        end
                    end
                    default: begin
                        fault_kill_kernel_o <= 1'b1;
                        fault_interrupt_o   <= 1'b1;
                    end
                endcase
            end
        end
    end
`ifdef VERILATOR
    always @(posedge clk) begin
        if (rst_n && fault_valid_i)
            $display("[FAULT] addr=%h type=%d warp=%d core=%d", fault_addr_i, fault_type_i, fault_warp_id_i, fault_core_id_i);
        if (rst_n && fifo_full_o && fault_valid_i)
            $display("[FAULT] FIFO OVERFLOW, dropping fault, total drops=%d", dcr_fault_drop_count_o + 1);
    end
`endif
endmodule
