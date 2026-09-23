`timescale 1ns/1ps
// Single-master open-drain transaction engine. Byte zero is packed at bit 7:0.
// A write followed by a read uses a repeated START. Read-only transactions work.
module i2c_master #(
    parameter integer SYS_CLK_HZ=100000000,
    parameter integer I2C_HZ=100000,
    parameter integer TIMEOUT_TICKS=1000000
)(
    input wire sys_clk, rst_sys_n,
    input wire req_valid, output wire req_ready,
    input wire [6:0] req_addr,
    input wire [5:0] req_write_len, req_read_len,
    input wire [255:0] req_write_data,
    output reg done, output reg [2:0] error,
    output reg [255:0] read_data,
    input wire scl_i, sda_i,
    output reg scl_drive_low, sda_drive_low,
    output wire busy
);
    localparam integer QUARTER=(SYS_CLK_HZ/(I2C_HZ*4)>1)?SYS_CLK_HZ/(I2C_HZ*4):2;
    localparam IDLE=0, START=1, SEND=2, ACK=3, RESTART=4,
        READ=5, READ_ACK=6, STOP=7, RECOVER=8;
    reg [3:0] state;
    reg [1:0] phase;
    reg [31:0] divider, watchdog;
    reg [6:0] address;
    reg [5:0] write_len, read_len, index;
    reg [255:0] write_data;
    reg [7:0] shift;
    reg [2:0] bit_index;
    reg direction, address_byte;
    reg [3:0] recovery_count;
    (* ASYNC_REG="TRUE" *) reg scl_meta,scl_sync,sda_meta,sda_sync;
    assign req_ready=state==IDLE;
    assign busy=state!=IDLE;
    always @(posedge sys_clk) begin
        scl_meta<=scl_i; scl_sync<=scl_meta; sda_meta<=sda_i; sda_sync<=sda_meta;
    end
    always @(posedge sys_clk) begin
        if(!rst_sys_n) begin
            state<=IDLE; phase<=0; divider<=0; watchdog<=0; done<=0; error<=0;
            scl_drive_low<=0; sda_drive_low<=0; read_data<=0; address<=0;
            write_len<=0; read_len<=0; write_data<=0; shift<=0; index<=0;
            bit_index<=7; direction<=0; address_byte<=1; recovery_count<=0;
        end else begin
            done<=0;
            if(state==IDLE) begin
                scl_drive_low<=0; sda_drive_low<=0; divider<=0; watchdog<=0;
                if(req_valid) begin
                    error<=0; read_data<=0; address<=req_addr;
                    write_len<=req_write_len; read_len<=req_read_len;
                    write_data<=req_write_data; index<=0; phase<=0;
                    direction<=req_write_len==0; address_byte<=1; bit_index<=7;
                    shift<={req_addr,req_write_len==0};
                    if(req_write_len>32 || req_read_len>32 || (req_write_len==0 && req_read_len==0)) begin
                        error<=3; done<=1;
                    end else if(!sda_sync || !scl_sync) begin
                        state<=RECOVER; recovery_count<=0; error<=4;
                    end else state<=START;
                end
            end else if(watchdog>=TIMEOUT_TICKS-1) begin
                state<=IDLE; scl_drive_low<=0; sda_drive_low<=0; error<=2; done<=1;
            end else begin
                watchdog<=watchdog+1'b1;
                // Hold the high phase until physical SCL rises (clock stretching).
                if(!scl_drive_low && !scl_sync && phase!=0) divider<=0;
                else if(divider<QUARTER-1) divider<=divider+1'b1;
                else begin
                    divider<=0;
                    case(state)
                        START: case(phase)
                            0: begin sda_drive_low<=0; scl_drive_low<=0; phase<=1; end
                            1: begin sda_drive_low<=1; phase<=2; end
                            2: phase<=3;
                            3: begin scl_drive_low<=1; state<=SEND; phase<=0; end
                        endcase
                        SEND: case(phase)
                            0: begin scl_drive_low<=1; sda_drive_low<=!shift[bit_index]; phase<=1; end
                            1: begin scl_drive_low<=0; phase<=2; end
                            2: phase<=3;
                            3: begin
                                scl_drive_low<=1; phase<=0;
                                if(bit_index==0) state<=ACK;
                                else bit_index<=bit_index-1'b1;
                            end
                        endcase
                        ACK: case(phase)
                            0: begin sda_drive_low<=0; phase<=1; end
                            1: begin scl_drive_low<=0; phase<=2; end
                            2: begin if(sda_sync) error<=1; phase<=3; end
                            3: begin
                                scl_drive_low<=1; phase<=0; bit_index<=7;
                                if(error!=0) state<=STOP;
                                else if(address_byte) begin
                                    address_byte<=0; index<=0;
                                    if(direction) state<=READ;
                                    else begin shift<=write_data[7:0]; state<=SEND; end
                                end else if(index+1<write_len) begin
                                    index<=index+1'b1; shift<=write_data[(index+1)*8+:8]; state<=SEND;
                                end else if(read_len!=0) begin
                                    state<=RESTART; direction<=1; address_byte<=1;
                                    shift<={address,1'b1}; index<=0;
                                end else state<=STOP;
                            end
                        endcase
                        RESTART: case(phase)
                            0: begin sda_drive_low<=0; phase<=1; end
                            1: begin scl_drive_low<=0; phase<=2; end
                            2: begin sda_drive_low<=1; phase<=3; end
                            3: begin scl_drive_low<=1; phase<=0; state<=SEND; end
                        endcase
                        READ: case(phase)
                            0: begin sda_drive_low<=0; phase<=1; end
                            1: begin scl_drive_low<=0; phase<=2; end
                            2: begin shift[bit_index]<=sda_sync; phase<=3; end
                            3: begin
                                scl_drive_low<=1; phase<=0;
                                if(bit_index==0) begin read_data[index*8+:8]<=shift; state<=READ_ACK; end
                                else bit_index<=bit_index-1'b1;
                            end
                        endcase
                        READ_ACK: case(phase)
                            0: begin sda_drive_low<=index+1<read_len; phase<=1; end
                            1: begin scl_drive_low<=0; phase<=2; end
                            2: phase<=3;
                            3: begin
                                scl_drive_low<=1; phase<=0; bit_index<=7;
                                if(index+1>=read_len) state<=STOP;
                                else begin index<=index+1'b1; state<=READ; end
                            end
                        endcase
                        STOP: case(phase)
                            0: begin scl_drive_low<=1; sda_drive_low<=1; phase<=1; end
                            1: begin scl_drive_low<=0; phase<=2; end
                            2: begin sda_drive_low<=0; phase<=3; end
                            3: begin state<=IDLE; done<=1; end
                        endcase
                        RECOVER: case(phase)
                            0: begin sda_drive_low<=0; scl_drive_low<=1; phase<=1; end
                            1: begin scl_drive_low<=0; phase<=2; end
                            2: phase<=3;
                            3: begin
                                phase<=0;
                                if(recovery_count==8) state<=STOP;
                                else recovery_count<=recovery_count+1'b1;
                            end
                        endcase
                        default: state<=IDLE;
                    endcase
                end
            end
        end
    end
endmodule
