`timescale 1ns/1ps
`include "error_codes.vh"
`include "sensor_cfg_codes.vh"
module tb_hc2a_uart_diagnostic;
    localparam integer SYS_CLK_HZ=320000;
    localparam integer BIT_NS=52083;
    reg clk=0;always #1562.5 clk=~clk;
    reg rst_n=0;
    reg [63:0] timestamp_now=0;
    always @(posedge clk)timestamp_now<=timestamp_now+1'b1;
    reg cfg_valid=0,cfg_write=0;
    reg [31:0] cfg_addr=0,cfg_wdata=0;
    reg [3:0] cfg_wstrb=4'hf;
    wire cfg_ready,cfg_error;
    wire [31:0] cfg_rdata;
    wire [3:0] cfg_error_code;
    wire txd;
    reg rxd=1;
    wire m_valid;
    wire [31:0] m_data,m_flags,m_cycle_id;
    wire [3:0] m_keep;
    wire m_sof,m_last;
    wire [15:0] m_source_id,m_msg_id;
    wire [63:0] m_timestamp;
    wire [31:0] errors,drops,level;
    wire online;
    reg [7:0] tx_bytes[0:8];
    reg [7:0] response[0:127];
    reg [223:0] packet=0;
    integer packet_count=0,packet_beat=0;
    integer request_count=0,response_length=0;
    integer i,k,debug_byte;
    reg [7:0] expected_byte;
    reg [31:0] checksum_sum;
    reg [63:0] packet_timestamp=0;
    function real f32_value;
        input [31:0] bits;
        integer exponent;
        real magnitude;
        begin
            exponent=bits[30:23];exponent=exponent-127;
            magnitude=(1.0+bits[22:0]/8388608.0)*(2.0**exponent);
            f32_value=bits[31]?-magnitude:magnitude;
        end
    endfunction

    hc2a_roascii_uart #(.SYS_CLK_HZ(SYS_CLK_HZ),.FIFO_DEPTH(16),.DEFAULT_ADDRESS(99)) dut(
        .sys_clk(clk),.rst_sys_n(rst_n),.uart_rxd(rxd),.uart_txd(txd),
        .timestamp_now(timestamp_now),.time_sync_valid(1'b1),.time_sync_seq(32'd7),
        .cfg_valid(cfg_valid),.cfg_write(cfg_write),.cfg_addr(cfg_addr),.cfg_wdata(cfg_wdata),.cfg_wstrb(cfg_wstrb),
        .cfg_ready(cfg_ready),.cfg_rdata(cfg_rdata),.cfg_error(cfg_error),.cfg_error_code(cfg_error_code),
        .m_valid(m_valid),.m_ready(1'b1),.m_data(m_data),.m_keep(m_keep),.m_sof(m_sof),.m_last(m_last),
        .m_source_id(m_source_id),.m_msg_id(m_msg_id),.m_timestamp(m_timestamp),.m_cycle_id(m_cycle_id),.m_flags(m_flags),
        .online(online),.errors(errors),.drop_count(drops),.fifo_level(level));

    task cfg_write32;
        input [31:0] addr,value;
        begin
            @(negedge clk);cfg_valid=1;cfg_write=1;cfg_addr=addr;cfg_wdata=value;
            #1;if(!cfg_ready||cfg_error)$fatal(1,"CFG_WRITE addr=%h error=%b code=%h",addr,cfg_error,cfg_error_code);
            @(negedge clk);cfg_valid=0;cfg_write=0;
        end
    endtask

    task cfg_read32;
        input [31:0] addr;
        output [31:0] value;
        begin
            @(negedge clk);cfg_valid=1;cfg_write=0;cfg_addr=addr;
            #1;if(!cfg_ready||cfg_error)$fatal(1,"CFG_READ addr=%h error=%b",addr,cfg_error);
            value=cfg_rdata;
            @(negedge clk);cfg_valid=0;
        end
    endtask

    task expect_bad_address_write;
        begin
            @(negedge clk);cfg_valid=1;cfg_write=1;cfg_addr=32'h6114;cfg_wdata=65;
            #1;if(!cfg_ready||!cfg_error||cfg_error_code!=`SENSOR_CFG_RANGE)
                $fatal(1,"ADDRESS_65_MUST_BE_REJECTED");
            @(negedge clk);cfg_valid=0;cfg_write=0;
        end
    endtask

    task expect_cfg_error;
        input is_write;
        input [31:0] addr,wdata;
        input [3:0] reason;
        begin
            @(negedge clk);cfg_valid=1;cfg_write=is_write;cfg_addr=addr;cfg_wdata=wdata;
            #1;if(!cfg_ready || !cfg_error || cfg_error_code!=reason)
                $fatal(1,"HC2A_CFG_REJECTION addr=%h write=%b reason=%h expected=%h",addr,is_write,cfg_error_code,reason);
            @(negedge clk);cfg_valid=0;cfg_write=0;
        end
    endtask

    task receive_tx_byte;
        output [7:0] value;
        integer bit_index;
        begin
            @(negedge txd);
            #(BIT_NS*3/2);
            for(bit_index=0;bit_index<8;bit_index=bit_index+1)begin
                value[bit_index]=txd;
                #(BIT_NS);
            end
            if(txd!==1'b1)$fatal(1,"UART_TX_STOP_BIT");
        end
    endtask

    task send_rx_byte;
        input [7:0] value;
        integer bit_index;
        begin
            rxd=0;#(BIT_NS);
            for(bit_index=0;bit_index<8;bit_index=bit_index+1)begin
                rxd=value[bit_index];#(BIT_NS);
            end
            rxd=1;#(BIT_NS);
        end
    endtask

    task append_ascii;
        input [1023:0] value;
        integer byte_index;
        reg seen;
        reg [7:0] current_byte;
        begin
            seen=0;
            for(byte_index=127;byte_index>=0;byte_index=byte_index-1)begin
                current_byte=value[byte_index*8+:8];
                if(current_byte!=0)begin
                    response[response_length]=current_byte;
                    response_length=response_length+1;
                    seen=1;
                end else if(seen)begin
                    $fatal(1,"NUL_IN_RESPONSE_FIXTURE");
                end
            end
        end
    endtask

    task send_roascii_response;
        input corrupt_checksum;
        integer byte_index;
        begin
            response_length=0;checksum_sum=0;
            append_ascii("{F04rdd 001; 4.45;%RH;000;=; 20.07;C;000;=;nc;---.--;C;000; ;001;B2.8;0000000002;HyClp2;006;");
            if(request_count==3)response[1]=8'h58;
            for(byte_index=0;byte_index<response_length;byte_index=byte_index+1)
                checksum_sum=checksum_sum+response[byte_index];
            response[response_length]=(checksum_sum&32'h3f)+32'h20;
            if(corrupt_checksum)response[response_length]=response[response_length]^8'h01;
            response_length=response_length+1;
            response[response_length]=8'h0d;response_length=response_length+1;
            for(byte_index=0;byte_index<response_length;byte_index=byte_index+1)
                send_rx_byte(response[byte_index]);
        end
    endtask

    always @(posedge clk)if(rst_n&&m_valid)begin
        if(m_source_id!==16'h0041||m_msg_id!==16'h1100||m_cycle_id!==32'hffffffff||m_keep!==4'hf)
            $fatal(1,"HC2A_STREAM_METADATA");
        if(m_sof)begin packet=0;packet_beat=0;packet_timestamp=m_timestamp;end
        if(m_timestamp!==packet_timestamp||m_flags[0]!==1'b1||m_flags[2]!==1'b1)
            $fatal(1,"HC2A_STREAM_TIMESTAMP_FLAGS");
        packet[packet_beat*32+:32]=m_data;
        packet_beat=packet_beat+1;
        if(m_last)begin
            if(packet_beat!=7)$fatal(1,"HC2A_RECORD_BEAT_COUNT=%0d",packet_beat);
            if(packet[31:0]!==32'h00030001||packet[63:32]!==32'h04090100||
               packet[127:96]!==32'h04090101||packet[191:160]!==32'h04030002||
               packet[223:192]!==32'd6)$fatal(1,"HC2A_RECORD_LAYOUT %h",packet);
            packet_count=packet_count+1;
        end
    end

    initial begin
        wait(rst_n);
        forever begin
            for(i=0;i<9;i=i+1)begin
                receive_tx_byte(tx_bytes[i]);
            end
            request_count=request_count+1;
            if(tx_bytes[0]!==8'h7b||tx_bytes[1]!==8'h46||tx_bytes[4]!==8'h52||
               tx_bytes[5]!==8'h44||tx_bytes[6]!==8'h44||tx_bytes[7]!==8'h7d||tx_bytes[8]!==8'h0d)
                $fatal(1,"HC2A_RDD_REQUEST_BYTES");
            if(request_count==1)begin
                if(tx_bytes[2]!==8'h39||tx_bytes[3]!==8'h39)$fatal(1,"UNKNOWN_ADDRESS_PROBE");
            end else if(tx_bytes[2]!==8'h30||tx_bytes[3]!==8'h34)
                $fatal(1,"LEARNED_ADDRESS_NOT_USED");
            #(BIT_NS/2);repeat(3)@(posedge clk);
            if(request_count==1)send_roascii_response(0);
            else if(request_count==2)send_roascii_response(1);
            else if(request_count==3)send_roascii_response(0);
        end
    end

    reg [31:0] value;
    initial begin
        repeat(20)@(negedge clk);rst_n=1;
        cfg_read32(32'h6100,value);if(value!==32'h00410106)$fatal(1,"HC2A_ID");
        cfg_read32(32'h6114,value);if(value!==99)$fatal(1,"HC2A_UNKNOWN_ADDRESS_DEFAULT");
        cfg_read32(32'h6118,value);if(value!==0)$fatal(1,"HC2A_DEFAULT_8N1");
        expect_bad_address_write();
        expect_cfg_error(0,'h6101,0,5);
        expect_cfg_error(1,'h61fc,0,6);
        expect_cfg_error(0,'h614d,0,5);
        cfg_read32('h614c,value);if(value!==32'h48434432)$fatal(1,"DEBUG_SIGNATURE");
        cfg_read32('h6158,value);if(value!==0)$fatal(1,"DEBUG_RESET");
        expect_cfg_error(1,'h6124,0,6);
        expect_cfg_error(1,'h6134,32'h447d5000,6);
        expect_cfg_error(1,'h6104,5,7);
        expect_cfg_error(1,'h6118,1,7);
        expect_cfg_error(1,'h611c,99,7);
        expect_cfg_error(1,'h6120,0,7);
        cfg_write32('h6114,64);cfg_write32('h6114,99);
        cfg_write32('h6110,9600);cfg_write32('h6110,19200);
        cfg_write32(32'h611c,100);
        cfg_write32(32'h6104,1);
        expect_cfg_error(1,'h6114,4,8);
        expect_cfg_error(1,'h6114,65,7);
        expect_cfg_error(1,'h6110,19200,8);
        expect_cfg_error(1,'h6110,0,7);
        expect_cfg_error(1,'h6118,0,8);
        expect_cfg_error(1,'h6118,1,7);
        wait(packet_count==1);
        if(!online||request_count!=1)$fatal(1,"HC2A_ONLINE_AFTER_VALID_RESPONSE");
        cfg_read32(32'h6114,value);if(value!==4)$fatal(1,"HC2A_ADDRESS_LEARNING=%0d",value);
        cfg_read32('h6158,value);
        if(value[31]!==1'b1 || value[9:8]!==0 || value[7:0]!==response_length-1)
            $fatal(1,"DEBUG_SNAPSHOT_LENGTH_FLAGS=%h",value);
        cfg_read32('h6150,value);if(value!==response_length)$fatal(1,"DEBUG_BYTE_COUNT");
        cfg_read32('h6154,value);if(value!==0)$fatal(1,"DEBUG_UART_ERRORS");
        for(k=0;k<response_length-1;k=k+4)begin
            cfg_read32('h6160+k,value);
            for(debug_byte=0;debug_byte<4;debug_byte=debug_byte+1)begin
                if(k+debug_byte<response_length-1 && value[debug_byte*8+:8]!==response[k+debug_byte])
                    $fatal(1,"DEBUG_SNAPSHOT_BYTES offset=%0d",k+debug_byte);
            end
        end
        // Independent numeric tolerance: Q16 conversion error must be far below 0.01.
        cfg_read32(32'h6124,value);if(f32_value(value)<4.44998 || f32_value(value)>4.45002)$fatal(1,"HC2A_RH_FLOAT=%h",value);
        cfg_read32(32'h6128,value);if(f32_value(value)<20.06998 || f32_value(value)>20.07002)$fatal(1,"HC2A_TEMP_FLOAT=%h",value);
        wait(dut.checksum_errors!=0);
        cfg_read32('h615c,value);if(value!==2)$fatal(1,"DEBUG_CHECKSUM_REASON=%h",value);
        wait(dut.format_errors!=0);
        cfg_read32('h615c,value);if(value!==32'h40)$fatal(1,"DEBUG_BAD_IDENTIFIER=%h",value);
        cfg_read32('h6160,value);if(value!==32'h3430587b)$fatal(1,"DEBUG_REJECTED_RAW=%h",value);
        wait(dut.timeout_count!=0);
        cfg_read32('h615c,value);if(value!==1)$fatal(1,"DEBUG_TIMEOUT_REASON=%h",value);
        repeat(2)@(negedge clk);
        if(request_count<3)$fatal(1,"HC2A_RETRY_AFTER_BAD_CHECKSUM");
        if(online)$fatal(1,"HC2A_MUST_GO_OFFLINE_AFTER_RETRY_TIMEOUT");
        cfg_write32(32'h6104,0);
        cfg_write32(32'h6104,2);
        cfg_read32(32'h6114,value);if(value!=99)$fatal(1,"HC2A_SOFT_RESET_ADDRESS");
        cfg_read32(32'h6144,value);if(value!=0)$fatal(1,"HC2A_SOFT_RESET_COUNTER");
        cfg_read32('h6158,value);if(value!==0)$fatal(1,"DEBUG_SOFT_RESET");
        cfg_read32('h6150,value);if(value!==0)$fatal(1,"DEBUG_COUNTER_SOFT_RESET");
        $display("HC2A_UART_DIAGNOSTIC_PASS request=F99RDD then F04RDD, valid/checksum-fault/timeout retry, RH/T TLV");
        $finish;
    end
    initial begin #(64'd2400000000);$fatal(1,"HC2A_TEST_TIMEOUT requests=%0d packets=%0d",request_count,packet_count);end
endmodule
