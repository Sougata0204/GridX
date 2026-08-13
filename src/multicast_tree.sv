
`default_nettype none
`timescale 1ns/1ns

module multicastTree #(
    parameter NUM_GROUPS   = 16,
    parameter MAX_TARGETS  = 8,
    parameter FLIT_WIDTH   = 512,
    parameter GROUP_ID_W   = 4
) (
    input  wire clk,
    input  wire reset,

    input  wire                         cfgValid,
    input  wire [GROUP_ID_W-1:0]        cfgGroupId,
    input  wire [MAX_TARGETS-1:0]       cfgTargetMask,
    input  wire                         cfgEnable,

    input  wire                         flitInValid,
    input  wire [FLIT_WIDTH-1:0]        flitInData,
    input  wire [GROUP_ID_W-1:0]        flitInGroupId,
    input  wire                         flitInIsMulticast,

    output reg                          flitOutValid,
    output reg  [FLIT_WIDTH-1:0]        flitOutData,
    output reg  [$clog2(MAX_TARGETS)-1:0] flitOutTargetId,
    input  wire                         flitOutReady,

    output wire                         busy,
    output reg  [15:0]                  multicastCount
);

    reg [MAX_TARGETS-1:0] groupMask   [NUM_GROUPS-1:0];
    reg [NUM_GROUPS-1:0]  groupActive;

    reg                          replActive;
    reg [FLIT_WIDTH-1:0]         replData;
    reg [MAX_TARGETS-1:0]        replRemaining;
    reg [$clog2(MAX_TARGETS)-1:0] replCurrent;

    assign busy = replActive;

    integer i;

    reg [$clog2(MAX_TARGETS)-1:0] nextTarget;
    reg                           nextFound;
    always @(*) begin
        nextFound = 0;
        nextTarget = 0;
        for (i = 0; i < MAX_TARGETS; i = i + 1) begin
            if (replRemaining[i] && !nextFound) begin
                nextFound = 1;
                nextTarget = i;
            end
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            replActive <= 0;
            flitOutValid <= 0;
            multicastCount <= 0;
            groupActive <= 0;
            for (i = 0; i < NUM_GROUPS; i = i + 1) begin
                groupMask[i] <= 0;
            end
        end else begin
            flitOutValid <= 0;

            if (cfgValid) begin
                groupMask[cfgGroupId] <= cfgTargetMask;
                groupActive[cfgGroupId] <= cfgEnable;
            end

            if (flitInValid && flitInIsMulticast && !replActive) begin
                if (groupActive[flitInGroupId]) begin
                    replActive <= 1;
                    replData <= flitInData;
                    replRemaining <= groupMask[flitInGroupId];
                    multicastCount <= multicastCount + 1;
                end
            end

            if (replActive) begin
                if (nextFound) begin
                    flitOutValid <= 1;
                    flitOutData <= replData;
                    flitOutTargetId <= nextTarget;
                    replCurrent <= nextTarget;

                    if (flitOutReady) begin
                        replRemaining[nextTarget] <= 0;
                    end
                end else begin

                    replActive <= 0;
                end
            end
        end
    end

endmodule
