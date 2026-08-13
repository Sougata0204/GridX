
`default_nettype none
`timescale 1ns/1ns

module creditManager #(
    parameter MAX_CREDITS = 8,
    parameter CREDIT_WIDTH = $clog2(MAX_CREDITS) + 1
) (
    input  wire clk,
    input  wire reset,
    input  wire consume,
    input  wire releaseCredit,
    output wire [CREDIT_WIDTH-1:0] available,
    output wire canIssue,
    output wire nearlyEmpty,
    output wire empty,
    output reg [31:0] totalConsumed,
    output reg [31:0] totalReleased,
    output reg [CREDIT_WIDTH-1:0] minCreditsSeen,
    output reg [CREDIT_WIDTH-1:0] maxOutstandingSeen
);
    reg [CREDIT_WIDTH-1:0] creditCount;
    wire [CREDIT_WIDTH-1:0] outstanding;
    assign available = creditCount;
    assign canIssue = (creditCount > 0);
    assign nearlyEmpty = (creditCount == 1);
    assign empty = (creditCount == 0);
    assign outstanding = MAX_CREDITS - creditCount;
    always @(posedge clk) begin
        if (reset) begin
            creditCount <= MAX_CREDITS;
            totalConsumed <= 0;
            totalReleased <= 0;
            minCreditsSeen <= MAX_CREDITS;
            maxOutstandingSeen <= 0;
        end else begin
            case ({consume & canIssue, releaseCredit})
                2'b10: begin
                    creditCount <= creditCount - 1;
                    totalConsumed <= totalConsumed + 1;
                end
                2'b01: begin
                    if (creditCount < MAX_CREDITS) begin
                        creditCount <= creditCount + 1;
                    end
                    totalReleased <= totalReleased + 1;
                end
                2'b11: begin
                    totalConsumed <= totalConsumed + 1;
                    totalReleased <= totalReleased + 1;
                end
                default: begin
                end
            endcase
            if (creditCount < minCreditsSeen) begin
                minCreditsSeen <= creditCount;
            end
            if (outstanding > maxOutstandingSeen) begin
                maxOutstandingSeen <= outstanding;
            end
        end
    end
`ifdef VERILATOR
    always @(posedge clk) begin
        if (!reset) begin
            if (creditCount > MAX_CREDITS) begin
                $fatal(1, "creditManager: Credit overflow! count=%d, max=%d",
                       creditCount, MAX_CREDITS);
            end
            if (consume && !canIssue) begin
                $warning("creditManager: Attempted consume with no credits!");
            end
            if (releaseCredit && creditCount == MAX_CREDITS) begin
                $warning("creditManager: Release when already at max credits!");
            end
        end
    end
`endif
endmodule
