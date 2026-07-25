
`default_nettype none
`timescale 1ns/1ns

module prefetch_engine #(
    parameter ADDR_WIDTH   = 22,
    parameter DATA_WIDTH   = 8,
    parameter NUM_ENTRIES  = 8,
    parameter PREFETCH_DIST = 4
) (
    input  wire clk,
    input  wire reset,

    input  wire                    lsu_load_valid,
    input  wire [ADDR_WIDTH-1:0]   lsu_load_addr,

    output reg                     pf_req_valid,
    output reg  [ADDR_WIDTH-1:0]   pf_req_addr,
    input  wire                    pf_req_ready,

    output wire [3:0]              active_streams,
    output reg  [15:0]             pf_issued_count,
    output reg  [15:0]             pf_hit_count
);

    reg                    entry_valid   [NUM_ENTRIES-1:0];
    reg [ADDR_WIDTH-1:0]   entry_last    [NUM_ENTRIES-1:0];
    reg signed [ADDR_WIDTH-1:0] entry_stride [NUM_ENTRIES-1:0];
    reg [3:0]              entry_conf    [NUM_ENTRIES-1:0];
    reg [ADDR_WIDTH-1:0]   entry_pf_addr [NUM_ENTRIES-1:0];

    reg [3:0] active_cnt;
    assign active_streams = active_cnt;

    integer i;
    reg [3:0] temp_active;

    reg [$clog2(NUM_ENTRIES)-1:0] match_idx;
    reg                           match_found;
    reg signed [ADDR_WIDTH-1:0]   observed_stride;

    always @(*) begin
        match_found = 0;
        match_idx = 0;
        observed_stride = 0;
        for (i = NUM_ENTRIES-1; i >= 0; i = i - 1) begin
            if (entry_valid[i]) begin

                if (lsu_load_addr >= entry_last[i]) begin
                    if ((lsu_load_addr - entry_last[i]) < 256) begin
                        match_found = 1;
                        match_idx = i;
                        observed_stride = lsu_load_addr - entry_last[i];
                    end
                end else begin
                    if ((entry_last[i] - lsu_load_addr) < 256) begin
                        match_found = 1;
                        match_idx = i;
                        observed_stride = -$signed(entry_last[i] - lsu_load_addr);
                    end
                end
            end
        end
    end

    reg [$clog2(NUM_ENTRIES)-1:0] free_idx;
    always @(*) begin
        free_idx = 0;
        for (i = NUM_ENTRIES-1; i >= 0; i = i - 1) begin
            if (!entry_valid[i]) free_idx = i;
            else if (entry_conf[i] < entry_conf[free_idx]) free_idx = i;
        end
    end

    reg [$clog2(NUM_ENTRIES)-1:0] pf_rr;
    reg pf_pending;
    reg [ADDR_WIDTH-1:0] pf_pending_addr;

    always @(posedge clk) begin
        if (reset) begin
            pf_req_valid <= 0;
            pf_issued_count <= 0;
            pf_hit_count <= 0;
            pf_pending <= 0;
            pf_rr <= 0;
            active_cnt <= 0;
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                entry_valid[i]   <= 0;
                entry_last[i]    <= 0;
                entry_stride[i]  <= 0;
                entry_conf[i]    <= 0;
                entry_pf_addr[i] <= 0;
            end
        end else begin
            pf_req_valid <= 0;

            if (lsu_load_valid) begin
                if (match_found) begin

                    entry_last[match_idx] <= lsu_load_addr;
                    if (observed_stride == entry_stride[match_idx]) begin

                        if (entry_conf[match_idx] < 15)
                            entry_conf[match_idx] <= entry_conf[match_idx] + 1;

                        entry_pf_addr[match_idx] <= lsu_load_addr +
                            (entry_stride[match_idx] * PREFETCH_DIST);
                    end else begin

                        entry_stride[match_idx] <= observed_stride;
                        entry_conf[match_idx] <= 1;
                    end

                    if (lsu_load_addr == entry_pf_addr[match_idx])
                        pf_hit_count <= pf_hit_count + 1;
                end else begin

                    entry_valid[free_idx]   <= 1;
                    entry_last[free_idx]    <= lsu_load_addr;
                    entry_stride[free_idx]  <= 0;
                    entry_conf[free_idx]    <= 0;
                    entry_pf_addr[free_idx] <= 0;
                end
            end

            if (!pf_pending) begin
                for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                    if (entry_valid[(pf_rr + i) % NUM_ENTRIES] &&
                        entry_conf[(pf_rr + i) % NUM_ENTRIES] >= 4 &&
                        entry_pf_addr[(pf_rr + i) % NUM_ENTRIES] != 0 &&
                        !pf_pending) begin
                        pf_pending <= 1;
                        pf_pending_addr <= entry_pf_addr[(pf_rr + i) % NUM_ENTRIES];
                        pf_rr <= ((pf_rr + i + 1) % NUM_ENTRIES);
                    end
                end
            end

            if (pf_pending) begin
                pf_req_valid <= 1;
                pf_req_addr  <= pf_pending_addr;
                if (pf_req_ready) begin
                    pf_pending <= 0;
                    pf_issued_count <= pf_issued_count + 1;
                end
            end

            temp_active = 0;
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                if (entry_valid[i] && entry_conf[i] >= 4)
                    temp_active = temp_active + 1;
            end
            active_cnt <= temp_active;
        end
    end

endmodule
