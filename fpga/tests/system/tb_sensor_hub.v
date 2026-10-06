`timescale 1ns/1ps
module tb_sensor_hub;
    localparam N=7;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,ready=0;
    reg[N-1:0]v=0;wire[N-1:0]rdy;
    reg[N*32-1:0]data=0;reg[N*4-1:0]keep={N{4'hf}};
    reg[N-1:0]sof={N{1'b1}},last=0;
    reg[N*16-1:0]src=0;wire valid,os,ol;
    wire[31:0]od;wire[3:0]ok;wire[15:0]oid;wire[63:0]gc;
    reg[N-1:0]fire=0;
    integer counts[0:N-1];integer word_index[0:N-1];integer frame_index[0:N-1];
    integer i,clock_count=0,accepted=0,cur_source=-1,within=0;
    reg held=0;reg[55:0]held_data;
    sensor_hub #(.N(N))dut(.sys_clk(clk),.rst_sys_n(rst),.s_valid(v),.s_ready(rdy),.s_data(data),.s_keep(keep),.s_sof(sof),.s_last(last),
      .s_source_id(src),.s_msg_id({N{16'h1100}}),.s_timestamp({N{64'd123}}),.s_cycle_id({N{32'hffffffff}}),.s_flags({N{32'd5}}),
      .m_data(od),.m_keep(ok),.m_sof(os),.m_last(ol),.m_source_id(oid),.m_msg_id(),.m_timestamp(),.m_cycle_id(),.m_flags(),
      .m_valid(valid),.m_ready(ready),.grant_count(gc),.pending_mask());
    always @(posedge clk)if(rst)begin
        fire=v & rdy;
        if(held && (!valid || {oid,os,ol,ok,od}!==held_data))$fatal(1,"unstable stalled beat");
        held<=valid && !ready;held_data<={oid,os,ol,ok,od};
        if(valid && ready)begin
            if(within==0)begin
                if(!os)$fatal(1,"missing SOF");cur_source=oid;
            end else if(os || cur_source!=oid)$fatal(1,"interleaving");
            if(od!=={oid[7:0],frame_index[oid][15:0],word_index[oid][7:0]})$fatal(1,"reordered data");
            if(ol)begin
                if(within!=2)$fatal(1,"wrong length");counts[oid]=counts[oid]+1;within=0;accepted=accepted+1;
            end else within=within+1;
        end
    end
    always @(negedge clk)if(rst)begin
        clock_count=clock_count+1;
        // Previous edge's handshake advanced exactly one chosen producer.
        for(i=0;i<N;i=i+1)begin
            if(fire[i])begin
                if(word_index[i]==2)begin word_index[i]=0;frame_index[i]=frame_index[i]+1;end
                else word_index[i]=word_index[i]+1;
            end
            data[i*32+:32]={i[7:0],frame_index[i][15:0],word_index[i][7:0]};
            sof[i]=(word_index[i]==0);last[i]=(word_index[i]==2);
        end
        ready=(clock_count%9)>2;
    end
    initial begin
        for(i=0;i<N;i=i+1)begin counts[i]=0;word_index[i]=0;frame_index[i]=0;src[i*16+:16]=i;data[i*32+:32]=i<<24;end
        repeat(4)@(negedge clk);#1;rst=1;v={N{1'b1}};
        wait(accepted>=96);@(negedge clk);#1;
        for(i=0;i<N;i=i+1)if(counts[i]<3)$fatal(1,"starved producer %d count %d",i,counts[i]);
        if(gc!=accepted)$fatal(1,"grant counter");
        rst=0;#1;if(valid)$fatal(1,"reset failed");
        $display("tb_sensor_hub_PASS");$finish;
    end
    initial begin #200000;$fatal(1,"timeout");end
endmodule
