
`timescale 1ps/1ps

// AXI skid buffer providing single-cycle pipeline register for timing closure on ready/valid handshake paths.
module axi_skid_buffer #(
    parameter int DATA_WIDTH = 64
)(
    input  logic                    clk,
    input  logic                    rst_n,

    input  logic                    s_valid,
    output logic                    s_ready,
    input  logic [DATA_WIDTH-1:0]   s_data,

    output logic                    m_valid,
    input  logic                    m_ready,
    output logic [DATA_WIDTH-1:0]   m_data
);

    logic [DATA_WIDTH-1:0] main_data_reg;
    logic                  main_valid_reg;

    logic [DATA_WIDTH-1:0] skid_data_reg;
    logic                  skid_valid_reg;

    assign s_ready = !skid_valid_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            main_valid_reg <= 1'b0;
            main_data_reg  <= '0;
        end else if (s_ready) begin
            if (m_ready || !main_valid_reg) begin
                main_valid_reg <= s_valid;
                main_data_reg  <= s_data;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            skid_valid_reg <= 1'b0;
            skid_data_reg  <= '0;
        end else begin
            if (s_valid && s_ready && main_valid_reg && !m_ready) begin
                skid_valid_reg <= 1'b1;
                skid_data_reg  <= s_data;
            end else if (m_ready) begin
                skid_valid_reg <= 1'b0;
            end
        end
    end

    assign m_valid = main_valid_reg || skid_valid_reg;
    assign m_data  = skid_valid_reg ? skid_data_reg : main_data_reg;

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n) begin
            assert (!(skid_valid_reg && !main_valid_reg))
                else $error("SKID_BUF: Skid valid without main valid - state corruption");
        end
    end

    assert property (@(posedge clk) disable iff (!rst_n)
        (s_valid && s_ready) |-> ##1 (main_valid_reg || skid_valid_reg))
        else $error("SKID_BUF: Data accepted but lost from pipeline");
`endif

endmodule
