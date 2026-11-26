`timescale 1ns/1ps
module tb_ai8_parameters;
    reg clk=0,rst=0,valid=0,write=0;
    always #5 clk=~clk;
    reg [31:0] addr=0,data=0;
    wire [31:0] rd;
    wire err;
    reg done=0;
    reg [3:0] transport=0;
    reg [255:0] response=0;
    integer ch,item,round,k;
    reg found;
    reg [15:0] expected,value;
    ai8_modbus_rs485 #(.SYS_CLK_HZ(2000000)) dut(
        .sys_clk(clk),.rst_sys_n(rst),.uart_rxd(1'b1),.uart_txd(),.rs485_de(),
        .timestamp_now(64'd1234),.time_sync_valid(1'b1),.time_sync_seq(32'd0),
        .cfg_valid(valid),.cfg_write(write),.cfg_addr(addr),.cfg_wdata(data),.cfg_wstrb(4'hf),
        .cfg_ready(),.cfg_rdata(rd),.cfg_error(err),.cfg_error_code(),
        .m_valid(),.m_ready(1'b1),.m_data(),.m_keep(),.m_sof(),.m_last(),.m_source_id(),.m_msg_id(),
        .m_timestamp(),.m_cycle_id(),.m_flags(),.online(),.errors(),.drop_count(),.fifo_level(),
        .bus_request(),.bus_busy(),.bus_grant(1'b1));
    task wr;
        input [31:0] a,d;
        begin @(negedge clk);valid=1;write=1;addr=a;data=d;
            #1;if(err)$fatal(1,"write rejected %h",a);@(negedge clk);valid=0;write=0;
        end
    endtask
    task rejected;
        input [31:0] a,d;
        begin @(negedge clk);valid=1;write=1;addr=a;data=d;
            #1;if(!err)$fatal(1,"invalid write accepted %h",a);
            @(negedge clk);valid=0;write=0;end
    endtask
    task finish_poll;
        begin
            while(dut.core.state!=8 && dut.core.state!=6)begin
                @(negedge clk);done=dut.core.state==2;response=0;
            end
            done=0;
        end
    endtask
    task reply;
        input [15:0] v; input [3:0] e;
        begin @(negedge clk);response={240'd0,v[7:0],v[15:8]};transport=e;done=1;
            @(negedge clk);done=0;repeat(3)@(negedge clk);transport=0;end
    endtask
    initial begin
        force dut.core.req_ready=1'b1;
        force dut.core.done=done;
        force dut.core.master_error=transport;
        force dut.core.master_exception=8'd0;
        force dut.core.read_data=response;
        repeat(4)@(negedge clk);rst=1;
        wr('h6668,1);wr('h662c,1);wr('h6604,1);
        wr('h6684,4);wr('h6688,250);wr('h6680,2);
        rejected('h6684,5);rejected('h6688,999);rejected('h6680,1);rejected('h6604,5);
        finish_poll;
        if(dut.core.selected_sp_address!=4)$fatal(1,"CH5 address");
        if(dut.core.master.retry_limit!=0)$fatal(1,"parameter retries enabled");
        reply(0,0);wait(dut.core.state==8);
        if(dut.param_done || dut.param_count!=0)$fatal(1,"ACK is not confirmation");
        if(dut.core.selected_sp_address!=4)$fatal(1,"readback address");
        reply(250,0);
        if(!dut.param_done || dut.param_count!=1 || dut.param_result || dut.param_readback!=250)$fatal(1,"confirmed write");
        wr('h6684,'h604);wr('h6680,1);finish_poll;reply(321,0);
        if(dut.param_count!=2 || dut.param_result || dut.param_readback!=321)$fatal(1,"read");
        wr('h6684,4);wr('h6680,2);finish_poll;reply(0,0);wait(dut.core.state==8);reply(999,0);
        if(dut.param_count!=3 || dut.param_result!=3 || dut.param_readback!=999)$fatal(1,"mismatch");
        wr('h6680,1);finish_poll;reply(0,1);
        if(dut.param_count!=4 || dut.param_result!=2 || dut.param_error!=1)$fatal(1,"timeout");
        wr('h6680,1);wr('h6604,0);repeat(4)@(negedge clk);
        if(dut.param_count!=5 || dut.param_pending || dut.param_result!=5)$fatal(1,"cancel");
        wr('h6604,1);
        wr('h6684,'h604);rejected('h6680,2);
        wr('h6684,'h700);rejected('h6680,1);
        wr('h6684,'h845);wr('h6688,99);rejected('h6680,2);
        wr('h6684,'h840);
        @(negedge clk);valid=1;write=1;addr='h6680;data=2;
        #1;if(!err)$fatal(1,"communication write accepted");
        @(negedge clk);valid=0;write=0;
        if(dut.confirmed_count!=0)$fatal(1,"legacy count polluted");
        $display("AI8_PARAMETERS_PASS");$finish;
    end
    initial begin #20000000;$fatal(1,"watchdog");end
endmodule
