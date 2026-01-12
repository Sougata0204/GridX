`default_nettype none
`timescale 1ns/1ns

// TENSOR UNIT (4x4 Matrix Multiply-Accumulate)
// > Performs D = A * B + C
// > Inputs: A (4x4 INT16), B (4x4 INT16), C (4x4 INT32)
// > Output: D (4x4 INT32)
// > Latency: 4 Cycles (Deterministic)
// > Throughput: 1 Operation every 4 cycles (Non-pipelined FSM for simplicity/area)

module tensor_unit (
    input wire clk,
    input wire reset,

    // Control
    input wire start,
    output reg done,
    output reg busy,

    // Data Inputs (Packed dimensions for cleaner interface)
    // Verilog requires careful packing order. Using unpacked for internal logic ease or packed for port?
    // SystemVerilog enables loose multidimensional ports.
    // A: 4 rows, 4 cols, 16 bits
    input wire signed [3:0][3:0][15:0] matrix_a, 
    input wire signed [3:0][3:0][15:0] matrix_b,
    input wire signed [3:0][3:0][31:0] matrix_c,

    // Data Output
    output reg signed [3:0][3:0][31:0] matrix_d
);

    // Internal State
    reg [2:0] cycle_count;
    reg computing;

    // Registers to hold inputs stable during computation
    reg signed [3:0][3:0][15:0] reg_a;
    reg signed [3:0][3:0][15:0] reg_b;
    reg signed [3:0][3:0][31:0] acc; // Accumulator

    integer i, j, k;

    always @(posedge clk) begin
        if (reset) begin
            cycle_count <= 0;
            computing <= 0;
            done <= 0;
            busy <= 0;
            // Clear result registers
            for (i=0; i<4; i=i+1) begin
                for (j=0; j<4; j=j+1) begin
                    matrix_d[i][j] <= 0;
                    acc[i][j] <= 0;
                    reg_a[i][j] <= 0;
                    reg_b[i][j] <= 0;
                end
            end
        end else begin
            done <= 0; // Pulse done signal

            if (start && !busy) begin
                // Latch Inputs
                reg_a <= matrix_a;
                reg_b <= matrix_b;
                acc <= matrix_c;
                
                computing <= 1;
                busy <= 1;
                cycle_count <= 0;
            end else if (computing) begin
                // Compute 1 row of result per cycle to spread area/power
                // Row 'cycle_count' of D is computed
                if (cycle_count < 4) begin
                    // Compute Row = cycle_count
                    // D[row][col] = Sum(A[row][k] * B[k][col]) + C[row][col]
                    // We compute all 4 columns for this row in parallel
                    // This creates 4 * 4 = 16 MACs per cycle.
                    // Total Logic: 16 Multipliers (16-bit) per cycle.
                    
                    for (j=0; j<4; j=j+1) begin // For each column
                       // Calculate Dot Product for D[cycle_count][j]
                       reg signed [31:0] dot_prod;
                       dot_prod = 0;
                       for (k=0; k<4; k=k+1) begin
                           // Explicit casting for signed multiplication
                           dot_prod = dot_prod + ({{16{reg_a[cycle_count][k][15]}}, reg_a[cycle_count][k]} * {{16{reg_b[k][j][15]}}, reg_b[k][j]});
                       end
                       // Add C and store to D buffer (using acc as temp storage or direct?)
                       // We can store directly to output register or internal accumulator
                       // Let's store to output matrix_d to save logic
                       matrix_d[cycle_count][j] <= dot_prod + acc[cycle_count][j];
                    end

                    cycle_count <= cycle_count + 1;
                end else begin
                    // Finished 4 rows
                    computing <= 0;
                    busy <= 0;
                    done <= 1;
                end
            end
        end
    end

endmodule
