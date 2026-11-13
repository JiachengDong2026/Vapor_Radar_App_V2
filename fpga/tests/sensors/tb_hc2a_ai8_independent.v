`timescale 1ns/1ps
module tb_hc2a_ai8_independent #(parameter integer INCLUDE_TFA=0);
    localparam integer SYS_CLK_HZ=INCLUDE_TFA ? 8000000 : 1000000;
    reg clk=0;always #(500000000.0/SYS_CLK_HZ) clk=~clk;
    reg rst_n=0,cv=0,cw=0;
    reg [31:0] ca=0,cd=0;
    wire cr,ce;
    wire [31:0] rd;
    wire txd,rxd,de,hc_txd,hc_rxd;
    integer concurrent_cycles=0,tfa_packets=0;
    reg tfa_rxd=1;
    wire tfa_txd;
    reg [63:0] ticks=0;
    always @(posedge clk)ticks<=ticks+1'b1;
    reg [3:0] fault=0;
    wire [31:0] hc_requests,ai_requests,ai_writes;
    wire [15:0] ai_sp;
    wire [6:0] mv,ms,ml,online;
    reg [6:0] ready=7'h7f;
    wire [223:0] data,flags,errors,drops,levels;
    wire [111:0] source_id,msg_id;
    wire [447:0] stamp;
    wire [27:0] keep;
    reg [223:0] hc_record=0;
    integer hc_packets=0,ai_packets=0,beat=0,stage=0;
    reg stalled=0;
    reg [133:0] held=0;
    wire [133:0] hc_bundle={data[32+:32],keep[4+:4],ms[1],ml[1],stamp[64+:64],flags[32+:32]};
    integer prior_hc,prior_ai,prior_requests;
    reg [31:0] value;
    reg [15:0] rng=16'h5a5a;
    reg block_output=0;
    member3_sensor_bank #(.SYS_CLK_HZ(SYS_CLK_HZ),.FIFO_DEPTH(64),.PTB_BOOT_MS(1)) dut(
        .sys_clk(clk),.rst_sys_n(rst_n),.timestamp_now(ticks),.time_sync_valid(1'b1),.time_sync_seq(32'd3),.sync_event_pulse(1'b0),
        .cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(4'hf),.cfg_ready(cr),.cfg_error(ce),.cfg_rdata(rd),
        .ptb_rxd(1'b1),.rs485_rxd(rxd),.rs485_txd(txd),.rs485_de(de),.epsilon_rxd(1'b1),
        .hc2a_rxd(hc_rxd),.hc2a_txd(hc_txd),.tfa_hf_rxd(tfa_rxd),.tfa_txd(tfa_txd),.tfa_lf_rxd(1'b1),.scl_i(1'b1),.sda_i(1'b1),.bmp_int(1'b0),
        .m_valid(mv),.m_ready(ready),.m_data(data),.m_keep(keep),.m_sof(ms),.m_last(ml),
        .m_source_id(source_id),.m_msg_id(msg_id),.m_timestamp(stamp),.m_flags(flags),
        .device_online(online),.device_error(errors),.device_drop_count(drops),.device_fifo_level(levels));
    hc2a_ai8_device_bfm #(.TTL_HC2A(1)) hc_model(.rst_n(rst_n),.master_txd(hc_txd),.master_de(1'b0),
        .hc2a_fault(fault),.slave_txd(hc_rxd),.hc2a_count(hc_requests));
    hc2a_ai8_device_bfm ai_model(.rst_n(rst_n),.master_txd(txd),.master_de(de),.hc2a_fault(4'd0),
        .slave_txd(rxd),.ai8_count(ai_requests),.write_count(ai_writes),.current_sp(ai_sp));
    task wr;
        input [31:0] a,d;
        begin
            @(negedge clk);cv=1;cw=1;ca=a;cd=d;#1;
            if(!cr||ce)$fatal(1,"HC_AI_CFG_WRITE %h %h",a,d);
            @(negedge clk);cv=0;cw=0;
        end
    endtask
    task read32;
        input [31:0] a;
        output [31:0] d;
        begin
            @(negedge clk);cv=1;cw=0;ca=a;#1;
            if(!cr||ce)$fatal(1,"HC_AI_CFG_READ %h",a);d=rd;
            @(negedge clk);cv=0;
        end
    endtask
    task recover;
        begin
            fault=0;prior_hc=hc_packets;prior_ai=ai_packets;
            wait(hc_packets>prior_hc && ai_packets>prior_ai);
            if(!online[1]||!online[6])$fatal(1,"HC_AI_RECOVERY");
        end
    endtask
    task reject_format;
        input [3:0] mode;
        reg [31:0] before_errors,before_frames;
        begin
            read32('h6148,before_errors);read32('h6144,before_frames);
            fault=mode;
            // A transaction already in flight may finish before the fault takes effect.
            wait(hc_requests>prior_requests+1);read32('h6144,before_frames);
            wait(dut.gen_hc2a.u_1.format_errors>before_errors);
            read32('h6144,value);
            if(value!=before_frames)$fatal(1,"MALFORMED_RESPONSE_PUBLISHED fault=%d",mode);
            prior_requests=hc_requests;
            recover();
        end
    endtask
    always @(negedge clk)if(rst_n)begin
        rng={rng[14:0],rng[15]^rng[13]^rng[12]^rng[10]};
        ready=block_output?7'd0:rng[6:0];
    end
    always @(posedge clk)if(rst_n)begin
        if(dut.bus_request[0] || dut.bus_busy[0] || dut.bus_de[0] || !dut.bus_txd[0])
            $fatal(1,"HC2A_MUST_NOT_CLAIM_CON19");
        if(dut.gen_hc2a.u_1.state==6 && de)concurrent_cycles=concurrent_cycles+1;
        if(mv[5] && ready[5] && ml[5])begin
            if(source_id[80+:16]!=16'h45 || data[160+:32]!=123450)$fatal(1,"TFA_DATA_OR_PORT_CROSSTALK");
            tfa_packets=tfa_packets+1;
        end
        if(stalled && (!mv[1] || hc_bundle!==held))$fatal(1,"HC_AI_STALL_STABILITY");
        stalled=mv[1]&&!ready[1];held=hc_bundle;
        if(mv[1]&&ready[1])begin
            if(source_id[16+:16]!=16'h41||msg_id[16+:16]!=16'h1100||keep[4+:4]!=15||
                flags[32+:3]!=5||stamp[64+:64]==0||stamp[64+:64]>=ticks)$fatal(1,"HC_AI_HC_METADATA");
            if(ms[1])begin beat=0;hc_record=0;end
            hc_record[beat*32+:32]=data[32+:32];beat=beat+1;
            if(ml[1])begin
                if(beat!=7||hc_record[31:0]!=32'h00030001)$fatal(1,"HC_AI_HC_LAYOUT");
                hc_packets=hc_packets+1;
            end
        end
        if(mv[6]&&ready[6]&&ml[6])ai_packets=ai_packets+1;
    end
    initial begin
        repeat(10)@(negedge clk);rst_n=1;
        #5000000;if(de||hc_txd!==1||hc_requests||ai_requests)$fatal(1,"DISABLED_STARTUP_TRAFFIC");
        if(INCLUDE_TFA)wr('h6504,1);
        wr('h611c,100);wr('h662c,100);wr('h6104,1);wr('h6604,1);
        wait(hc_packets>=2 && ai_packets>=2);stage=1;
        if(hc_record[95:64]!==32'h42480000||hc_record[159:128]!==32'h41cc0000||ai_writes)
            $fatal(1,"HC_AI_NORMAL_DATA_OR_UNSOLICITED_WRITE");
        read32('h6114,value);if(value!=4)$fatal(1,"HC_AI_LEARNED_ADDRESS");
        if(INCLUDE_TFA)begin
            wait(tfa_packets>=10);
            // Force a long HC2A response wait so independent AI8 traffic must overlap it.
            fault=1;prior_requests=hc_requests;prior_ai=ai_packets;
            wait(hc_requests>prior_requests);
            wait(concurrent_cycles>0 && ai_packets>prior_ai);
            if(!online[5] || concurrent_cycles==0)$fatal(1,"TRIPLE_PORT_PROGRESS online=%b overlap_cycles=%d packets=%d/%d/%d TFA_state=%d errors=%h",online,concurrent_cycles,hc_packets,ai_packets,tfa_packets,dut.u_5.state,errors[160+:32]);
            $display("HC2A_AI8_TFA_PASS HC=%0d AI=%0d TFA=%0d independent_GPIO_CON19_CON21",hc_packets,ai_packets,tfa_packets);
            $finish;
        end
        prior_requests=hc_requests;reject_format(4);stage=2;
        prior_requests=hc_requests;reject_format(3);stage=3;
        prior_requests=hc_requests;reject_format(11);stage=4;
        prior_requests=hc_requests;reject_format(12);stage=5;
        prior_requests=hc_requests;reject_format(5);
        prior_requests=hc_requests;reject_format(6);
        prior_requests=hc_requests;reject_format(7);
        fault=9;prior_requests=hc_requests;
        wait(hc_requests>prior_requests+1);prior_hc=hc_packets;wait(hc_packets>prior_hc);
        // -20.07 C, within the documented Q16 conversion error.
        read32('h6128,value);if(value<32'hc1a08f50 || value>32'hc1a08f68)$fatal(1,"NEGATIVE_TEMPERATURE %h",value);
        fault=10;prior_requests=hc_requests;
        wait(hc_requests>prior_requests+1);prior_hc=hc_packets;wait(hc_packets>prior_hc);
        if(hc_record[95:64]!==32'h42c80000||hc_record[159:128]!==32'hc2200000)$fatal(1,"HC_RH_T_ENDPOINTS %h",hc_record);
        recover();
        fault=1;prior_requests=hc_requests;prior_ai=ai_packets;
        wait(errors[32] && !online[1]);wait(ai_packets>prior_ai);
        if(hc_requests<prior_requests+2)$fatal(1,"HC_AI_TIMEOUT_RETRY");
        recover();stage=6;
        fault=8;prior_requests=hc_requests;
        wait(hc_requests>prior_requests+1);prior_hc=hc_packets;
        wait(hc_packets>prior_hc);fault=0;stage=7;
        // Confirm AI8 setpoint writes and readback still work with HC2A active.
        wr('h6650,333);wr('h6604,5);
        begin:await_set
            forever begin
                read32('h6648,value);if(value==1)disable await_set;
                #1000000;
            end
        end
        if(ai_sp!=333||ai_writes!=1)$fatal(1,"HC_AI_SETPOINT_READBACK");
        block_output=1;wait(drops[32+:32]!=0);repeat(5)@(negedge clk);
        if(!errors[34])$fatal(1,"HC_FIFO_DROP_DIAGNOSTIC");
        block_output=0;recover();stage=8;
        wr('h6104,0);wr('h6604,0);repeat(50)@(negedge clk);
        if(de || dut.bus_grant || dut.bus_request)$fatal(1,"HC_AI_DISABLE_RELEASE");
        if(concurrent_cycles==0)$fatal(1,"NO_CONCURRENT_PORT_ACTIVITY");
        $display("HC2A_AI8_INDEPENDENT_PASS HC_packets=%0d AI_packets=%0d requests=%0d/%0d set=333 faults/units/overflow/delayed-response/backpressure",hc_packets,ai_packets,hc_requests,ai_requests);
        $finish;
    end
    task tfa_byte;
        input [7:0] v;
        integer k;
        begin
            tfa_rxd=0;#2000;
            for(k=0;k<8;k=k+1)begin tfa_rxd=v[k];#2000;end
            tfa_rxd=1;#2000;
        end
    endtask
    initial begin
        wait(INCLUDE_TFA && rst_n);wait(dut.u_5.active_mode==2 && dut.u_5.state==0);
        forever begin
            // TFA HF raw 12345 -> 123450 mm, with inverted byte sum.
            tfa_byte('h5c);tfa_byte('h39);tfa_byte('h30);tfa_byte(0);tfa_byte('h96);
            #20000000;
        end
    end
    initial begin #(64'd20000000000);$fatal(1,"HC_AI_TIMEOUT stage=%d packets=%d/%d requests=%d/%d",stage,hc_packets,ai_packets,hc_requests,ai_requests);end
endmodule
