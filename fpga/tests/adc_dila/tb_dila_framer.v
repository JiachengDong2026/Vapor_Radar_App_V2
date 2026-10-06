`timescale 1ns/1ps
module tb_dila_framer;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,pv=0,bv=0,clear=0,run_ready=1,score=1;
    reg [191:0] pd=0;
    reg [193:0] pt=0;
    reg [31:0] bc=0;
    wire [2:0] mv,ms,ml;
    reg [2:0] mr=0;
    wire [31:0] md[0:2],mc[0:2],mf[0:2],drops[0:2],frags[0:2],levels[0:2];
    wire [63:0] mt[0:2];
    wire [3:0] mk[0:2];
    wire [15:0] sid[0:2],mid[0:2];
    integer header[0:2],point[0:2],wordn[0:2],fragment[0:2],cyc[0:2],seen[0:2];
    reg stalled[0:2];
    reg [199:0] held[0:2];
    reg [31:0] expected_word;
    integer g,k,n,c,words,fraglen;
    reg [31:0] random_state=32'h12345678;
    genvar v;
    generate for(v=0;v<3;v=v+1)begin:gens
        dila_block_framer #(.MAX_POINTS(1024),.OUTPUT_FORMAT(v),.SOURCE_ID(16'h0030+v)) dut(
            .clk(clk),.rst_n(rst_n),.clear(clear),.point_valid(pv),.point_data(pd),.point_tag(pt),.point_flags(32'd0),
            .output_rate(32'd10000),.fragment_points(32'd256),.boundary_valid(bv),.boundary_cycle(bc),.boundary_partial(1'b0),
            .drop_count(drops[v]),.last_fragment_count(frags[v]),.level(levels[v]),
            .m_valid(mv[v]),.m_ready(mr[v]),.m_data(md[v]),.m_keep(mk[v]),.m_sof(ms[v]),.m_last(ml[v]),
            .m_source_id(sid[v]),.m_msg_id(mid[v]),.m_timestamp(mt[v]),.m_cycle_id(mc[v]),.m_flags(mf[v]));
    end endgenerate
    always @(negedge clk)begin
        random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
        mr=run_ready ? random_state[2:0]|3'b010:0;
    end
    always @(posedge clk)if(rst_n && score)begin
        for(g=0;g<3;g=g+1)begin
            if(stalled[g] && (!mv[g] || held[g]!=={md[g],mk[g],ms[g],ml[g],sid[g],mid[g],mt[g],mc[g],mf[g],2'd0}))$fatal(1,"Framer %0d stability",g);
            stalled[g]=mv[g]&&!mr[g];held[g]={md[g],mk[g],ms[g],ml[g],sid[g],mid[g],mt[g],mc[g],mf[g],2'd0};
            if(mv[g]&&mr[g])begin
                words=g==0?2:(g==1?4:6);fraglen=fragment[g]<2?256:88;
                if(sid[g]!=16'h30+g || mid[g]!=16'h1001 || mc[g]!=cyc[g] || mt[g]!=cyc[g]*1000 || mf[g]!=7 || mk[g]!=15)$fatal(1,"Framer metadata format=%0d",g);
                if(header[g]<8)begin
                    case(header[g])
                        0:expected_word=(g<<16)|2;1:expected_word=10000;2:expected_word=600;
                        3:expected_word=(3<<16)|fragment[g];4:expected_word=fragment[g]*256;
                        5:expected_word=fraglen;6:expected_word=words*4;default:expected_word=0;
                    endcase
                    if(md[g]!==expected_word || ms[g]!=(header[g]==0) || ml[g])$fatal(1,"Framer header f=%0d h=%0d got=%h expected=%h",g,header[g],md[g],expected_word);
                    header[g]=header[g]+1;
                end else begin
                    if(g==0)expected_word=point[g]+(wordn[g]==0?1000:2000);
                    else case(wordn[g])
                        0:expected_word=point[g]+100;1:expected_word=point[g]+200;
                        2:expected_word=point[g]+300;3:expected_word=point[g]+400;
                        4:expected_word=point[g]+1000;default:expected_word=point[g]+2000;
                    endcase
                    if(md[g]!==expected_word || ms[g])$fatal(1,"Framer payload format=%0d pt=%0d word=%0d got=%h expected=%h",g,point[g],wordn[g],md[g],expected_word);
                    if(ml[g]!==((point[g]+1==fragment[g]*256+fraglen)&&(wordn[g]==words-1)))$fatal(1,"Framer LAST");
                    if(wordn[g]==words-1)begin
                        wordn[g]=0;point[g]=point[g]+1;seen[g]=seen[g]+1;
                        if(point[g]==600)begin point[g]=0;fragment[g]=0;header[g]=0;cyc[g]=cyc[g]+1;end
                        else if(point[g]==fragment[g]*256+fraglen)begin fragment[g]=fragment[g]+1;header[g]=0;end
                    end else wordn[g]=wordn[g]+1;
                end
            end
        end
    end
    task push;
        input integer cycle_value,index;
        reg [63:0] cycle_tick;
        reg [31:0] iv,cvv;
        begin
            iv=index;cvv=cycle_value;cycle_tick=cycle_value*1000;
            @(negedge clk);pv=1;pd={iv+32'd2000,iv+32'd1000,iv+32'd400,iv+32'd300,iv+32'd200,iv+32'd100};
            pt={2'b11,cycle_tick,64'd0,32'd0,cvv};
            @(negedge clk);pv=0;
        end
    endtask
    initial begin #2000000;$fatal(1,"Framer watchdog");end
    initial begin
        for(k=0;k<3;k=k+1)begin header[k]=0;point[k]=0;wordn[k]=0;fragment[k]=0;cyc[k]=1;seen[k]=0;stalled[k]=0;held[k]=0;end
        repeat(5)@(negedge clk);rst_n=1;
        for(c=1;c<=2;c=c+1)for(n=0;n<600;n=n+1)begin push(c,n);repeat(10)@(negedge clk);end
        @(negedge clk);bv=1;bc=3;@(negedge clk);bv=0;
        wait(seen[0]==1200 && seen[1]==1200 && seen[2]==1200);
        score=0;run_ready=0;
        repeat(4)@(negedge clk);
        for(c=3;c<=5;c=c+1)for(n=0;n<32;n=n+1)push(c,n);
        repeat(5)@(negedge clk);
        if(drops[0]==0 || drops[1]==0 || drops[2]==0)$fatal(1,"Framer buffer overflow missing");
        clear=1;@(negedge clk);clear=0;repeat(2)@(negedge clk);
        if(|mv || levels[0]!=0 || levels[1]!=0 || levels[2]!=0)$fatal(1,"Framer clear");
        $display("DILA_FRAMER_PASS formats=3 points=3600 fragmentation=256/256/88 overflow_reset=PASS");$finish;
    end
endmodule
