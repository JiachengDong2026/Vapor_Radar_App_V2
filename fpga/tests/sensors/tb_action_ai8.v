`timescale 1ns/1ps
module tb_action_ai8;
    reg clk=0,rst_n=0;always #250 clk=~clk;
    reg [63:0] ticks=0;always @(posedge clk)ticks<=ticks+1;
    reg action_valid=0;
    reg [127:0] action_args=0;
    wire action_ready,action_busy;
    wire [31:0] action_status;
    wire ac_valid,ac_write,ac_ready,ac_error;
    wire [31:0] ac_addr,ac_data,rd;
    wire [3:0] ac_strb,errcode;
    reg manual=0,manual_write=0;
    reg [31:0] manual_addr=0,manual_data=0;
    wire cfg_valid=manual || ac_valid;
    wire cfg_write=manual ? manual_write:ac_write;
    wire [31:0] cfg_addr=manual ? manual_addr:ac_addr;
    wire [31:0] cfg_data=manual ? manual_data:ac_data;
    wire [3:0] cfg_strb=manual ? 4'hf:ac_strb;
    wire cfg_ready,cfg_error,txd,rxd,de;
    reg [3:0] fault=0;
    wire [31:0] requests,writes,verifies;
    wire [15:0] current_sp;
    reg [31:0] before_confirm,before_verify,expected_raw,value;
    integer completions=0,stage=0;
    assign ac_ready=!manual && cfg_ready;
    assign ac_error=!manual && cfg_error;
    action_controller #(.CFG_TIMEOUT(128),.ACTION_TIMEOUT(500000)) action(
        .sys_clk(clk),.rst_sys_n(rst_n),.action_valid(action_valid),.action_ready(action_ready),
        .action_status(action_status),.action_code(16'd11),.action_source(16'h46),.action_args(action_args),
        .cfg_valid(ac_valid),.cfg_write(ac_write),.cfg_addr(ac_addr),.cfg_wdata(ac_data),.cfg_wstrb(ac_strb),
        .cfg_ready(ac_ready),.cfg_error(ac_error),.cfg_rdata(rd),.cfg_error_code(errcode),
        .channel_datapath_idle(2'b11),.sensor_datapath_idle(1'b1),.stop_flush(),.acquisition_running(),.busy(action_busy));
    ai8_modbus_rs485 #(.SYS_CLK_HZ(2000000),.FIFO_DEPTH(64)) ai(
        .sys_clk(clk),.rst_sys_n(rst_n),.uart_rxd(rxd),.uart_txd(txd),.rs485_de(de),
        .timestamp_now(ticks),.time_sync_valid(1'b1),.time_sync_seq(32'd0),
        .cfg_valid(cfg_valid),.cfg_write(cfg_write),.cfg_addr(cfg_addr),.cfg_wdata(cfg_data),.cfg_wstrb(cfg_strb),
        .cfg_ready(cfg_ready),.cfg_rdata(rd),.cfg_error(cfg_error),.cfg_error_code(errcode),
        .m_valid(),.m_ready(1'b1),.m_data(),.m_keep(),.m_sof(),.m_last(),.m_source_id(),.m_msg_id(),
        .m_timestamp(),.m_cycle_id(),.m_flags(),.online(),.errors(),.drop_count(),.fifo_level(),
        .bus_request(),.bus_busy(),.bus_grant(1'b1));
    ai8_setpoint_slave_bfm slave(.rst_n(rst_n),.master_txd(txd),.master_de(de),.fault_mode(fault),
        .slave_txd(rxd),.request_count(requests),.write_count(writes),.verify_count(verifies),.current_sp(current_sp));
    task cfg_access;
        input wr;input [31:0] address,data;
        begin
            @(negedge clk);manual=1;manual_write=wr;manual_addr=address;manual_data=data;
            @(posedge clk);
            if(!cfg_ready || cfg_error)$fatal(1,"manual cfg failed addr=%h",address);
            value=rd;
            @(negedge clk);manual=0;
        end
    endtask
    task start_set;
        input [31:0] microdegrees;
        begin
            before_confirm=ai.confirmed_count;before_verify=verifies;expected_raw=microdegrees/100000;
            @(negedge clk);action_args={64'd0,microdegrees,32'd17};action_valid=1;
        end
    endtask
    task finish_set;
        input [31:0] expected_status;
        begin
            wait(action_ready);@(negedge clk);
            if(action_status!==expected_status)$fatal(1,"action status=%d expected=%d stage=%d",action_status,expected_status,stage);
            if(expected_status==0)begin
                if(ai.confirmed_count!==before_confirm+1 || current_sp!==expected_raw ||
                    verifies<=before_verify || ai.last_readback!==expected_raw || ai.result!==0)
                    $fatal(1,"action succeeded without confirmed readback");
            end else if(ai.confirmed_count>before_confirm)$fatal(1,"failed action grew confirmed count");
            repeat(10)begin
                @(negedge clk);
                if(!action_ready || action_status!==expected_status)$fatal(1,"completion not stable until valid drops");
            end
            action_valid=0;repeat(3)@(negedge clk);completions=completions+1;
        end
    endtask
    always @(posedge clk)if(rst_n && action_valid && action_ready && action_status==0)begin
        if(ai.pending || ai.confirmed_count!==before_confirm+1 || verifies<=before_verify || ai.last_readback!==expected_raw)
            $fatal(1,"premature action success at write echo");
    end
    initial begin
        repeat(10)@(negedge clk);rst_n=1;
        cfg_access(1,'h662c,1);cfg_access(1,'h6660,20);cfg_access(1,'h6604,1);
        stage=1;start_set(40000000);finish_set(0);
        cfg_access(0,'h6648,0);if(value!==1)$fatal(1,"40C confirmed count");
        cfg_access(0,'h6654,0);if(value!==32'h01900190)$fatal(1,"40C requested/readback raw");
        stage=2;fault=1;start_set(42000000);finish_set(14);
        if(ai.result!==3 || current_sp!==400 || ai.confirmed_count!==1)$fatal(1,"locked echo semantics");
        stage=3;fault=5;start_set(43000000);finish_set(14);
        if(ai.result!==2 || ai.transport_error!==1 || ai.confirmed_count!==1)$fatal(1,"verify timeout semantics");
        // Reset the wrapper during a newly submitted command's quiet interval.
        // A second cfg client may perform this abort; action polling is stalled
        // for only the one accepted external cfg beat.
        stage=4;fault=0;start_set(44000000);
        wait(ai.submitted && ai.core.bus_busy && !de);
        cfg_access(1,'h6604,2);finish_set(14);
        if(ai.pending || ai.enabled || ai.confirmed_count!==0)$fatal(1,"soft reset cancellation");
        // Re-enable with a transport deadline longer than the action deadline.
        // This exercises action status 9 rather than a driver completion error.
        stage=5;cfg_access(1,'h6660,500);cfg_access(1,'h6604,1);
        fault=5;start_set(45000000);finish_set(9);
        if(ai.confirmed_count!==0)$fatal(1,"action deadline reported false confirmation");
        $display("TEST_PASS tb_action_ai8 real action11/sub17: confirmed40C, locked14, verify-timeout14, reset14, deadline9; completions=%0d",completions);
        $finish;
    end
    initial begin repeat(3)#1000000000;$fatal(1,"action AI8 watchdog stage=%d",stage);end
endmodule
