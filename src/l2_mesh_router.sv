
`default_nettype none
`timescale 1ns/1ns

module l2MeshRouter #(
    parameter SLICE_ID = 0,
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 8,
    parameter L2_BASE = 16'h8000
) (
    input wire clk,
    input wire reset,
    input wire cReqValid,
    input wire cReqWrite,
    input wire [ADDR_WIDTH-1:0] cReqAddr,
    input wire [DATA_WIDTH-1:0] cReqWdata,
    output reg cReqReady,
    output reg [DATA_WIDTH-1:0] cReqRdata,
    input wire nInValid, input wire nInWrite, input wire [ADDR_WIDTH-1:0] nInAddr, input wire [DATA_WIDTH-1:0] nInWdata, output wire nInReady, output wire [DATA_WIDTH-1:0] nInRdata,
    input wire sInValid, input wire sInWrite, input wire [ADDR_WIDTH-1:0] sInAddr, input wire [DATA_WIDTH-1:0] sInWdata, output wire sInReady, output wire [DATA_WIDTH-1:0] sInRdata,
    input wire eInValid, input wire eInWrite, input wire [ADDR_WIDTH-1:0] eInAddr, input wire [DATA_WIDTH-1:0] eInWdata, output wire eInReady, output wire [DATA_WIDTH-1:0] eInRdata,
    input wire wInValid, input wire wInWrite, input wire [ADDR_WIDTH-1:0] wInAddr, input wire [DATA_WIDTH-1:0] wInWdata, output wire wInReady, output wire [DATA_WIDTH-1:0] wInRdata,
    output wire nOutValid, output wire nOutWrite, output wire [ADDR_WIDTH-1:0] nOutAddr, output wire [DATA_WIDTH-1:0] nOutWdata, input wire nOutReady, input wire [DATA_WIDTH-1:0] nOutRdata,
    output wire sOutValid, output wire sOutWrite, output wire [ADDR_WIDTH-1:0] sOutAddr, output wire [DATA_WIDTH-1:0] sOutWdata, input wire sOutReady, input wire [DATA_WIDTH-1:0] sOutRdata,
    output wire eOutValid, output wire eOutWrite, output wire [ADDR_WIDTH-1:0] eOutAddr, output wire [DATA_WIDTH-1:0] eOutWdata, input wire eOutReady, input wire [DATA_WIDTH-1:0] eOutRdata,
    output wire wOutValid, output wire wOutWrite, output wire [ADDR_WIDTH-1:0] wOutAddr, output wire [DATA_WIDTH-1:0] wOutWdata, input wire wOutReady, input wire [DATA_WIDTH-1:0] wOutRdata,
    output wire gOutValid, output wire gOutWrite, output wire [ADDR_WIDTH-1:0] gOutAddr, output wire [DATA_WIDTH-1:0] gOutWdata, input wire gOutReady, input wire [DATA_WIDTH-1:0] gOutRdata
);
    wire [15:0] destSliceId = (cReqAddr - L2_BASE) >> 10;
    wire isL2Access = (cReqAddr >= L2_BASE && cReqAddr < 16'hC000);
    wire isGlobal = (cReqAddr >= 16'hC000);
    wire targetIsLocal = isL2Access && (destSliceId == SLICE_ID);
    wire targetIsNorth = isL2Access && (destSliceId == SLICE_ID - 4);
    wire targetIsSouth = isL2Access && (destSliceId == SLICE_ID + 4);
    wire targetIsEast  = isL2Access && (destSliceId == SLICE_ID + 1);
    wire targetIsWest  = isL2Access && (destSliceId == SLICE_ID - 1);

    function isValidEast;
        input [4:0] src;
        input [4:0] dst;
        begin
            isValidEast = (dst == src + 1) && ((src / 4) == (dst / 4));
        end
    endfunction

    function isValidWest;
        input [4:0] src;
        input [4:0] dst;
        begin
            isValidWest = (dst == src - 1) && ((src / 4) == (dst / 4));
        end
    endfunction
    wire validEast = isValidEast(SLICE_ID[4:0], destSliceId[4:0]);
    wire validWest = isValidWest(SLICE_ID[4:0], destSliceId[4:0]);
    assign nOutValid = cReqValid && targetIsNorth;
    assign sOutValid = cReqValid && targetIsSouth;
    assign eOutValid = cReqValid && targetIsEast && validEast;
    assign wOutValid = cReqValid && targetIsWest && validWest;
    wire vcGInReady;
    virtualChannel #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(4)
    ) globalVc (
        .clk(clk),
        .reset(reset),
        .inValid(cReqValid && isGlobal),
        .inIsResponse(1'b0),
        .inAddr(cReqAddr),
        .inData(cReqWdata),
        .inWrite(cReqWrite),
        .inReady(vcGInReady),
        .vc0Valid(gOutValid),
        .vc0Addr(gOutAddr),
        .vc0Data(gOutWdata),
        .vc0Write(gOutWrite),
        .vc0Ready(gOutReady),
        .vc1Valid(), .vc1Addr(), .vc1Data(), .vc1Ready(1'b1),
        .perfVc0Packets(),
        .perfVc1Packets(),
        .perfVc0BlockedCycles(),
        .perfVc1BlockedCycles()
    );
    assign nOutWrite = cReqWrite; assign nOutAddr = cReqAddr; assign nOutWdata = cReqWdata;
    assign sOutWrite = cReqWrite; assign sOutAddr = cReqAddr; assign sOutWdata = cReqWdata;
    assign eOutWrite = cReqWrite; assign eOutAddr = cReqAddr; assign eOutWdata = cReqWdata;
    assign wOutWrite = cReqWrite; assign wOutAddr = cReqAddr; assign wOutWdata = cReqWdata;
    wire sliceReqValid;
    wire sliceReqWrite;
    wire [9:0] sliceReqAddr;
    wire [DATA_WIDTH-1:0] sliceWdata;
    wire sliceReqReady;
    wire [DATA_WIDTH-1:0] sliceReqRdata;
    wire cLocalValid = cReqValid && targetIsLocal;
    wire [4:0] reqVec = {wInValid, eInValid, sInValid, nInValid, cLocalValid};
    wire [4:0] grantVector;
    
    islipArbiter #(.PORTS(5)) iSlipArb (
        .clk(clk),
        .reset(reset),
        .reqs(reqVec),
        .grants(grantVector),
        .accept(sliceReqReady)
    );
    
    reg selValid, selWrite;
    reg [9:0] selAddr;
    reg [DATA_WIDTH-1:0] selWdata;
    wire found = (grantVector != 0);
    
    always @(*) begin
        case (1'b1)
            grantVector[0]: begin selValid=1; selWrite=cReqWrite; selAddr=(cReqAddr[9:0]); selWdata=cReqWdata; end
            grantVector[1]: begin selValid=1; selWrite=nInWrite; selAddr=(nInAddr[9:0]); selWdata=nInWdata; end
            grantVector[2]: begin selValid=1; selWrite=sInWrite; selAddr=(sInAddr[9:0]); selWdata=sInWdata; end
            grantVector[3]: begin selValid=1; selWrite=eInWrite; selAddr=(eInAddr[9:0]); selWdata=eInWdata; end
            grantVector[4]: begin selValid=1; selWrite=wInWrite; selAddr=(wInAddr[9:0]); selWdata=wInWdata; end
            default: begin selValid=0; selWrite=0; selAddr=0; selWdata=0; end
        endcase
    end
    assign sliceReqValid = selValid;
    assign sliceReqWrite = selWrite;
    assign sliceReqAddr  = selAddr;
    assign sliceWdata     = selWdata;
    wire sliceReqReadyMux = (found && sliceReqReady);
    wire ack = sliceReqReady;
    wire coreWon = grantVector[0];
    wire localAck = coreWon && ack;
    assign nInReady = grantVector[1] && ack;
    assign nInRdata = sliceReqRdata;
    assign sInReady = grantVector[2] && ack;
    assign sInRdata = sliceReqRdata;
    assign eInReady = grantVector[3] && ack;
    assign eInRdata = sliceReqRdata;
    assign wInReady = grantVector[4] && ack;
    assign wInRdata = sliceReqRdata;
    l2Slice #(
        .ADDR_WIDTH(10),
        .DATA_WIDTH(DATA_WIDTH)
    ) memorySlice (
        .clk(clk),
        .reqValid(sliceReqValid),
        .reqWrite(sliceReqWrite),
        .reqAddr(sliceReqAddr),
        .reqWdata(sliceWdata),
        .reqReady(sliceReqReady),
        .reqRdata(sliceReqRdata)
    );
    reg cReadyTemp;
    reg [DATA_WIDTH-1:0] cRdataTemp;
    always @(*) begin
        cReadyTemp = 0;
        cRdataTemp = 0;
        if (targetIsLocal) begin
             cReadyTemp = localAck;
             cRdataTemp = sliceReqRdata;
        end else if (targetIsNorth) begin
             cReadyTemp = nOutReady; cRdataTemp = nOutRdata;
        end else if (targetIsSouth) begin
             cReadyTemp = sOutReady; cRdataTemp = sOutRdata;
        end else if (targetIsEast && validEast) begin
             cReadyTemp = eOutReady; cRdataTemp = eOutRdata;
        end else if (targetIsWest && validWest) begin
             cReadyTemp = wOutReady; cRdataTemp = wOutRdata;
        end else if (isGlobal) begin
             cReadyTemp = gOutReady; cRdataTemp = gOutRdata;
        end
    end
    always @(*) begin
        cReqReady = cReadyTemp;
        cReqRdata = cRdataTemp;
    end
    // synthesis translateOff
    reg [31:0] reqSeenCount;
    reg [31:0] reqForwardedCount;
    reg [31:0] localHitCount;
    localparam [ADDR_WIDTH-1:0] TRACE_ADDR = 22'h00c000;
    reg [31:0] debugCounter;
    always @(posedge clk) begin
        if (reset) begin
            debugCounter <= 0;
            reqSeenCount <= 0;
            reqForwardedCount <= 0;
            localHitCount <= 0;
        end else begin
            debugCounter <= debugCounter + 1;
            if (cReqValid && cReqReady) begin
                reqSeenCount <= reqSeenCount + 1;
                if (targetIsLocal) begin
                    localHitCount <= localHitCount + 1;
                end else begin
                    reqForwardedCount <= reqForwardedCount + 1;
                end
            end
            if (cReqValid && (cReqAddr == TRACE_ADDR) && SLICE_ID == 0) begin
                $display("[TRACE 00c000] Cycle %0d MESH_INGRESS: Router=%0d Valid=%b Ready=%b Write=%b",
                         debugCounter, SLICE_ID, cReqValid, cReqReady, cReqWrite);
            end
            if (gOutValid && (gOutAddr == TRACE_ADDR) && SLICE_ID == 0) begin
                $display("[TRACE 00c000] Cycle %0d MESH_TO_GLOBAL: Router=%0d GValid=%b GReady=%b",
                         debugCounter, SLICE_ID, gOutValid, gOutReady);
            end
            if ((nOutValid || sOutValid || eOutValid || wOutValid) &&
                (cReqAddr == TRACE_ADDR) && SLICE_ID == 0) begin
                $display("[TRACE 00c000] Cycle %0d MESH_TO_NEIGHBOR: Router=%0d N=%b S=%b E=%b W=%b",
                         debugCounter, SLICE_ID, nOutValid, sOutValid, eOutValid, wOutValid);
            end
            if ((debugCounter % 2000 == 0) && SLICE_ID == 0) begin
                $display("[HEARTBEAT] Cycle %0d Router0: Seen=%0d Forwarded=%0d LocalHit=%0d",
                         debugCounter, reqSeenCount, reqForwardedCount, localHitCount);
            end
        end
    end
    // synthesis translateOn
endmodule
