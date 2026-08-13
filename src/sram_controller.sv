
`default_nettype none
`timescale 1ns/1ns

module sramController #(
    parameter NUM_CORES = 2,
    parameter THREADS_PER_BLOCK = 4,
    parameter NUM_BANKS = 8,
    parameter BANK_DEPTH = 256,
    parameter DATA_WIDTH = 64,
    parameter ADDR_BITS = 8,
    parameter NUM_REQUESTERS = NUM_CORES * THREADS_PER_BLOCK,
    parameter NUM_TILES = 4
) (
    input wire clk,
    input wire reset,
    input wire [ADDR_BITS-1:0] sramBaseReg,
    input wire [ADDR_BITS-1:0] sramLimitReg,
    input wire [NUM_REQUESTERS-1:0] coreReadValid,
    input wire [ADDR_BITS-1:0] coreReadAddress [NUM_REQUESTERS-1:0],
    output wire [NUM_REQUESTERS-1:0] coreReadReady,
    output wire [DATA_WIDTH-1:0] coreReadData [NUM_REQUESTERS-1:0],
    input wire [NUM_REQUESTERS-1:0] coreWriteValid,
    input wire [ADDR_BITS-1:0] coreWriteAddress [NUM_REQUESTERS-1:0],
    input wire [DATA_WIDTH-1:0] coreWriteData [NUM_REQUESTERS-1:0],
    output wire [NUM_REQUESTERS-1:0] coreWriteReady,
    output wire [NUM_REQUESTERS-1:0] coreBankConflict,
    input wire tileLdValid,
    input wire [$clog2(NUM_TILES)-1:0] tileLdId,
    input wire tileStValid,
    input wire [$clog2(NUM_TILES)-1:0] tileStId,
    input wire tileFenceValid,
    input wire [$clog2(NUM_TILES)-1:0] tileFenceId,
    output wire tileFenceDone,
    output wire [NUM_REQUESTERS-1:0] lsuMustStall,
    output wire [NUM_REQUESTERS-1:0] extReadValid,
    output wire [ADDR_BITS-1:0] extReadAddress [NUM_REQUESTERS-1:0],
    input wire [NUM_REQUESTERS-1:0] extReadReady,
    input wire [DATA_WIDTH-1:0] extReadData [NUM_REQUESTERS-1:0],
    output wire [NUM_REQUESTERS-1:0] extWriteValid,
    output wire [ADDR_BITS-1:0] extWriteAddress [NUM_REQUESTERS-1:0],
    output wire [DATA_WIDTH-1:0] extWriteData [NUM_REQUESTERS-1:0],
    input wire [NUM_REQUESTERS-1:0] extWriteReady,
    input wire dmaReadValid,
    input wire [ADDR_BITS-1:0] dmaReadAddress,
    output reg dmaReadReady,
    output reg [DATA_WIDTH-1:0] dmaReadData,
    input wire dmaWriteValid,
    input wire [ADDR_BITS-1:0] dmaWriteAddress,
    input wire [DATA_WIDTH-1:0] dmaWriteData,
    output reg dmaWriteReady,
    input wire dmaWriteDone,
    input wire dmaReadDone,
    input wire [NUM_BANKS-1:0] forceBankEnable,
    input wire [NUM_BANKS-1:0] forceBankSleep,
    output wire [NUM_BANKS-1:0] bankActive,
    output wire [1:0] bankPowerState [NUM_BANKS-1:0],
    output wire [NUM_BANKS-1:0] bankNeedsReload,
    output wire [2:0] tileState [NUM_TILES-1:0]
);
    localparam TILE_IDLE     = 3'b000;
    localparam TILE_LOADING  = 3'b001;
    localparam TILE_READY    = 3'b010;
    localparam TILE_IN_USE   = 3'b011;
    localparam TILE_EVICTING = 3'b100;
    reg [2:0] tileStateReg [NUM_TILES-1:0];
    reg [NUM_TILES-1:0] tileFirstReadSeen;
    genvar t;
    generate
        for (t = 0; t < NUM_TILES; t = t + 1) begin : tileStateOutput
            assign tileState[t] = tileStateReg[t];
        end
    endgenerate

    function [$clog2(NUM_TILES)-1:0] getTileId;
        input [ADDR_BITS-1:0] addr;
        reg [ADDR_BITS-1:0] tileSize;
        begin
            tileSize = (sramLimitReg - sramBaseReg + 1) / NUM_TILES;
            if (tileSize > 0)
                getTileId = (addr - sramBaseReg) / tileSize;
            else
                getTileId = 0;
        end
    endfunction
    wire [NUM_TILES-1:0] tileReadable;
    generate
        for (t = 0; t < NUM_TILES; t = t + 1) begin : readableCheck
            assign tileReadable[t] = (tileStateReg[t] == TILE_READY) ||
                                      (tileStateReg[t] == TILE_IN_USE);
        end
    endgenerate
    wire [NUM_TILES-1:0] tileDmaWriteAllowed;
    generate
        for (t = 0; t < NUM_TILES; t = t + 1) begin : dmaWriteCheck
            assign tileDmaWriteAllowed[t] = (tileStateReg[t] == TILE_IDLE);
        end
    endgenerate
    wire [NUM_TILES-1:0] tileDmaReadAllowed;
    generate
        for (t = 0; t < NUM_TILES; t = t + 1) begin : dmaReadCheck
            assign tileDmaReadAllowed[t] = (tileStateReg[t] == TILE_READY);
        end
    endgenerate
    assign tileFenceDone = tileFenceValid &&
                             (tileStateReg[tileFenceId] == TILE_READY);
    reg [NUM_REQUESTERS-1:0] lsuStallReg;
    integer r;
    always @(*) begin
        for (r = 0; r < NUM_REQUESTERS; r = r + 1) begin
            if (coreReadValid[r]) begin
                if (coreReadAddress[r] >= sramBaseReg &&
                    coreReadAddress[r] <= sramLimitReg) begin
                    lsuStallReg[r] = ~tileReadable[getTileId(coreReadAddress[r])];
                end else begin
                    lsuStallReg[r] = 1'b0;
                end
            end else begin
                lsuStallReg[r] = 1'b0;
            end
        end
    end
    assign lsuMustStall = lsuStallReg;
    integer i;
    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < NUM_TILES; i = i + 1) begin
                tileStateReg[i] <= TILE_IDLE;
                tileFirstReadSeen[i] <= 1'b0;
            end
        end else begin
            for (i = 0; i < NUM_TILES; i = i + 1) begin
                case (tileStateReg[i])
                    TILE_IDLE: begin
                        if (tileLdValid && (tileLdId == i)) begin
                            tileStateReg[i] <= TILE_LOADING;
                        end
                    end
                    TILE_LOADING: begin
                        if (dmaWriteDone) begin
                            tileStateReg[i] <= TILE_READY;
                            tileFirstReadSeen[i] <= 1'b0;
                        end
                    end
                    TILE_READY: begin
                        if (!tileFirstReadSeen[i]) begin
                            for (r = 0; r < NUM_REQUESTERS; r = r + 1) begin
                                if (coreReadValid[r] &&
                                    coreReadAddress[r] >= sramBaseReg &&
                                    coreReadAddress[r] <= sramLimitReg &&
                                    getTileId(coreReadAddress[r]) == i) begin
                                    tileStateReg[i] <= TILE_IN_USE;
                                    tileFirstReadSeen[i] <= 1'b1;
                                end
                            end
                        end
                        if (tileStValid && (tileStId == i)) begin
                            tileStateReg[i] <= TILE_EVICTING;
                        end
                    end
                    TILE_IN_USE: begin
                        if (tileFenceValid && (tileFenceId == i)) begin
                            tileStateReg[i] <= TILE_READY;
                            tileFirstReadSeen[i] <= 1'b0;
                        end
                    end
                    TILE_EVICTING: begin
                        if (dmaReadDone) begin
                            tileStateReg[i] <= TILE_IDLE;
                            tileFirstReadSeen[i] <= 1'b0;
                        end
                    end
                    default: begin
                        tileStateReg[i] <= TILE_IDLE;
                    end
                endcase
            end
        end
    end
    `ifdef FORMAL
    genvar a;
    generate
        for (a = 0; a < NUM_REQUESTERS; a = a + 1) begin : assertLsuRead
            always @(posedge clk) begin
                if (!reset && coreReadValid[a]) begin
                    if (coreReadAddress[a] >= sramBaseReg &&
                        coreReadAddress[a] <= sramLimitReg) begin
                        assert(tileReadable[getTileId(coreReadAddress[a])])
                            else $error("ILLEGAL: LSU read when tile not READY/IN_USE");
                    end
                end
            end
        end
    endgenerate
    always @(posedge clk) begin
        if (!reset && dmaWriteValid && tileLdValid) begin
            assert(tileDmaWriteAllowed[tileLdId])
                else $error("ILLEGAL: DMA write when tile != IDLE");
        end
    end
    always @(posedge clk) begin
        if (!reset && dmaReadValid && tileStValid) begin
            assert(tileStateReg[tileStId] != TILE_IN_USE)
                else $error("ILLEGAL: DMA read when tile == IN_USE");
        end
    end
    `endif
    wire [NUM_BANKS-1:0] bankTileActive;
    generate
        for (t = 0; t < NUM_BANKS && t < NUM_TILES; t = t + 1) begin : bankTileMap
            assign bankTileActive[t] = (tileStateReg[t] != TILE_IDLE);
        end
        for (t = NUM_TILES; t < NUM_BANKS; t = t + 1) begin : bankUnused
            assign bankTileActive[t] = 1'b0;
        end
    endgenerate
    wire [NUM_BANKS-1:0] bankPowerEnable;
    wire [NUM_REQUESTERS-1:0] sramReadReady;
    wire [DATA_WIDTH-1:0] sramReadData [NUM_REQUESTERS-1:0];
    wire [NUM_REQUESTERS-1:0] sramWriteReady;
    wire [NUM_REQUESTERS-1:0] tileExtReadValid;
    wire [ADDR_BITS-1:0] tileExtReadAddress [NUM_REQUESTERS-1:0];
    wire [NUM_REQUESTERS-1:0] tileExtWriteValid;
    wire [ADDR_BITS-1:0] tileExtWriteAddress [NUM_REQUESTERS-1:0];
    wire [DATA_WIDTH-1:0] tileExtWriteData [NUM_REQUESTERS-1:0];
    wire [NUM_REQUESTERS-1:0] gatedReadValid;
    assign gatedReadValid = coreReadValid & ~lsuMustStall;
    sramTileBuffer #(
        .NUM_BANKS(NUM_BANKS),
        .BANK_DEPTH(BANK_DEPTH),
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_REQUESTERS(NUM_REQUESTERS),
        .ADDR_BITS(ADDR_BITS)
    ) tileBufferInst (
        .clk(clk),
        .reset(reset),
        .sramBase(sramBaseReg),
        .sramLimit(sramLimitReg),
        .readValid(gatedReadValid),
        .readAddress(coreReadAddress),
        .readReady(sramReadReady),
        .readData(sramReadData),
        .writeValid(coreWriteValid),
        .writeAddress(coreWriteAddress),
        .writeData(coreWriteData),
        .writeReady(sramWriteReady),
        .bankConflict(coreBankConflict),
        .bankPowerEnable(bankPowerEnable | bankTileActive),
        .bankActive(bankActive),
        .externalReadValid(tileExtReadValid),
        .externalReadAddress(tileExtReadAddress),
        .externalWriteValid(tileExtWriteValid),
        .externalWriteAddress(tileExtWriteAddress),
        .externalWriteData(tileExtWriteData)
    );
    powerController #(
        .NUM_BANKS(NUM_BANKS),
        .idleCycles(16),
        .SLEEP_CYCLES(256)
    ) powerCtrlInst (
        .clk(clk),
        .reset(reset),
        .bankActive(bankActive | bankTileActive),
        .forceEnable(forceBankEnable | bankTileActive),
        .forceSleep(forceBankSleep & ~bankTileActive),
        .bankPowerEnable(bankPowerEnable),
        .bankPowerState(bankPowerState),
        .bankNeedsReload(bankNeedsReload),
        .totalIdleCycles(),
        .totalSleepCycles(),
        .stateTransitions(),
        .bankWasActive()
    );
    assign extReadValid = tileExtReadValid;
    assign extReadAddress = tileExtReadAddress;
    assign extWriteValid = tileExtWriteValid;
    assign extWriteAddress = tileExtWriteAddress;
    assign extWriteData = tileExtWriteData;
    genvar m;
    generate
        for (m = 0; m < NUM_REQUESTERS; m = m + 1) begin : responseMux
            assign coreReadReady[m] = sramReadReady[m] | extReadReady[m];
            assign coreReadData[m] = sramReadReady[m] ? sramReadData[m] : extReadData[m];
            assign coreWriteReady[m] = sramWriteReady[m] | extWriteReady[m];
        end
    endgenerate
    always @(posedge clk) begin
        if (reset) begin
            dmaReadReady <= 1'b0;
            dmaReadData <= {DATA_WIDTH{1'b0}};
            dmaWriteReady <= 1'b0;
        end else begin
            dmaReadReady <= dmaReadValid;
            dmaWriteReady <= dmaWriteValid;
        end
    end
endmodule
