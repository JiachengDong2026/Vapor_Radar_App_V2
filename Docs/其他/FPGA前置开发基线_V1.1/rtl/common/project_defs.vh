`ifndef VAPOR_LIDAR_PROJECT_DEFS_VH
`define VAPOR_LIDAR_PROJECT_DEFS_VH

`define SYS_CLK_HZ                  32'd100000000
`define TIME_CLK_HZ                 32'd100000000
`define TIMESTAMP_WIDTH             64
`define CYCLE_ID_WIDTH              32
`define CFG_ADDR_WIDTH              32
`define CFG_DATA_WIDTH              32
`define SAMPLE_DATA_WIDTH           32
`define SAMPLE_FLAGS_WIDTH          8
`define MSG_DATA_WIDTH              32
`define MSG_KEEP_WIDTH              4
`define BULK_DATA_WIDTH             32
`define BULK_KEEP_WIDTH             4
`define SOURCE_ID_WIDTH             16
`define MSG_ID_WIDTH                16

// V1.1 buffering / fragmentation baseline
`define MSG_MAX_PAYLOAD_BYTES       32'd1024
`define BULK_FRAGMENT_MAX_BYTES     32'd8192
`define DILA_FRAGMENT_POINTS_DEFAULT 32'd256
`define ARB_MAX_HIGH_BURST_DEFAULT  32'd4

// source_id
`define SRC_SYSTEM              16'h0001
`define SRC_TIME                16'h0002
`define SRC_WMS0                16'h0010
`define SRC_WMS1                16'h0011
`define SRC_ADC0                16'h0020
`define SRC_ADC1                16'h0021
`define SRC_DILA0               16'h0030
`define SRC_DILA1               16'h0031
`define SRC_PTB210              16'h0040
`define SRC_HMP                 16'h0041
`define SRC_EPSILON2            16'h0042
`define SRC_BMP390              16'h0043
`define SRC_SHT45               16'h0044
`define SRC_TFA1500             16'h0045
`define SRC_RD105               16'h0046
`define SRC_STEPPER             16'h0047
`define SRC_DIAGNOSTICS         16'h0050
`define SRC_BROADCAST           16'hFFFF

// msg_id (used by both msg_stream and bulk_stream)
`define MSG_ADC_RAW_CYCLE       16'h1000
`define MSG_DILA_BLOCK          16'h1001
`define MSG_SENSOR_TLV_RECORD   16'h1100
`define MSG_GNSS_FDILINK_RAW    16'h1200
`define MSG_TIME_SYNC_EVENT     16'h1201
`define MSG_MOTOR_STATUS        16'h1300
`define MSG_SYSTEM_STATUS       16'h1400
`define MSG_MODULE_STATUS       16'h1401
`define MSG_ERROR_EVENT         16'h1402

// arbitration classes
`define ARB_PRIO_P0             2'd0
`define ARB_PRIO_P1             2'd1
`define ARB_PRIO_P2             2'd2
`define ARB_PRIO_P3             2'd3

// DILA V2 point formats
`define DILA_FMT_H1_H2          16'd0
`define DILA_FMT_IQ             16'd1
`define DILA_FMT_IQ_MAG         16'd2

`define CYCLE_ID_NONE           32'hFFFF_FFFF

`endif
