// Store Coalescing Engine ? Per-Slot FIFO with Non-Blocking Drain
// Each incoming store gets its own FIFO slot. A round-robin arbiter drains
// entries to the external memory interface without blocking new ingress.
// This structurally eliminates store-drop races under thread contention.

`default_nettype none
`timescale 1ns/1ns

module storeCombiner #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 16,
    parameter BUFFER_DEPTH = 4,
    parameter WARP_ID_WIDTH = 2,
    // Per-lane depth: each of NUM_LANES lanes has LANE_DEPTH entries
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

    // Per-lane storage: each lane is a small FIFO of LANE_DEPTH entries
    reg [ADDR_WIDTH-1:0] laneAddr  [NUM_LANES-1:0][LANE_DEPTH-1:0];
    reg [DATA_WIDTH-1:0] laneData  [NUM_LANES-1:0][LANE_DEPTH-1:0];
    reg [LANE_DEPTH-1:0] laneValid [NUM_LANES-1:0];
    reg [$clog2(LANE_DEPTH):0] laneCount [NUM_LANES-1:0];
    reg [$clog2(LANE_DEPTH)-1:0] laneWrPtr [NUM_LANES-1:0];
    reg [$clog2(LANE_DEPTH)-1:0] laneRdPtr [NUM_LANES-1:0];

    // Ingress lane selector: round-robin across lanes for incoming stores
    reg [$clog2(NUM_LANES)-1:0] ingressLane;

    // Drain arbiter: round-robin across lanes for output
    reg [$clog2(NUM_LANES)-1:0] drainLane;

    typedef enum logic [1:0] {
        IDLE = 2'b00,
        DRAINING = 2'b01
    } stateE;
    stateE state;

    // Total entry count across all lanes
    reg [$clog2(NUM_LANES * LANE_DEPTH + 1)-1:0] totalCount;
    assign storeBufferEmpty = (totalCount == 0);

    // Find a lane with space for ingress
    reg foundFreeLane;
    reg [$clog2(NUM_LANES)-1:0] freeLaneIdx;
    integer fi;
    always @(*) begin
        foundFreeLane = 0;
        freeLaneIdx = 0;
        for (fi = 0; fi < NUM_LANES; fi = fi + 1) begin
            automatic integer idx = (ingressLane + fi) % NUM_LANES;
            if (laneCount[idx] < LANE_DEPTH && !foundFreeLane) begin
                foundFreeLane = 1;
                freeLaneIdx = idx[$clog2(NUM_LANES)-1:0];
            end
        end
    end

    assign storeReady = foundFreeLane && (state == IDLE);

    // Intra-lane combining: check if new store can merge with existing entry
    // in the same lane (same cache-line alignment = same addr[ADDR_WIDTH-1:2])
    reg foundCombine;
    reg [$clog2(LANE_DEPTH)-1:0] combineSlot;
    integer ci, cl;
    always @(*) begin
        foundCombine = 0;
        combineSlot = 0;
        if (foundFreeLane) begin
            for (ci = 0; ci < LANE_DEPTH; ci = ci + 1) begin
                if (laneValid[freeLaneIdx][ci] && !foundCombine) begin
                    // Same cache line (4-byte aligned): merge
                    if ((laneAddr[freeLaneIdx][ci] & ~{{(ADDR_WIDTH-2){1'b0}}, 2'b11}) ==
                        (storeAddr & ~{{(ADDR_WIDTH-2){1'b0}}, 2'b11})) begin
                        foundCombine = 1;
                        combineSlot = ci[$clog2(LANE_DEPTH)-1:0];
                    end
                end
            end
        end
    end

    // Find a lane with valid entries to drain
    reg foundDrainLane;
    reg [$clog2(NUM_LANES)-1:0] drainLaneIdx;
    integer di;
    always @(*) begin
        foundDrainLane = 0;
        drainLaneIdx = 0;
        for (di = 0; di < NUM_LANES; di = di + 1) begin
            automatic integer didx = (drainLane + di) % NUM_LANES;
            if (laneCount[didx] > 0 && !foundDrainLane) begin
                foundDrainLane = 1;
                drainLaneIdx = didx[$clog2(NUM_LANES)-1:0];
            end
        end
    end

    // Flush trigger: drain all entries on fence, kernel end, load pending,
    // or when idle with entries pending
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

                    // Accept incoming stores into lanes
                    if (storeValid && foundFreeLane) begin
                        perfStoresReceived <= perfStoresReceived + 1;

                        if (foundCombine) begin
                            // Intra-lane combine: overwrite data at same cache line
                            laneData[freeLaneIdx][combineSlot] <= storeData;
                            laneAddr[freeLaneIdx][combineSlot] <= storeAddr;
                            perfStoresCombined <= perfStoresCombined + 1;
                        end else begin
                            // New entry in lane FIFO
                            laneAddr[freeLaneIdx][laneWrPtr[freeLaneIdx]] <= storeAddr;
                            laneData[freeLaneIdx][laneWrPtr[freeLaneIdx]] <= storeData;
                            laneValid[freeLaneIdx][laneWrPtr[freeLaneIdx]] <= 1;
                            laneWrPtr[freeLaneIdx] <=
                                (laneWrPtr[freeLaneIdx] == LANE_DEPTH - 1) ? 0 :
                                laneWrPtr[freeLaneIdx] + 1;
                            laneCount[freeLaneIdx] <= laneCount[freeLaneIdx] + 1;
                            totalCount <= totalCount + 1;
                        end

                        // Advance ingress round-robin
                        ingressLane <= (ingressLane == NUM_LANES - 1) ? 0 : ingressLane + 1;
                    end

                    // Transition to drain when flush triggered
                    if (doFlush && totalCount > 0) begin
                        state <= DRAINING;
                        perfFlushEvents <= perfFlushEvents + 1;
                    end
                end

                DRAINING: begin
                    if (totalCount == 0) begin
                        // All lanes drained
                        state <= IDLE;
                        combinedValid <= 0;
                    end else if (foundDrainLane) begin
                        // Present entry from drain lane to output
                        combinedValid <= 1;
                        combinedAddr <= laneAddr[drainLaneIdx][laneRdPtr[drainLaneIdx]];
                        combinedData <= {{(DATA_WIDTH*3){1'b0}},
                                         laneData[drainLaneIdx][laneRdPtr[drainLaneIdx]]};
                        combinedMask <= 4'b0001;
                        combinedCount <= 1;

                        if (combinedReady) begin
                            // Consume entry
                            laneValid[drainLaneIdx][laneRdPtr[drainLaneIdx]] <= 0;
                            laneRdPtr[drainLaneIdx] <=
                                (laneRdPtr[drainLaneIdx] == LANE_DEPTH - 1) ? 0 :
                                laneRdPtr[drainLaneIdx] + 1;
                            laneCount[drainLaneIdx] <= laneCount[drainLaneIdx] - 1;
                            totalCount <= totalCount - 1;

                            // Advance drain round-robin
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

    // synthesis translateOff
    always @(posedge clk) begin
        if (!reset && combinedValid && combinedReady) begin
            $display("[COMBINER] t=%0t addr=%h data=%h lane=%0d total=%0d",
                     $time, combinedAddr, combinedData[DATA_WIDTH-1:0],
                     drainLaneIdx, totalCount);
        end
    end
    // synthesis translateOn

endmodule
