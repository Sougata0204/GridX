
`default_nettype none
`timescale 1ns/1ns

module dcr (
    input wire clk,
    input wire reset,
    input wire device_control_write_enable,
    input wire [15:0] device_control_data,
    output wire [15:0] thread_count,
    output wire dcr_valid
);
    reg [15:0] device_control_register;
    reg dcr_written;
    assign thread_count = device_control_register;
    assign dcr_valid = dcr_written && (device_control_register > 0);
    always @(posedge clk) begin
        if (reset) begin
            device_control_register <= 16'b0;
            dcr_written <= 0;
        end else begin
            if (device_control_write_enable) begin
                device_control_register <= device_control_data;
                dcr_written <= 1;
            end
        end
    end
endmodule
