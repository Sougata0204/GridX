
`default_nettype none
`timescale 1ns/1ns

module credit_manager #(
    parameter MAX_CREDITS = 8,
    parameter CREDIT_WIDTH = $clog2(MAX_CREDITS) + 1
) (
    input  wire clk,
    input  wire reset,
    input  wire consume,
    input  wire release_credit,
    output wire [CREDIT_WIDTH-1:0] available,
    output wire can_issue,
    output wire nearly_empty,
    output wire empty,
    output reg [31:0] total_consumed,
    output reg [31:0] total_released,
    output reg [CREDIT_WIDTH-1:0] min_credits_seen,
    output reg [CREDIT_WIDTH-1:0] max_outstanding_seen
);
    reg [CREDIT_WIDTH-1:0] credit_count;
    wire [CREDIT_WIDTH-1:0] outstanding;
    assign available = credit_count;
    assign can_issue = (credit_count > 0);
    assign nearly_empty = (credit_count == 1);
    assign empty = (credit_count == 0);
    assign outstanding = MAX_CREDITS - credit_count;
    always @(posedge clk) begin
        if (reset) begin
            credit_count <= MAX_CREDITS;
            total_consumed <= 0;
            total_released <= 0;
            min_credits_seen <= MAX_CREDITS;
            max_outstanding_seen <= 0;
        end else begin
            case ({consume & can_issue, release_credit})
                2'b10: begin
                    credit_count <= credit_count - 1;
                    total_consumed <= total_consumed + 1;
                end
                2'b01: begin
                    if (credit_count < MAX_CREDITS) begin
                        credit_count <= credit_count + 1;
                    end
                    total_released <= total_released + 1;
                end
                2'b11: begin
                    total_consumed <= total_consumed + 1;
                    total_released <= total_released + 1;
                end
                default: begin
                end
            endcase
            if (credit_count < min_credits_seen) begin
                min_credits_seen <= credit_count;
            end
            if (outstanding > max_outstanding_seen) begin
                max_outstanding_seen <= outstanding;
            end
        end
    end
`ifdef VERILATOR
    always @(posedge clk) begin
        if (!reset) begin
            if (credit_count > MAX_CREDITS) begin
                $fatal(1, "CREDIT_MANAGER: Credit overflow! count=%d, max=%d",
                       credit_count, MAX_CREDITS);
            end
            if (consume && !can_issue) begin
                $warning("CREDIT_MANAGER: Attempted consume with no credits!");
            end
            if (release_credit && credit_count == MAX_CREDITS) begin
                $warning("CREDIT_MANAGER: Release when already at max credits!");
            end
        end
    end
`endif
endmodule
