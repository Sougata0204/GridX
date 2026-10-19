
`default_nettype none
`timescale 1ns/1ps

// SIMT register file providing per-thread general-purpose registers with dual read ports and single write port.
module registers #(
    parameter ThreadsPerBlock = 4,
    parameter ThreadId        = 0,
    parameter DataBits        = 16
) (
    input  wire                  clk,
    input  wire                  reset,
    input  wire                  enable,
    input  wire [7:0]            blockId,
    input  wire [2:0]            coreState,
    input  wire [3:0]            decodedRdAddress,
    input  wire [3:0]            decodedRsAddress,
    input  wire [3:0]            decodedRtAddress,
    input  wire                  decodedRegWriteEnable,
    input  wire [1:0]            decodedRegInputMux,
    input  wire [DataBits-1:0]   decodedImmediate,
    input  wire                  forceRegWriteEnable,
    input  wire [3:0]            forceRegWriteDest,
    input  wire [DataBits-1:0]   forceRegWriteData,
    input  wire [DataBits-1:0]   aluOut,
    input  wire [DataBits-1:0]   lsuOut,
    output wire [DataBits-1:0]   rs,
    output wire [DataBits-1:0]   rt,
    output wire [DataBits-1:0]   rdVal
);

    localparam Arithmetic = 2'b00,
               Memory     = 2'b01,
               Constant   = 2'b10;

    reg [DataBits-1:0] registers [15:0];

    assign rs    = (decodedRsAddress == 4'b0000) ? '0 : registers[decodedRsAddress];
    assign rt    = (decodedRtAddress == 4'b0000) ? '0 : registers[decodedRtAddress];
    assign rdVal = (decodedRdAddress == 4'b0000) ? '0 : registers[decodedRdAddress];

    integer i;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 16; i = i + 1)
                registers[i] <= '0;
            registers[13] <= {{(DataBits-8){1'b0}}, 8'b0};
            registers[14] <= {{(DataBits-8){1'b0}}, ThreadsPerBlock[7:0]};
            registers[15] <= {{(DataBits-8){1'b0}}, ThreadId[7:0]};
        end else if (enable) begin
            registers[13] <= {{(DataBits-8){1'b0}}, blockId};

            if (forceRegWriteEnable) begin
                if (forceRegWriteDest != 4'b0000) begin
                    registers[forceRegWriteDest] <= forceRegWriteData;
                end
            end else if (coreState == 3'b110) begin
                if (decodedRegWriteEnable && decodedRdAddress < 4'd13 && decodedRdAddress != 4'b0000) begin
                    case (decodedRegInputMux)
                        Arithmetic: registers[decodedRdAddress] <= aluOut;
                        Memory:     registers[decodedRdAddress] <= lsuOut;
                        Constant:   registers[decodedRdAddress] <= decodedImmediate;
                        default:    registers[decodedRdAddress] <= aluOut;
                    endcase
                end
            end
        end
    end

endmodule
