`timescale 1ns/1ps
module tb_dila_coeff_upload;
    localparam [47:0] Q46_ONE=48'd70368744177664;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,cv=0,cw=0,sv=0;
    reg [31:0] ca=0,cd=0;
    reg [193:0] tag=0;
    reg [959:0] bank=0;
    reg [31:0] readback;
    reg [31:0] input_rate=1000000,old_generation;
    reg [3:0] strobes=4'hf;
    wire cr,ce,sr;wire [31:0] rd;
    integer i,order_value;
    dila_core #(.USE_CAPTURE_TAGS(1),.OUTPUT_FORMAT(1),.MAX_POINTS(512)) dut(
        .sys_clk(clk),.rst_sys_n(rst),.sample_valid(sv),.sample_ready(sr),.sample_data(32'd1000000),.sample_flags(8'd0),
        .wms_scan_start(1'b0),.wms_cycle_id(32'd1),.wms_sine_phase(32'd0),.wms_phase_valid(1'b1),
        .timestamp_now(64'd1),.time_sync_valid(1'b1),.capture_tag(tag),.input_sample_rate_hz(input_rate),
        .expected_per_cycle(32'd0),.input_overflow_pulse(1'b0),.cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),
        .cfg_wdata(cd),.cfg_wstrb(strobes),.cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce),.m_ready(1'b1));

    task write_reg;
        input [7:0] offset;input [31:0] value;input expect_error;
        begin
            @(negedge clk);cv=1;cw=1;ca=32'h5000+offset;cd=value;
            @(posedge clk);if(!cr || ce!==expect_error)$fatal(1,"cfg write ofs=%h error=%b expected=%b",offset,ce,expect_error);
            @(negedge clk);cv=0;cw=0;
        end
    endtask
    task read_reg;
        input [7:0] offset;output [31:0] value;
        begin
            @(negedge clk);cv=1;cw=0;ca=32'h5000+offset;
            @(posedge clk);if(!cr || ce)$fatal(1,"cfg read ofs=%h",offset);value=rd;
            @(negedge clk);cv=0;
        end
    endtask
    task make_identity_bank;
        integer section_index;
        begin
            bank=0;
            for(section_index=0;section_index<4;section_index=section_index+1)begin
                bank[section_index*240 +:48]=Q46_ONE;
            end
        end
    endtask
    task upload;
        input integer requested_order;
        input expect_commit_error;
        integer word_index;
        reg [31:0] ignored;
        begin
            write_reg(8'hE0,1000000,0);
            write_reg(8'hE4,1000,0);
            write_reg(8'h60,requested_order,0);
            for(word_index=0;word_index<30;word_index=word_index+1)
                write_reg(8'h68+word_index*4,bank[word_index*32 +:32],0);
            write_reg(8'h04,4,expect_commit_error);
            if(!expect_commit_error)begin
                repeat(160)@(negedge clk);
                if(dut.pending || dut.order_active!=requested_order)$fatal(1,"order commit %0d active=%0d",requested_order,dut.order_active);
                for(word_index=0;word_index<30;word_index=word_index+1)begin
                    read_reg(8'h68+word_index*4,ignored);
                    if(ignored!==bank[word_index*32 +:32])$fatal(1,"coefficient packed word %0d",word_index);
                end
            end
        end
    endtask
    task send_sample;
        input [31:0] cycle_id;
        begin
            @(negedge clk);tag={2'b11,64'd1,64'd1,32'd0,cycle_id};sv=1;
            while(!sr)@(negedge clk);
            @(negedge clk);sv=0;repeat(40)@(negedge clk);
        end
    endtask

    initial begin
        repeat(5)@(negedge clk);rst=1;
        read_reg(8'hF0,readback);if(readback!=32'h534f5301)$fatal(1,"SOS capability ID");
        write_reg(8'h64,0,1);write_reg(8'hF0,0,1);write_reg(8'hE8,0,1);
        write_reg(8'h60,1,1);write_reg(8'h60,9,1);write_reg(8'h69,0,1);
        write_reg(8'h60,2,0);write_reg(8'h04,4,1); // incomplete bank
        strobes=4'h3;write_reg(8'h68,0,1);strobes=4'hf;
        write_reg(8'h04,2,0); // abort upload
        make_identity_bank();
        for(order_value=2;order_value<=8;order_value=order_value+1)upload(order_value,0);

        // A denominator pole on the unit circle must be rejected at commit.
        bank[144 +:48]=-Q46_ONE;
        upload(2,1);
        bank[144 +:48]=Q46_ONE;upload(2,1); // pole at -1
        bank[144 +:48]=0;bank[192 +:48]=Q46_ONE;upload(2,1); // conjugate unit poles
        make_identity_bank();bank[192 +:48]=-Q46_ONE;upload(2,1);
        make_identity_bank();bank[240+96 +:48]=1;upload(3,1); // odd last section b2 must be zero
        make_identity_bank();
        upload(2,0);

        // A commit while enabled stays pending until the next capture-cycle boundary.
        bank[240 +:48]=Q46_ONE; // first-order section is represented with b2=a2=0.
        upload(3,0);
        if(dut.order_active!=3)$fatal(1,"disabled order update failed");
        write_reg(8'h04,1,0);
        write_reg(8'h60,5,0);
        for(i=0;i<30;i=i+1)write_reg(8'h68+i*4,bank[i*32 +:32],0);
        write_reg(8'h04,5,0);
        repeat(160)@(negedge clk);
        if(!dut.pending || dut.order_active!=3)$fatal(1,"active config changed before cycle boundary");
        write_reg(8'h68,0,1);write_reg(8'h60,2,1);write_reg(8'hE0,500000,1);write_reg(8'h58,500,1);
        write_reg(8'h04,5,1); // duplicate commit
        send_sample(1);
        if(dut.pending || dut.order_active!=5)$fatal(1,"config not applied at cycle boundary");
        read_reg(8'h64,readback);
        if(readback!=5)$fatal(1,"active order readback");
        old_generation=dut.filter_generation;
        write_reg(8'h04,0,0);
        // Design rate mismatch and Nyquist boundary are rejected.
        write_reg(8'h60,2,0);
        for(i=0;i<30;i=i+1)write_reg(8'h68+i*4,bank[i*32 +:32],0);
        write_reg(8'hE0,500000,0);write_reg(8'h04,4,1);
        write_reg(8'hE0,1000000,0);write_reg(8'hE4,500000,0);write_reg(8'h04,4,1);
        write_reg(8'hE4,1000,0);
        // A rate change after accepted commit must cancel rather than activate stale coefficients.
        write_reg(8'h04,4,0);input_rate=500000;
        repeat(160)@(negedge clk);
        if(dut.pending || dut.filter_generation!=old_generation || !dut.error_status[8])$fatal(1,"stale rate commit cancellation");
        write_reg(8'h04,1,0);repeat(4)@(negedge clk);
        if(sr || !dut.error_status[8])$fatal(1,"rate mismatch must block samples");
        write_reg(8'h04,2,0);input_rate=1000000;
        // Explicit order=0 returns to legacy even when the legacy cutoff is unchanged.
        write_reg(8'h60,0,0);write_reg(8'h04,4,0);repeat(160)@(negedge clk);
        if(dut.coeff_active_custom || dut.order_active!=4)$fatal(1,"legacy restoration");
        if(dut.filter_generation!=old_generation+1)$fatal(1,"generation readback");
        $display("DILA_COEFF_UPLOAD_PASS order=2..8 packing stability boundary incomplete pending readonly rate abort legacy");$finish;
    end
    initial begin #1000000;$fatal(1,"coefficient upload timeout");end
endmodule
