`ifndef SENSOR_CFG_CODES_VH
`define SENSOR_CFG_CODES_VH
// VLP command status values. Device protocol errors are a separate namespace.
`define SENSOR_CFG_OK            4'd0
`define SENSOR_CFG_BAD_ADDRESS   4'd5
`define SENSOR_CFG_READ_ONLY     4'd6
`define SENSOR_CFG_RANGE         4'd7
`define SENSOR_CFG_BUSY          4'd8
`define SENSOR_CFG_TIMEOUT       4'd9
`endif
