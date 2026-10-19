`default_nettype none
`timescale 1ns/1ns

// iSLIP iterative arbiter providing fair round-robin scheduling for multi-port crossbar switch allocation.
module islipArbiter #(
    parameter PORTS = 5
) (
    input wire clk,
    input wire reset,
    input wire [PORTS-1:0] reqs,
    output reg [PORTS-1:0] grants,
    input wire accept
);

    reg [PORTS-1:0] pointers [PORTS-1:0];

    integer i, j, k;
    reg [PORTS-1:0] grantTemp;

    function automatic integer wrap_port(integer base, integer offset);
        automatic integer raw = base + offset;
        return (raw >= PORTS) ? (raw - PORTS) : raw;
    endfunction
    
    always_comb begin
        grantTemp = 0;
        for (i = 0; i < PORTS; i = i + 1) begin
            if (reqs[i]) begin
                for (j = 0; j < PORTS; j = j + 1) begin
                    if (!grantTemp && ((1 << wrap_port(pointers[i], j)) & reqs) != 0) begin
                        if (wrap_port(pointers[i], j) == i) begin
                            grantTemp[i] = 1'b1;
                        end
                    end
                end
            end
        end
        grants = grantTemp;
    end
    
    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < PORTS; i = i + 1) begin
                pointers[i] <= i;
            end
        end else if (accept && grants != 0) begin
            for (i = 0; i < PORTS; i = i + 1) begin
                if (grants[i]) begin
                    pointers[i] <= wrap_port(pointers[i], 1);
                end
            end
        end
    end

endmodule
