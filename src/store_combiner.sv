
`default_nettype none
`timescale 1ns/1ps

// Store combiner merging multiple narrow store operations into wider aligned writes to reduce memory bandwidth pressure.
module storeCombiner #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 16,
    parameter BUFFER_DEPTH = 4,
    parameter WARP_ID_WIDTH = 2,
    parameter NUM_LANES = 4,
    parameter LANE_DEPTH = 2
) (
    input wire clk,
    input wire reset,
    input wire storeValid,
    input wire [ADDR_WIDTH-1:0] storeAddr,
    input wire [DATA_WIDTH-1:0] storeData,
    input wire [WARP_ID_WIDTH-1:0] storeWarpId,
    output wire storeReady,
    input wire fenceInstruction,
    input wire kernelEnd,
    input wire loadPending,
    output reg combinedValid,
    output reg [ADDR_WIDTH-1:0] combinedAddr,
    output reg [DATA_WIDTH*4-1:0] combinedData,
    output reg [3:0] combinedMask,
    output reg [2:0] combinedCount,
    input wire combinedReady,
    output reg [31:0] perfStoresReceived,
    output reg [31:0] perfStoresCombined,
    output reg [31:0] perfFlushEvents,
    output wire storeBufferEmpty
);

    reg [ADDR_WIDTH-1:0] laneAddr  [NUM_LANES-1:0][LANE_DEPTH-1:0];
    reg [DATA_WIDTH-1:0] laneData  [NUM_LANES-1:0][LANE_DEPTH-1:0];
    reg [LANE_DEPTH-1:0] laneValid [NUM_LANES-1:0];
    reg [$clog2(LANE_DEPTH):0] laneCount [NUM_LANES-1:0];
    reg [$clog2(LANE_DEPTH)-1:0] laneWrPtr [NUM_LANES-1:0];
    reg [$clog2(LANE_DEPTH)-1:0] laneRdPtr [NUM_LANES-1:0];

    reg [$clog2(NUM_LANES)-1:0] ingressLane;

    reg [$clog2(NUM_LANES)-1:0] drainLane;

    typedef enum logic [1:0] {
        IDLE = 2'b00,
        DRAINING = 2'b01
    } stateE;
    stateE state;

    reg [$clog2(NUM_LANES * LANE_DEPTH + 1)-1:0] totalCount;
    assign storeBufferEmpty = (totalCount == 0);

    reg foundFreeLane;
    reg [$clog2(NUM_LANES)-1:0] freeLaneIdx;
    integer fi;

    function automatic integer wrap_lane(integer base, integer offset);
        automatic integer raw = base + offset;
        return (raw >= NUM_LANES) ? (raw - NUM_LANES) : raw;
    endfunction

    always_comb begin
        foundFreeLane = 0;
        freeLaneIdx = 0;
        for (fi = 0; fi < NUM_LANES; fi = fi + 1) begin
            automatic integer idx = wrap_lane(ingressLane, fi);
            if (laneCount[idx] < LANE_DEPTH && !foundFreeLane) begin
                foundFreeLane = 1;
                freeLaneIdx = idx[$clog2(NUM_LANES)-1:0];
            end
        end
    end

    assign storeReady = foundFreeLane && (state == IDLE);

    reg foundCombine;
    reg [$clog2(LANE_DEPTH)-1:0] combineSlot;
    integer ci, cl;
    always_comb begin
        foundCombine = 0;
        combineSlot = 0;
        if (foundFreeLane) begin
            for (ci = 0; ci < LANE_DEPTH; ci = ci + 1) begin
                if (laneValid[freeLaneIdx][ci] && !foundCombine) begin
                    if ((laneAddr[freeLaneIdx][ci] & ~{{(ADDR_WIDTH-2){1'b0}}, 2'b11}) ==
                        (storeAddr & ~{{(ADDR_WIDTH-2){1'b0}}, 2'b11})) begin
                        foundCombine = 1;
                        combineSlot = ci[$clog2(LANE_DEPTH)-1:0];
                    end
                end
            end
        end
    end

    reg foundDrainLane;
    reg [$clog2(NUM_LANES)-1:0] drainLaneIdx;
    integer di;
    always_comb begin
        foundDrainLane = 0;
        drainLaneIdx = 0;
        for (di = 0; di < NUM_LANES; di = di + 1) begin
            automatic integer didx = wrap_lane(drainLane, di);
            if (laneCount[didx] > 0 && !foundDrainLane) begin
                foundDrainLane = 1;
                drainLaneIdx = didx[$clog2(NUM_LANES)-1:0];
            end
        end
    end

    wire doFlush = fenceInstruction || kernelEnd || loadPending ||
                    (totalCount == NUM_LANES * LANE_DEPTH) ||
                    (!storeValid && totalCount > 0);

    integer li, si;
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            combinedValid <= 0;
            combinedAddr <= 0;
            combinedData <= 0;
            combinedMask <= 0;
            combinedCount <= 0;
            ingressLane <= 0;
            drainLane <= 0;
            totalCount <= 0;
            perfStoresReceived <= 0;
            perfStoresCombined <= 0;
            perfFlushEvents <= 0;
            for (li = 0; li < NUM_LANES; li = li + 1) begin
                laneValid[li] <= 0;
                laneCount[li] <= 0;
                laneWrPtr[li] <= 0;
                laneRdPtr[li] <= 0;
                for (si = 0; si < LANE_DEPTH; si = si + 1) begin
                    laneAddr[li][si] <= 0;
                    laneData[li][si] <= 0;
                end
            end
        end else begin
            case (state)
                IDLE: begin
                    combinedValid <= 0;

                    if (storeValid && foundFreeLane) begin
                        perfStoresReceived <= perfStoresReceived + 1;

                        if (foundCombine) begin
                            laneData[freeLaneIdx][combineSlot] <= storeData;
                            laneAddr[freeLaneIdx][combineSlot] <= storeAddr;
                            perfStoresCombined <= perfStoresCombined + 1;
                        end else begin
                            $display("[COMBINER_PUSH] t=%0t addr=%h data=%h lane=%0d total=%0d", 
                                     $time, storeAddr, storeData, freeLaneIdx, totalCount);
                            laneAddr[freeLaneIdx][laneWrPtr[freeLaneIdx]] <= storeAddr;
                            laneData[freeLaneIdx][laneWrPtr[freeLaneIdx]] <= storeData;
                            laneValid[freeLaneIdx][laneWrPtr[freeLaneIdx]] <= 1;
                            laneWrPtr[freeLaneIdx] <=
                                (laneWrPtr[freeLaneIdx] == LANE_DEPTH - 1) ? 0 :
                                laneWrPtr[freeLaneIdx] + 1;
                            laneCount[freeLaneIdx] <= laneCount[freeLaneIdx] + 1;
                            totalCount <= totalCount + 1;
                        end

                        ingressLane <= (ingressLane == NUM_LANES - 1) ? 0 : ingressLane + 1;
                    end

                    if (doFlush && totalCount > 0) begin
                        state <= DRAINING;
                        perfFlushEvents <= perfFlushEvents + 1;
                    end
                end

                DRAINING: begin
                    if (totalCount == 0) begin
                        state <= IDLE;
                        combinedValid <= 0;
                    end else if (foundDrainLane) begin
                        combinedValid <= 1;
                        combinedAddr <= laneAddr[drainLaneIdx][laneRdPtr[drainLaneIdx]];
                        combinedData <= {{(DATA_WIDTH*3){1'b0}},
                                         laneData[drainLaneIdx][laneRdPtr[drainLaneIdx]]};
                        combinedMask <= 4'b0001;
                        combinedCount <= 1;

                        if (combinedReady) begin
                            laneValid[drainLaneIdx][laneRdPtr[drainLaneIdx]] <= 0;
                            laneRdPtr[drainLaneIdx] <=
                                (laneRdPtr[drainLaneIdx] == LANE_DEPTH - 1) ? 0 :
                                laneRdPtr[drainLaneIdx] + 1;
                            laneCount[drainLaneIdx] <= laneCount[drainLaneIdx] - 1;
                            totalCount <= totalCount - 1;

                            drainLane <= (drainLane == NUM_LANES - 1) ? 0 : drainLane + 1;
                        end
                    end else begin
                        combinedValid <= 0;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    always @(posedge clk) begin
        if (!reset && combinedValid && combinedReady) begin
            $display("[COMBINER] t=%0t addr=%h data=%h lane=%0d total=%0d",
                     $time, combinedAddr, combinedData[DATA_WIDTH-1:0],
                     drainLaneIdx, totalCount);
        end
    end

endmodule
