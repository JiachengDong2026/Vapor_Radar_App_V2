`ifndef VAPOR_LIDAR_STREAM_DEFS_VH
`define VAPOR_LIDAR_STREAM_DEFS_VH

// Do not duplicate numeric widths here. project_defs.vh is the single source
// of truth; this file only provides stream-specific aliases used by reusable
// RTL and simulation components.
`include "project_defs.vh"

`define SAMPLE_STREAM_DATA_W   `SAMPLE_DATA_WIDTH
`define SAMPLE_STREAM_FLAGS_W  `SAMPLE_FLAGS_WIDTH

`define MSG_STREAM_DATA_W      `MSG_DATA_WIDTH
`define MSG_STREAM_KEEP_W      `MSG_KEEP_WIDTH

`define BULK_STREAM_DATA_W     `BULK_DATA_WIDTH
`define BULK_STREAM_KEEP_W     `BULK_KEEP_WIDTH

`define STREAM_SOURCE_W        `SOURCE_ID_WIDTH
`define STREAM_MSG_ID_W        `MSG_ID_WIDTH
`define STREAM_TIMESTAMP_W     `TIMESTAMP_WIDTH
`define STREAM_CYCLE_ID_W      `CYCLE_ID_WIDTH
`define STREAM_FLAGS_W         `STREAM_FLAGS_WIDTH

`endif
