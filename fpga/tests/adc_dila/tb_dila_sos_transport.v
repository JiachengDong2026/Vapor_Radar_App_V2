`timescale 1ns/1ps
// Exercise VLP command decoding, multiword bank transport and lane isolation.
module tb_dila_sos_transport;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,command_valid=0,m_ready=0;
    reg [15:0] source=16'h30,command_id=0;
    reg [31:0] sequence_id=0,payload_bytes=0;
    reg [31:0] request_words[0:31],response_words[0:63];
    wire done,bv,bw,br,be,mv,ml;
    wire [31:0] read_word,ba,bd,brd,md;
    wire [3:0] bs,bc;
    wire [1:0] lane_ready,lane_error;
    wire [31:0] lane_data[0:1];wire [3:0] lane_code[0:1];
    integer i,tick=0,received=0;
    reg [959:0] identity;
    cmd_decoder decoder(.sys_clk(clk),.rst_sys_n(rst),.timestamp_now(64'd0),
        .command_valid(command_valid),.command_done(done),.command_status(32'd0),.command_sequence(sequence_id),
        .command_payload_bytes(payload_bytes),.command_source(source),.command_id(command_id),
        .payload_read_word(read_word),.payload_read_data(request_words[read_word[4:0]]),
        .cfg_valid(bv),.cfg_write(bw),.cfg_addr(ba),.cfg_wdata(bd),.cfg_wstrb(bs),.cfg_ready(br),
        .cfg_error(be),.cfg_error_code(bc),.cfg_rdata(brd),.action_ready(1'b0),.action_status(32'd0),
        .m_valid(mv),.m_ready(m_ready),.m_data(md),.m_last(ml));
    assign br=|lane_ready;assign be=|lane_error;
    assign brd=lane_data[0]|lane_data[1];assign bc=lane_code[0]|lane_code[1];
    genvar ch;
    generate for(ch=0;ch<2;ch=ch+1)begin : lanes
        dila_core #(.BASE_ADDR(32'h5000+ch*256),.SOURCE_ID(16'h30+ch),.USE_CAPTURE_TAGS(1),.MAX_POINTS(64)) dut(
            .sys_clk(clk),.rst_sys_n(rst),.sample_valid(1'b0),.sample_data(32'd0),.sample_flags(8'd0),
            .wms_scan_start(1'b0),.wms_cycle_id(32'd0),.wms_sine_phase(32'd0),.wms_phase_valid(1'b1),
            .timestamp_now(64'd0),.time_sync_valid(1'b1),.capture_tag(194'd0),.input_sample_rate_hz(32'd1000000),
            .expected_per_cycle(32'd0),.input_overflow_pulse(1'b0),.cfg_valid(bv),.cfg_write(bw),.cfg_addr(ba),
            .cfg_wdata(bd),.cfg_wstrb(bs),.cfg_ready(lane_ready[ch]),.cfg_rdata(lane_data[ch]),
            .cfg_error(lane_error[ch]),.cfg_error_code(lane_code[ch]),.m_ready(1'b1));
    end endgenerate
    always @(negedge clk)begin tick=tick+1;m_ready=tick%7<3;end
    always @(posedge clk)if(rst && mv && m_ready)begin
        response_words[received]=md;received=received+1;
    end
    task transact;
        input [15:0] id;
        input [31:0] bytes;
        input expect_error;
        begin
            @(negedge clk);received=0;sequence_id=sequence_id+1;command_id=id;payload_bytes=bytes;command_valid=1;
            @(posedge clk);while(!done)@(posedge clk);
            @(negedge clk);command_valid=0;repeat(5)@(negedge clk);
            if(received==0 || (response_words[0]!=0)!==expect_error)$fatal(1,"transport status id=%h value=%h",id,response_words[0]);
        end
    endtask
    task write_one;
        input [31:0] address,value;
        begin request_words[0]=address;request_words[1]=1;request_words[2]=value;transact(3,12,0);end
    endtask
    task read_one;
        input [31:0] address,expected_value;
        begin
            request_words[0]=address;request_words[1]=1;transact(2,8,0);
            if(received!=4 || response_words[1]!=address || response_words[2]!=1 || response_words[3]!==expected_value)
                $fatal(1,"transport read address=%h got=%h expected=%h",address,response_words[3],expected_value);
        end
    endtask
    initial begin
        identity=0;for(i=0;i<4;i=i+1)identity[i*240 +:48]=48'd70368744177664;
        repeat(5)@(negedge clk);rst=1;
        read_one(32'h50F0,32'h534f5301);
        write_one(32'h5060,8);
        request_words[0]=32'h50E0;request_words[1]=2;request_words[2]=1000000;request_words[3]=1250;transact(3,16,0);
        request_words[0]=32'h5068;request_words[1]=30;
        for(i=0;i<30;i=i+1)request_words[i+2]=identity[i*32 +:32];
        transact(3,128,0);
        request_words[0]=32'h5068;request_words[1]=30;transact(2,8,0);
        if(received!=33)$fatal(1,"bulk read length");
        for(i=0;i<30;i=i+1)if(response_words[i+3]!==identity[i*32 +:32])$fatal(1,"bulk coefficient word %0d",i);
        write_one(32'h5004,4);repeat(180)@(negedge clk);
        read_one(32'h5064,8);read_one(32'h50EC,1250);read_one(32'h50F8,1);read_one(32'h5024,32'h80000008);
        // Wrong source must not write the other channel.
        request_words[0]=32'h5160;request_words[1]=1;request_words[2]=2;transact(3,12,1);
        source=16'h31;read_one(32'h5164,4);read_one(32'h51F8,0);read_one(32'h5124,32'h00040101);
        $display("DILA_SOS_TRANSPORT_PASS bulk_write_read ack_backpressure ownership lane_isolation");$finish;
    end
    initial begin #1000000;$fatal(1,"SOS transport timeout");end
endmodule
