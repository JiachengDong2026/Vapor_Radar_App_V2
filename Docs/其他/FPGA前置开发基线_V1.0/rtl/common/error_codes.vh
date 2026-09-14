`ifndef VAPOR_LIDAR_ERROR_CODES_VH
`define VAPOR_LIDAR_ERROR_CODES_VH

`define ERR_BIT_TIMEOUT                 0
`define ERR_BIT_PROTOCOL_OR_CRC         1
`define ERR_BIT_FIFO_OVERFLOW           2
`define ERR_BIT_DEVICE_NOT_READY        3
`define ERR_BIT_CONFIG_RANGE            4
`define ERR_BIT_CDC_OR_INTERNAL         5
`define ERR_BIT_DEVICE_REPORTED_ERROR   6
`define ERR_BIT_DATA_FORMAT             7

`define ERR_TIMEOUT                 32'h0000_0001
`define ERR_PROTOCOL_OR_CRC         32'h0000_0002
`define ERR_FIFO_OVERFLOW           32'h0000_0004
`define ERR_DEVICE_NOT_READY        32'h0000_0008
`define ERR_CONFIG_RANGE            32'h0000_0010
`define ERR_CDC_OR_INTERNAL         32'h0000_0020
`define ERR_DEVICE_REPORTED_ERROR   32'h0000_0040
`define ERR_DATA_FORMAT             32'h0000_0080

`endif
