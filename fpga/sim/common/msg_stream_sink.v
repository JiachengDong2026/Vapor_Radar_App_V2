`timescale 1ns/1ps
`include "stream_defs.vh"

module msg_stream_sink #(
    parameter integer STALL_EVERY = 0,
    parameter integer STALL_CYCLES = 1,
    parameter integer CHECK_IDS = 0,
    parameter [`STREAM_SOURCE_W-1:0] EXPECTED_SOURCE_ID = {`STREAM_SOURCE_W{1'b0}},
    parameter [`STREAM_MSG_ID_W-1:0] EXPECTED_MSG_ID = {`STREAM_MSG_ID_W{1'b0}}
)(
    input  wire clk,
    input  wire rst_n,
    input  wire valid,
    output wire ready,
    input  wire [`MSG_STREAM_DATA_W-1:0] data,
    input  wire [`MSG_STREAM_KEEP_W-1:0] keep,
    input  wire sof,
    input  wire last,
    input  wire [`STREAM_SOURCE_W-1:0] source_id,
    input  wire [`STREAM_MSG_ID_W-1:0] msg_id,
    input  wire [`STREAM_TIMESTAMP_W-1:0] timestamp,
    input  wire [`STREAM_CYCLE_ID_W-1:0] cycle_id,
    input  wire [`STREAM_FLAGS_W-1:0] flags,
    output reg  [31:0] beat_count,
    output reg  [31:0] msg_count
);
    reg ready_r;
    integer accepted_since_stall;
    integer stall_left;
    reg in_msg;
    reg [`STREAM_SOURCE_W-1:0] frame_source_id;
    reg [`STREAM_MSG_ID_W-1:0] frame_msg_id;
    reg [`STREAM_TIMESTAMP_W-1:0] frame_timestamp;
    reg [`STREAM_CYCLE_ID_W-1:0] frame_cycle_id;
    reg [`STREAM_FLAGS_W-1:0] frame_flags;
    reg [`STREAM_TIMESTAMP_W-1:0] last_message_timestamp;

    reg hold_active;
    reg [`MSG_STREAM_DATA_W-1:0] hold_data;
    reg [`MSG_STREAM_KEEP_W-1:0] hold_keep;
    reg hold_sof, hold_last;
    reg [`STREAM_SOURCE_W-1:0] hold_source_id;
    reg [`STREAM_MSG_ID_W-1:0] hold_msg_id;
    reg [`STREAM_TIMESTAMP_W-1:0] hold_timestamp;
    reg [`STREAM_CYCLE_ID_W-1:0] hold_cycle_id;
    reg [`STREAM_FLAGS_W-1:0] hold_flags;

    assign ready = ready_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ready_r <= 1'b1;
            accepted_since_stall <= 0;
            stall_left <= 0;
            in_msg <= 1'b0;
            beat_count <= 0;
            msg_count <= 0;
            frame_source_id <= 0;
            frame_msg_id <= 0;
            frame_timestamp <= 0;
            frame_cycle_id <= 0;
            frame_flags <= 0;
            last_message_timestamp <= 0;
            hold_active <= 1'b0;
        end else begin
            if (stall_left > 0) begin
                ready_r <= 1'b0;
                stall_left <= stall_left - 1;
            end else begin
                ready_r <= 1'b1;
                if (valid && ready_r && STALL_EVERY > 0) begin
                    if (accepted_since_stall == STALL_EVERY-1) begin
                        accepted_since_stall <= 0;
                        stall_left <= STALL_CYCLES;
                    end else begin
                        accepted_since_stall <= accepted_since_stall + 1;
                    end
                end
            end

            if (hold_active) begin
                if (!valid)
                    $fatal(1, "MSG_VALID_DROPPED_DURING_STALL");
                if (data !== hold_data || keep !== hold_keep || sof !== hold_sof ||
                    last !== hold_last || source_id !== hold_source_id ||
                    msg_id !== hold_msg_id || timestamp !== hold_timestamp ||
                    cycle_id !== hold_cycle_id || flags !== hold_flags)
                    $fatal(1, "MSG_CHANGED_DURING_STALL");
            end

            if (valid && !ready) begin
                if (!hold_active) begin
                    hold_data <= data;
                    hold_keep <= keep;
                    hold_sof <= sof;
                    hold_last <= last;
                    hold_source_id <= source_id;
                    hold_msg_id <= msg_id;
                    hold_timestamp <= timestamp;
                    hold_cycle_id <= cycle_id;
                    hold_flags <= flags;
                end
                hold_active <= 1'b1;
            end else if (valid && ready) begin
                hold_active <= 1'b0;
            end else if (!valid) begin
                hold_active <= 1'b0;
            end

            if (valid && ready) begin
                beat_count <= beat_count + 1'b1;

                if (CHECK_IDS != 0) begin
                    if (source_id !== EXPECTED_SOURCE_ID)
                        $fatal(1, "MSG_SOURCE_ID_MISMATCH expected=%h actual=%h", EXPECTED_SOURCE_ID, source_id);
                    if (msg_id !== EXPECTED_MSG_ID)
                        $fatal(1, "MSG_ID_MISMATCH expected=%h actual=%h", EXPECTED_MSG_ID, msg_id);
                end

                if (!last && keep !== {`MSG_STREAM_KEEP_W{1'b1}})
                    $fatal(1, "MSG_KEEP_NONFULL_BEFORE_LAST keep=%h", keep);
                if (last && keep == {`MSG_STREAM_KEEP_W{1'b0}})
                    $fatal(1, "MSG_LAST_KEEP_ZERO");

                if (sof) begin
                    if (in_msg)
                        $fatal(1, "MSG_NESTED_SOF");
                    if (msg_count != 0 && timestamp < last_message_timestamp)
                        $fatal(1, "MSG_TIMESTAMP_DECREASE previous=%0d current=%0d", last_message_timestamp, timestamp);
                    frame_source_id <= source_id;
                    frame_msg_id <= msg_id;
                    frame_timestamp <= timestamp;
                    frame_cycle_id <= cycle_id;
                    frame_flags <= flags;
                    if (!last)
                        in_msg <= 1'b1;
                end else begin
                    if (!in_msg)
                        $fatal(1, "MSG_BEAT_OUTSIDE_MESSAGE");
                    if (source_id !== frame_source_id || msg_id !== frame_msg_id ||
                        timestamp !== frame_timestamp || cycle_id !== frame_cycle_id ||
                        flags !== frame_flags)
                        $fatal(1, "MSG_METADATA_CHANGED_WITHIN_MESSAGE");
                end

                if (last) begin
                    if (!sof && !in_msg)
                        $fatal(1, "MSG_LAST_WITHOUT_MESSAGE");
                    in_msg <= 1'b0;
                    msg_count <= msg_count + 1'b1;
                    last_message_timestamp <= timestamp;
                end

                $display("MSG beat=%0d source=0x%04h msg=0x%04h sof=%b last=%b data=%h",
                         beat_count, source_id, msg_id, sof, last, data);
            end
        end
    end
endmodule
