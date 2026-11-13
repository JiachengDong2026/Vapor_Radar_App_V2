`timescale 1ns/1ps
module tb_hc2a_sensor_bank_select;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,cfg_valid=0,cfg_write=0;
    reg [31:0] cfg_addr=0,cfg_wdata=0;
    wire cfg_ready,cfg_error;
    wire [31:0] cfg_rdata;
    wire [27:0] cfg_error_code;
    wire [6:0] m_valid,online;
    wire [223:0] m_data,m_cycle,m_flags,device_error,device_drop_count,device_fifo_level;
    wire [27:0] m_keep;
    wire [6:0] m_sof,m_last;
    wire [111:0] m_source_id,m_msg_id;
    wire [447:0] m_timestamp;
    wire hc2a_txd;
    wire ptb_txd,rs485_txd,rs485_de,epsilon_txd,epsilon_correction_txd,tfa_txd;
    wire scl_drive_low,sda_drive_low;
    wire [63:0] gnss_time_tag;
    wire gnss_time_tag_valid;
    integer checks=0;
    member3_sensor_bank #(.SYS_CLK_HZ(1000000),.FIFO_DEPTH(16),.PTB_BOOT_MS(1)) dut(
        .sys_clk(clk),.rst_sys_n(rst_n),.timestamp_now(64'd0),.time_sync_valid(1'b0),.time_sync_seq(32'd0),.sync_event_pulse(1'b0),
        .cfg_valid(cfg_valid),.cfg_write(cfg_write),.cfg_addr(cfg_addr),.cfg_wdata(cfg_wdata),.cfg_wstrb(4'hf),
        .cfg_ready(cfg_ready),.cfg_error(cfg_error),.cfg_rdata(cfg_rdata),.cfg_error_code(cfg_error_code),
        .ptb_rxd(1'b1),.ptb_txd(ptb_txd),.rs485_rxd(1'b1),.rs485_txd(rs485_txd),.rs485_de(rs485_de),
        .epsilon_rxd(1'b1),.epsilon_txd(epsilon_txd),.epsilon_correction_txd(epsilon_correction_txd),
        .hc2a_rxd(1'b1),.hc2a_txd(hc2a_txd),.tfa_hf_rxd(1'b1),.tfa_lf_rxd(1'b1),.tfa_txd(tfa_txd),.scl_i(1'b1),.sda_i(1'b1),.bmp_int(1'b0),
        .scl_drive_low(scl_drive_low),.sda_drive_low(sda_drive_low),.gnss_time_tag(gnss_time_tag),.gnss_time_tag_valid(gnss_time_tag_valid),
        .m_valid(m_valid),.m_ready(7'h7f),.m_data(m_data),.m_keep(m_keep),.m_sof(m_sof),.m_last(m_last),
        .m_source_id(m_source_id),.m_msg_id(m_msg_id),.m_timestamp(m_timestamp),.m_cycle_id(m_cycle),.m_flags(m_flags),
        .device_online(online),.device_error(device_error),.device_drop_count(device_drop_count),.device_fifo_level(device_fifo_level));
    task read32;
        input [31:0] addr;
        input [31:0] expected;
        begin
            @(negedge clk);cfg_valid=1;cfg_write=0;cfg_addr=addr;#1;
            if(!cfg_ready||cfg_error||cfg_rdata!==expected)$fatal(1,"BANK_CFG addr=%h ready=%b error=%b data=%h expected=%h",addr,cfg_ready,cfg_error,cfg_rdata,expected);
            checks=checks+1;@(negedge clk);cfg_valid=0;
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst_n=1;repeat(4)@(negedge clk);
        read32(32'h6100,32'h00410106);
        read32(32'h6110,19200);
        read32(32'h6114,99);
        read32(32'h6118,0);
        read32(32'h6600,32'h00460200);
        read32('h6500,'h00450100);
        if(tfa_txd!==1 || rs485_de!==0 || hc2a_txd!==1)$fatal(1,"PORT_STARTUP");
        $display("HC2A_SENSOR_BANK_SELECT_PASS checks=%0d HC2A_lane=1 AI8_lane=6 HC2A_CON11_AI8_CON19_TFA_CON21",checks);
        $finish;
    end
    initial begin #1000000;$fatal(1,"HC2A_BANK_SELECT_TIMEOUT");end
endmodule
