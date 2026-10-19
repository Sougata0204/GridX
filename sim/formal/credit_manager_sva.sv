// Formal verification assertions for credit manager checking grant safety, credit bounds, and saturation invariant.
`default_nettype none
`timescale 1ns/1ns

module credit_manager_sva #(
    parameter MAX_CREDITS = 8,
    parameter CREDIT_WIDTH = $clog2(MAX_CREDITS) + 1
) (
    input wire clk,
    input wire reset,
    input wire allocValid,
    input wire freeValid,
    input wire [CREDIT_WIDTH-1:0] creditsAvailable,
    input wire allocReady
);

    property p_no_grant_on_empty;
        @(posedge clk) disable iff (reset)
        (creditsAvailable == 0) |-> !allocValid;
    endproperty
    sva_no_grant_on_empty: assert property(p_no_grant_on_empty)
        else $error("SVA ERROR: Consumed a flit when credits were zero.");

    property p_no_credit_overflow;
        @(posedge clk) disable iff (reset)
        creditsAvailable <= MAX_CREDITS;
    endproperty
    sva_no_credit_overflow: assert property(p_no_credit_overflow)
        else $error("SVA ERROR: Credits exceeded MAX_CREDITS.");

    property p_no_increment_on_max_release;
        @(posedge clk) disable iff (reset)
        (creditsAvailable == MAX_CREDITS && freeValid && !allocValid) |=> (creditsAvailable == MAX_CREDITS);
    endproperty
    sva_no_increment_on_max_release: assert property(p_no_increment_on_max_release)
        else $error("SVA ERROR: Credit overflow on max release.");

    property p_eventual_credit_return;
        @(posedge clk) disable iff (reset)
        (creditsAvailable == 0) |-> s_eventually (freeValid);
    endproperty
    sva_eventual_credit_return: assert property(p_eventual_credit_return)
        else $error("SVA LIVENESS ERROR: Credits dropped to 0 and were never returned (Deadlock or leak).");

endmodule
