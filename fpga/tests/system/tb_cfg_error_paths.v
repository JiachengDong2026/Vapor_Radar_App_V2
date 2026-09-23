`timescale 1ns/1ps
module tb_cfg_error_paths;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,cv=0;reg [15:0] cmd=3;reg [31:0] length=12,seq=0,payload[0:3],prd=0;
    wire done;wire [31:0] prw;
    wire dv,dw,dr,de;wire [31:0] da,dd,dq;wire [3:0] ds,dc;
    wire bv,bw,br,be;wire [31:0] ba,bd,bq;wire [3:0] bs,bc;
    wire [2:0] sv,sr,se;wire sw;wire [31:0] sa,sd;wire [3:0] ss;
    wire [95:0] sq;wire [11:0] sc;
    wire [2:0] mrdy,merr;wire [95:0] mrdata;wire [11:0] mc;
    wire mv,ms,ml;reg mready=0;wire [31:0] md,msequence;wire [3:0] mk;
    wire [15:0] mid,msource;wire mbusy;
    integer tick=0,responses=0,expected=0;
    cmd_decoder #(.CFG_TIMEOUT(128)) decoder(
        .sys_clk(clk),.rst_sys_n(rst),.timestamp_now(64'd0),.command_valid(cv),.command_done(done),
        .command_status(32'd0),.command_sequence(seq),.command_payload_bytes(length),.command_source(16'h1),.command_id(cmd),
        .payload_read_word(prw),.payload_read_data(prd),.cfg_valid(dv),.cfg_write(dw),.cfg_addr(da),.cfg_wdata(dd),.cfg_wstrb(ds),
        .cfg_ready(mrdy[0]),.cfg_error(merr[0]),.cfg_rdata(mrdata[31:0]),.cfg_error_code(mc[3:0]),
        .action_ready(1'b0),.action_status(32'd0),.m_valid(mv),.m_ready(mready),.m_data(md),.m_keep(mk),.m_sof(ms),.m_last(ml),
        .m_sequence(msequence),.m_msg_id(mid),.m_source_id(msource));
    cfg_bus_arbiter arb(
        .sys_clk(clk),.rst_sys_n(rst),.s_valid({2'd0,dv}),.s_write({2'd0,dw}),.s_addr({64'd0,da}),.s_wdata({64'd0,dd}),.s_wstrb({8'd0,ds}),
        .s_ready(mrdy),.s_error(merr),.s_rdata(mrdata),.s_error_code(mc),.m_valid(bv),.m_write(bw),.m_addr(ba),.m_wdata(bd),.m_wstrb(bs),
        .m_ready(br),.m_error(be),.m_rdata(bq),.m_error_code(bc));
    reg_ctrl_crossbar #(.N(3),.PAGE_MAP(24'h551067),.TIMEOUT_CYCLES(8)) crossbar(
        .sys_clk(clk),.rst_sys_n(rst),.cfg_valid(bv),.cfg_write(bw),.cfg_addr(ba),.cfg_wdata(bd),.cfg_wstrb(bs),
        .cfg_ready(br),.cfg_error(be),.cfg_rdata(bq),.cfg_error_code(bc),.slave_valid(sv),.slave_write(sw),.slave_addr(sa),.slave_wdata(sd),
        .slave_wstrb(ss),.slave_ready(sr),.slave_error(se),.slave_rdata(sq),.slave_error_code(sc));
    stepper_ctrl #(.SYS_CLK_HZ(1000000)) motor(
        .sys_clk(clk),.rst_sys_n(rst),.system_enable(1'b1),.cfg_valid(sv[0]),.cfg_write(sw),.cfg_addr(sa),.cfg_wdata(sd),.cfg_wstrb(ss),
        .cfg_ready(sr[0]),.cfg_error(se[0]),.cfg_rdata(sq[31:0]),.cfg_error_code(sc[3:0]),.busy(mbusy));
    time_sync_core timer(
        .sys_clk(clk),.rst_sys_n(rst),.sync_in_async(1'b0),.gnss_time_tag(64'd0),.gnss_time_tag_valid(1'b0),.clock_valid(1'b1),
        .cfg_valid(sv[1]),.cfg_write(sw),.cfg_addr(sa),.cfg_wdata(sd),.cfg_wstrb(ss),.cfg_ready(sr[1]),.cfg_error(se[1]),
        .cfg_rdata(sq[63:32]),.cfg_error_code(sc[7:4]));
    // Mapped but nonresponding slot exercises the crossbar's real timeout.
    assign sr[2]=0;assign se[2]=0;assign sq[95:64]=0;assign sc[11:8]=0;
    always @(negedge clk)begin tick=tick+1;mready=tick%7<4;end
    always @(posedge clk)begin
        prd<=payload[prw[1:0]];
        if(mv&&mready)begin
            if(ms && (md!==expected || msequence!==seq || mid!==cmd || msource!==1))
                $fatal(1,"response code %d expected %d seq %d/%d",md,expected,msequence,seq);
            if(ml)responses=responses+1;
        end
    end
    task command;input [15:0] c;input [31:0] addr,data,code;
        integer limit;
        begin
            @(negedge clk);seq=seq+1;cmd=c;length=c==2?8:12;expected=code;
            payload[0]=addr;payload[1]=c==4?32'hffffffff:1;payload[2]=data;payload[3]=0;cv=1;
            limit=0;while(!done && limit<1000)begin @(negedge clk);limit=limit+1;end
            if(!done)$fatal(1,"command timeout");cv=0;repeat(3)@(negedge clk);
        end
    endtask
    initial begin
        payload[0]=0;payload[1]=0;payload[2]=0;payload[3]=0;
        repeat(4)@(negedge clk);rst=1;
        command(3,32'h6700,0,6);command(3,32'h6734,0,6);
        command(3,32'h6718,0,7);command(3,32'h671c,0,7);command(3,32'h6714,0,7);
        command(3,32'h677c,0,5);command(2,32'h677c,0,5);command(3,32'h5600,0,5);
        command(3,32'h1000,0,6);command(3,32'h1028,0,7);
        command(4,32'h6708,0,6);command(4,32'h6718,0,7);
        command(2,32'h5500,0,9);
        command(3,32'h672c,1,11);
        command(3,32'h6704,1,0);command(3,32'h6710,100,0);command(3,32'h672c,1,0);
        if(!mbusy)$fatal(1,"motor should be busy");command(3,32'h6710,200,8);
        $display("tb_cfg_error_paths_PASS responses=%0d real_stepper_time decoder_arbiter_crossbar RO_range_address_busy_timeout_mask",responses);$finish;
    end
    initial begin #200000;$fatal(1,"timeout");end
endmodule
