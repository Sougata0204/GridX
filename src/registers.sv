`default_nettype none
`timescale 1ns/1ns

// my registers store thread data and identity
module registers #(
    parameter ThreadsPerBlock = 4,
    parameter ThreadId = 0,
    parameter DataBits = 16
) (
    input wire clk,
    input wire reset,
    input wire enable,
    input reg [7:0] blockId,
    input reg [2:0] coreState,
    input reg [3:0] decodedRdAddress,
    input reg [3:0] decodedRsAddress,
    input reg [3:0] decodedRtAddress,
    input reg decodedRegWriteEnable,
    input reg [1:0] decodedRegInputMux,
    input reg [DataBits-1:0] decodedImmediate,
    input wire forceRegWriteEnable,
    input wire [3:0] forceRegWriteDest,
    input wire [DataBits-1:0] forceRegWriteData,
    input reg [DataBits-1:0] aluOut,
    input reg [DataBits-1:0] lsuOut,
    output reg [DataBits-1:0] rs,
    output reg [DataBits-1:0] rt,
    output reg [DataBits-1:0] rdVal
);
    localparam Arithmetic = 2'b00,
        Memory = 2'b01,
        Constant = 2'b10;
        
    reg [DataBits-1:0] registers[15:0];
    
    always @(*) begin
        rs = (decodedRsAddress == 4'b0000) ? {DataBits{1'b0}} : registers[decodedRsAddress];
        rt = (decodedRtAddress == 4'b0000) ? {DataBits{1'b0}} : registers[decodedRtAddress];
        rdVal = (decodedRdAddress == 4'b0000) ? {DataBits{1'b0}} : registers[decodedRdAddress];
    end
    
    integer i;
    
    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < 16; i = i + 1) begin
                registers[i] <= {DataBits{1'b0}};
            end
            registers[13] <= {{(DataBits-8){1'b0}}, 8'b0};
            registers[14] <= {{(DataBits-8){1'b0}}, ThreadsPerBlock[7:0]};
            registers[15] <= {{(DataBits-8){1'b0}}, ThreadId[7:0]};
        end else if (enable) begin
            registers[13] <= {{(DataBits-8){1'b0}}, blockId};
            if (forceRegWriteEnable) begin
                 if (forceRegWriteDest != 4'b0000) begin
                     registers[forceRegWriteDest] <= forceRegWriteData;
                 end
            end
            else if (coreState == 3'b110) begin
                if (decodedRegWriteEnable && decodedRdAddress < 13 && decodedRdAddress != 0) begin
                    // synthesis translateOff
                    $display("[REG_WRITE] Cycle %d: Thread %d: Writing reg %d with %h (mux=%d, alu=%h, lsu=%h, imm=%h)",
                             $time, ThreadId, decodedRdAddress,
                             (decodedRegInputMux == 2'b00) ? aluOut :
                             (decodedRegInputMux == 2'b01) ? lsuOut : decodedImmediate,
                             decodedRegInputMux, aluOut, lsuOut, decodedImmediate);
                    // synthesis translateOn
                    case (decodedRegInputMux)
                        Arithmetic: begin
                            registers[decodedRdAddress] <= aluOut;
                        end
                        Memory: begin
                            registers[decodedRdAddress] <= lsuOut;
                        end
                        Constant: begin
                            registers[decodedRdAddress] <= decodedImmediate;
                        end
                    endcase
                end
            end
        end
    end
endmodule
