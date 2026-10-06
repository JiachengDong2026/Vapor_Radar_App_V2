`timescale 1ns/1ps
// Real WMS/DAC arithmetic and AD5791 wire model; no forced divider results.
module tb_cfg_commit_cancel;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,cv=0,cw=0;
    reg [31:0] ca=0,cd=0;
    reg [3:0] cs=0;
    wire cr,ce,changed,sclk,sync_n,sdin,reset_n,clr_n,ldac_n;
    wire [31:0] rd,frames;
    wire [3:0] ec;
    wire [19:0] clear_code;
    integer changes=0,accepted=0,stage,n,cancelled=0;
    integer before_changes,before_frames;
    reg [31:0] data,expected_rate=0,expected_spi=16666666,expected_clear='h80000;
    always @(posedge clk)begin
        if(changed)changes=changes+1;
        if(cv && cr && cw && ca[7:0]==4 && cd[2] && !ce)accepted=accepted+1;
    end
    wms_dac_channel dut(
        .sys_clk(clk),.rst_sys_n(rst),.enable(1'b1),.timestamp_now(64'd0),.time_sync_valid(1'b1),
        .cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(cs),
        .cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce),.cfg_error_code(ec),
        .scan_start(),.cycle_id(),.sine_phase(),.wms_running(),.phase_valid(),.config_changed(changed),
        .dac_sclk(sclk),.dac_sync_n(sync_n),.dac_sdin(sdin),.dac_sdo(1'b0),
        .dac_rst_n(reset_n),.dac_clr_n(clr_n),.dac_ldac_n(ldac_n));
    ad5791_model model(.sclk(sclk),.sync_n(sync_n),.sdin(sdin),.rst_n(reset_n),
        .clr_n(clr_n),.ldac_n(ldac_n),.code(),.control(),.clear_code(clear_code),.last_frame(),.frame_count(frames));
    task transfer;
        input wr;input [31:0] addr,value;
        integer ticks;
        begin
            @(negedge clk);cv=1;cw=wr;ca=addr;cd=value;cs=wr?15:0;ticks=0;
            begin:ack
                forever begin
                    @(posedge clk);
                    if(cr)begin
                        if(ce || ec!=0)$fatal(1,"CFG_ERROR addr=%h code=%d",addr,ec);
                        data=rd;disable ack;
                    end
                    ticks=ticks+1;if(ticks>1000)$fatal(1,"CFG_TIMEOUT");
                end
            end
            @(negedge clk);cv=0;cw=0;cs=0;
        end
    endtask
    task wait_dac;
        begin
            transfer(0,'h3008,0);
            while(!data[1] || data[3])transfer(0,'h3008,0);
        end
    endtask
    task cancel_commit;
        input is_dac;input integer target_stage;
        integer ticks,old_accepted;
        begin
            old_accepted=accepted;
            @(negedge clk);cv=1;cw=1;ca=is_dac?'h3004:'h2004;cd=4;cs=15;ticks=0;
            // Observe terminal ready between edges, then withdraw before it is accepted.
            while((is_dac ? dut.dac.calc : dut.wms.calc)!=target_stage)begin
                @(negedge clk);ticks=ticks+1;
                if(ticks>500)$fatal(1,"STAGE_TIMEOUT dac=%d stage=%d",is_dac,target_stage);
            end
            cv=0;cw=0;cs=0;
            @(posedge clk);#1;
            if(cr || ce || ec!=0 || accepted!=old_accepted)$fatal(1,"CANCEL_LATE_ACK");
            if(is_dac)begin
                if(dut.dac.calc!=0 || dut.dac.div_busy)$fatal(1,"DAC_CANCEL_NOT_ABORTED stage=%d",target_stage);
            end else if(dut.wms.calc!=0 || dut.wms.div_busy || dut.wms.pending)
                $fatal(1,"WMS_CANCEL_NOT_ABORTED stage=%d",target_stage);
            cancelled=cancelled+1;
        end
    endtask
    initial begin
        repeat(5)@(negedge clk);rst=1;wait_dac;
        // Cancel during every arithmetic state and after ready rises, before ACK.
        for(n=1;n<=6;n=n+1)begin
            stage=n==6?7:n;
            transfer(1,'h3024,5000000);transfer(1,'h3014,'h10000+n);
            before_frames=frames;
            cancel_commit(1,stage);
            // Let an old divider finish, then read status: neither may reinitialize DAC.
            if(n[0]==0)repeat(420)@(negedge clk);
            transfer(0,'h3008,0);
            transfer(0,'h303c,0);
            if(data!=expected_spi || frames!=before_frames || clear_code!=expected_clear)
                $fatal(1,"DAC_CANCEL_CHANGED_ACTIVE");
            transfer(1,'h3024,10000000);transfer(1,'h3014,'h20000+n);
            transfer(1,'h3004,4);wait_dac;
            expected_spi=10000000;expected_clear='h20000+n;
            transfer(0,'h303c,0);
            if(data!=expected_spi || clear_code!=expected_clear || frames!=before_frames+4)
                $fatal(1,"DAC_RECOMMIT_STALE_SNAPSHOT");
        end
        for(n=1;n<=8;n=n+1)begin
            stage=n==8?9:n;
            transfer(1,'h2028,50000+n);transfer(1,'h2018,'h10000+n);
            before_changes=changes;
            cancel_commit(0,stage);
            if(n[0]==0)repeat(420)@(negedge clk);
            transfer(0,'h2008,0);
            repeat(3)@(negedge clk);transfer(0,'h202c,0);
            if(data!=expected_rate || changes!=before_changes)$fatal(1,"WMS_READ_APPLIED_CANCELLED_COMMIT");
            transfer(1,'h2028,100000);transfer(1,'h2018,'h20000+n);
            transfer(1,'h2004,4);
            repeat(3)@(negedge clk);expected_rate=100000;
            transfer(0,'h202c,0);
            if(data!=expected_rate || changes!=before_changes+1 || dut.wms.a_offset!='h20000+n)
                $fatal(1,"WMS_RECOMMIT_STALE_SNAPSHOT");
        end
        if(cancelled!=14 || accepted!=14)$fatal(1,"COMMIT_COUNTS");
        $display("TEST_PASS tb_cfg_commit_cancel cancelled=%0d recommitted=%0d DAC wire-model reinit and WMS active snapshots",cancelled,accepted);
        $finish;
    end
    initial begin #1000000;$fatal(1,"TIMEOUT");end
endmodule
