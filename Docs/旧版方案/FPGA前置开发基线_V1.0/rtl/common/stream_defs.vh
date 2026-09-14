`ifndef VAPOR_LIDAR_STREAM_DEFS_VH
`define VAPOR_LIDAR_STREAM_DEFS_VH

// sample_stream flags
`define SAMPLE_FLAG_OVERRANGE_BIT       0
`define SAMPLE_FLAG_DEVICE_ERROR_BIT    1

// Common CONTROL bits
`define CTRL_ENABLE_BIT                 0
`define CTRL_SOFT_RESET_BIT             1
`define CTRL_COMMIT_BIT                 2
`define CTRL_CLEAR_FIFO_BIT             3

// Common STATUS bits
`define STATUS_ENABLED_BIT              0
`define STATUS_READY_BIT                1
`define STATUS_CFG_PENDING_BIT          2
`define STATUS_BUSY_BIT                 3
`define STATUS_ONLINE_BIT               4
`define STATUS_FIFO_ALMOST_FULL_BIT     5
`define STATUS_OVERFLOW_BIT             6
`define STATUS_ERROR_BIT                7
`define STATUS_TIME_SYNC_VALID_BIT      8

// WMS phase is U0.32 turn phase: 2^32 == 2*pi
`define WMS_PHASE_WIDTH                 32
`define WMS_PHASE_0                     32'h0000_0000
`define WMS_PHASE_PI_2                  32'h4000_0000
`define WMS_PHASE_PI                    32'h8000_0000
`define WMS_PHASE_3PI_2                 32'hC000_0000

`endif
