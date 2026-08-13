`default_nettype none
`timescale 1ns/1ns
import gridxPkg::*;

// my decoder translates instructions to control signals
module decoder (
    input wire [2:0] coreState,
    input wire [15:0] instruction,
    output wire [63:0] decodedPacket
);
    localparam OpNop = OP_NOP,
        OpBrNzp = OP_BRnzp,
        OpCmp = OP_CMP,
        OpAdd = OP_ADD,
        OpSub = OP_SUB,
        OpMul = OP_MUL,
        OpDiv = OP_DIV,
        OpLdr = OP_LDR,
        OpStr = OP_STR,
        OpConst = OP_CONST,
        OpTileLd = OP_TILE_LD,
        OpTileSt = OP_TILE_ST,
        OpFence = OP_FENCE,
        OpBar = OP_BAR,
        OpRet = OP_RET;
        
    reg [3:0] iRd, iRs, iRt;
    reg [2:0] iNzp;
    reg [15:0] iImm;
    reg [3:0] iOpcode;
    
    reg cRegWe, cMemRe, cMemWe, cNzpWe;
    reg [1:0] cRegMux;
    reg [3:0] cAluArithMux;
    reg cPcMux, cRet, cTensor, cBar, cSimtSync, cFence;
    
    localparam AluAdd = 4'b0000;
    localparam AluSub = 4'b0001;
    localparam AluMul = 4'b0010;
    localparam AluDiv = 4'b0011;
    localparam AluCmp = 4'b0100;
    
    always @(*) begin
        iOpcode = instruction[15:12];
        iRd     = instruction[11:8];
        iRs     = instruction[7:4];
        iRt     = instruction[3:0];
        iNzp    = instruction[11:9];
        iImm    = {{8{instruction[7]}}, instruction[7:0]};
        
        cRegWe = 0; cMemRe = 0; cMemWe = 0; cNzpWe = 0;
        cRegMux = 2'b00; cAluArithMux = AluAdd;
        cPcMux = 0; cRet = 0; cTensor = 0; cBar = 0; cSimtSync = 0; cFence = 0;
        
        case (instruction[15:12])
            OpBrNzp: begin
                cPcMux = 1;
            end
            OpCmp: begin
                cAluArithMux = AluCmp;
                cNzpWe = 1;
            end
            OpAdd: begin
                cRegWe = 1; cRegMux = 2'b00; cAluArithMux = AluAdd;
            end
            OpSub: begin
                cRegWe = 1; cRegMux = 2'b00; cAluArithMux = AluSub;
            end
            OpMul: begin
                cRegWe = 1; cRegMux = 2'b00; cAluArithMux = AluMul;
            end
            OpDiv: begin
                cRegWe = 1; cRegMux = 2'b00; cAluArithMux = AluDiv;
            end
            OpLdr, OpTileLd: begin
                cRegWe = 1; cRegMux = 2'b01; cMemRe = 1;
            end
            OpStr, OpTileSt: begin
                cMemWe = 1;
            end
            OpConst: begin
                cRegWe = 1; cRegMux = 2'b10;
            end
            OP_TENSOR_MMA: begin
                cTensor = 1;
            end
            OpFence: begin
                cFence = 1;
            end
            OpBar: begin
                if (instruction[0] == 1'b1) begin
                    cSimtSync = 1;
                end else begin
                    cBar = 1;
                end
            end
            OpRet: begin
                cRet = 1;
            end
            default: begin  end
        endcase
    end
    
    assign decodedPacket = {
        14'd0,
        cFence,
        cSimtSync,
        cBar,
        iOpcode,
        cTensor,
        cRet,
        cPcMux,
        cAluArithMux,
        cRegMux,
        cNzpWe,
        cMemWe,
        cMemRe,
        cRegWe,
        iNzp,
        iRd,
        iRs,
        iRt,
        iImm
    };
endmodule
