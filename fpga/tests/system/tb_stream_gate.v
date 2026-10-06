`timescale 1ns/1ps
module tb_stream_gate;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,enable=0,s_valid=0,s_sof=0,s_last=0,m_ready=0;
    reg [31:0] s_data=0; reg [3:0] s_keep=15;
    reg [15:0] source=16'h41,msg=16'h1100;
    reg [63:0] stamp=64'h12345678abcdef00;
    reg [31:0] cycle_id=32'hfedcba98,flags=5;
    wire s_ready,m_valid,m_sof,m_last,drop_pulse;
    wire [31:0] m_data,m_cycle,m_flags,drops;
    wire [3:0] m_keep;wire [15:0] m_source,m_msg;wire [63:0] m_stamp;
    integer sent=0,forwarded=0,pulses=0,i;
    reg [31:0] expected[0:15];
    reg forbid_output=0;
    stream_gate dut(.sys_clk(clk),.rst_sys_n(rst_n),.enable(enable),
        .s_valid(s_valid),.s_ready(s_ready),.s_data(s_data),.s_keep(s_keep),.s_sof(s_sof),.s_last(s_last),
        .s_source_id(source),.s_msg_id(msg),.s_timestamp(stamp),.s_cycle_id(cycle_id),.s_flags(flags),
        .m_valid(m_valid),.m_ready(m_ready),.m_data(m_data),.m_keep(m_keep),.m_sof(m_sof),.m_last(m_last),
        .m_source_id(m_source),.m_msg_id(m_msg),.m_timestamp(m_stamp),.m_cycle_id(m_cycle),.m_flags(m_flags),
        .drop_pulse(drop_pulse),.drop_count(drops));
    always @(posedge clk) if(rst_n)begin
        if(forbid_output && m_valid)$fatal(1,"disabled message became visible");
        if(s_valid && s_ready) sent=sent+1;
        if(m_valid && m_ready)begin
            if(m_data!==expected[forwarded])$fatal(1,"data index=%0d got=%h expected=%h",forwarded,m_data,expected[forwarded]);
            if({m_keep,m_source,m_msg,m_stamp,m_cycle,m_flags}!=={s_keep,source,msg,stamp,cycle_id,flags})$fatal(1,"metadata");
            if(m_sof!==s_sof || m_last!==s_last)$fatal(1,"boundaries");
            forwarded=forwarded+1;
        end
        if(drop_pulse)pulses=pulses+1;
    end
    task beat;
        input [31:0] data; input first,last;
        begin
            @(negedge clk);s_valid=1;s_data=data;s_sof=first;s_last=last;
            @(posedge clk);while(!s_ready)@(posedge clk);
            @(negedge clk);s_valid=0;
        end
    endtask
    initial begin
        expected[0]=11;expected[1]=12;expected[2]=13;expected[3]=31;expected[4]=51;
        repeat(3)@(negedge clk);rst_n=1;enable=1;
        // Lock before first handshake and preserve the complete first beat.
        @(negedge clk);s_valid=1;s_data=11;s_sof=1;s_last=0;
        @(negedge clk);enable=0;
        repeat(5)begin @(negedge clk);if(!m_valid || s_ready || m_data!=11 || !m_sof)$fatal(1,"first-valid lock");end
        m_ready=1;@(posedge clk);@(negedge clk);s_valid=0;
        beat(12,0,0);
        repeat(3)@(negedge clk);
        beat(13,0,1);
        // Re-enable while a disabled packet is draining: no suffix may escape.
        m_ready=0;enable=0;forbid_output=1;
        beat(21,1,0);enable=1;beat(22,0,0);beat(23,0,1);
        if(drops!=1 || forwarded!=3)$fatal(1,"disabled complete message");
        forbid_output=0;m_ready=1;beat(31,1,1);
        enable=0;forbid_output=1;beat(41,1,1);forbid_output=0;
        // Reset an unaccepted first beat; upstream also resets with the gate.
        enable=1;m_ready=0;
        @(negedge clk);s_valid=1;s_data=99;s_sof=1;s_last=0;
        repeat(2)@(negedge clk);rst_n=0;s_valid=0;
        @(negedge clk);rst_n=1;m_ready=1;
        beat(51,1,1);
        repeat(3)@(negedge clk);
        if(forwarded!=5 || drops!=0 || pulses!=2)$fatal(1,"final counts forwarded=%0d drops=%0d pulses=%0d",forwarded,drops,pulses);
        $display("tb_stream_gate_PASS first-valid lock, first-beat stalls, mid-message enable toggles, disabled drain, gap, single-beat, metadata, reset");$finish;
    end
    initial begin #10000;$fatal(1,"timeout");end
endmodule
