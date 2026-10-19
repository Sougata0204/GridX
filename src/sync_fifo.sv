
`default_nettype none
`timescale 1ns/1ps

// Synchronous FIFO providing single-clock buffering with full, empty, and configurable almost-full/almost-empty flags.
module sync_fifo #(
    parameter DATA_WIDTH = 32,
    parameter DEPTH      = 4
) (
    input  wire                  clk,
    input  wire                  reset,

    input  wire                  pushValid,
    input  wire [DATA_WIDTH-1:0] pushData,
    output wire                  pushReady,

    output wire                  popValid,
    output wire [DATA_WIDTH-1:0] popData,
    input  wire                  popReady
);
    localparam PTR_WIDTH = $clog2(DEPTH);

    reg [DATA_WIDTH-1:0] mem [DEPTH-1:0];
    reg [PTR_WIDTH:0]    count;
    reg [PTR_WIDTH-1:0]  head;
    reg [PTR_WIDTH-1:0]  tail;

    assign pushReady = (count < DEPTH) || (popValid && popReady);
    assign popValid  = (count > 0);
    assign popData   = mem[head];

    wire doPush = pushValid && pushReady;
    wire doPop  = popValid && popReady;

    always @(posedge clk) begin
        if (reset) begin
            count <= '0;
            head  <= '0;
            tail  <= '0;
        end else begin
            case ({doPush, doPop})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase

            if (doPush) begin
                mem[tail] <= pushData;
                tail <= (tail == DEPTH - 1) ? '0 : tail + 1'b1;
            end

            if (doPop) begin
                head <= (head == DEPTH - 1) ? '0 : head + 1'b1;
            end
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (!reset) begin
            if (doPush && count == DEPTH && !doPop)
                $error("[SYNC_FIFO_ERR] Push on full FIFO without concurrent pop!");
            if (doPop && count == 0)
                $error("[SYNC_FIFO_ERR] Pop on empty FIFO!");
        end
    end
`endif

endmodule
