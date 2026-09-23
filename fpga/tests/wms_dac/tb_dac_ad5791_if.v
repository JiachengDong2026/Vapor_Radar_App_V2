`timescale 1ns/1ps
module tb_dac_ad5791_if;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,enable=1,active=0,valid=0;reg [31:0] sample_data=0;
    wire [3:0] error_code;reg [3:0] last_code;
    wire ready,op;wire [31:0] cap;
    wire cv,cw,cr,ce;wire [31:0] ca,cd,rd;wire [3:0] cs;
    always @(posedge clk)if(cv && cr)last_code<=error_code;
    wire sclk,sync_n,sdin,reset_n,clr_n,ldac_n;
    wire [19:0] code,control,clear_code;wire [23:0] frame;wire [31:0] frames;
    reg [31:0] x,g,o,lo,hi,expected,data;integer f,r,n;
    realtime last_fall=0;reg saw_fall=0;
    always @(negedge sync_n)saw_fall=0;
    always @(negedge sclk)if(reset_n && !sync_n)begin
        if(saw_fall && $realtime-last_fall<60)$fatal(1,"DAC_SAFE_PERIOD_MARGIN");
        last_fall=$realtime;saw_fall=1;
    end
    cfg_test_bfm bus(.clk(clk),.rst_n(rst),.cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(cs),.cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce));
    dac_ad5791_if dut(.sys_clk(clk),.rst_sys_n(rst),.enable(enable),.timestamp_now(64'd0),.time_sync_valid(1'b1),.stream_active(active),
        .cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(cs),.cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce),.cfg_error_code(error_code),
        .dac_sample(sample_data),.dac_sample_valid(valid),.dac_sample_ready(ready),.operational(op),.max_update_hz(cap),
        .dac_sclk(sclk),.dac_sync_n(sync_n),.dac_sdin(sdin),.dac_sdo(1'b0),.dac_rst_n(reset_n),.dac_clr_n(clr_n),.dac_ldac_n(ldac_n));
    ad5791_model model(.sclk(sclk),.sync_n(sync_n),.sdin(sdin),.rst_n(reset_n),.clr_n(clr_n),.ldac_n(ldac_n),
        .code(code),.control(control),.clear_code(clear_code),.last_frame(frame),.frame_count(frames));
    always @(posedge sync_n)begin
        #1;
        case(frames)
            1:if(frame!==24'h20031e)$fatal(1,"INIT_CLAMP_ORDER");
            2:if(frame!==24'h380000)$fatal(1,"INIT_CLEAR_ORDER");
            3:if(frame!==24'h180000)$fatal(1,"INIT_DATA_ORDER");
            4:if(frame!==24'h200312)$fatal(1,"INIT_ENABLE_ORDER");
            default:begin end
        endcase
    end
    task expect_code;
        input w;input [31:0] a,d;input [3:0] c;
        begin bus.expect_error(w,a,d);if(last_code!==c)$fatal(1,"DAC_CFG_CODE addr=%h expected=%d got=%d",a,c,last_code);end
    endtask
    task wait_idle;
        begin bus.read32('h3008,data);while(!data[1] || data[3])bus.read32('h3008,data);end
    endtask
    task sample;
        input [31:0] value;
        begin
            @(negedge clk);sample_data=value;valid=1;
            begin:accept forever begin @(posedge clk);if(ready)disable accept;end end
            @(negedge clk);valid=0;
            wait(!sync_n);wait(sync_n);#1;
        end
    endtask
    initial begin
        repeat(5)@(negedge clk);rst=1;wait_idle;
        if(frames!=4 || control!==20'h312 || code!==20'h80000 || clear_code!==20'h80000)$fatal(1,"INIT_SEQUENCE");
        if(cap!=609756)$fatal(1,"CAPACITY %d",cap);
        bus.read32('h3024,data);if(data!=20000000)$fatal(1,"DEFAULT_SPI_REQUEST");
        bus.read32('h303c,data);if(data!=16666666)$fatal(1,"DEFAULT_SPI_ACTUAL");
        for(n=0;n<=17;n=n+1)bus.read32('h3000+4*n,data);
        bus.masked('h3038,'h12345678,5);bus.read32('h3038,data);if(data!=='h00340078)$fatal(1,"DAC_WSTRB");bus.write32('h3038,0);
        bus.outside('h10003000);bus.outside('h3100);
        expect_code(0,'h3001,0,5);expect_code(0,'h30fc,0,5);expect_code(1,'h3020,1,6);expect_code(1,'h3004,'h20,7);
        bus.write32('h3024,0);expect_code(1,'h3004,4,7);
        bus.write32('h3024,20000001);expect_code(1,'h3004,4,7);
        bus.write32('h3024,25000000);expect_code(1,'h3004,4,7);bus.write32('h3024,20000000);
        bus.write32('h3018,'hfffff);bus.write32('h301c,0);expect_code(1,'h3004,4,7);
        bus.write32('h3018,0);bus.write32('h301c,'hfffff);
        bus.write32('h3010,2);expect_code(1,'h3004,4,7);bus.write32('h3010,'h312);
        bus.write32('h3010,'h352);expect_code(1,'h3004,4,7);bus.write32('h3010,'h312);
        active=1;expect_code(1,'h3004,4,8);expect_code(1,'h3004,16,8);active=0;
        bus.write32('h300c,'hffffffff);bus.read32('h300c,data);if(data)$fatal(1,"ERROR_W1C");
        f=$fopen("dac_vectors.txt","r");if(!f)$fatal(1,"VECTOR_OPEN");n=0;
        while(!$feof(f))begin
            r=$fscanf(f,"%h %h %h %h %h %h\n",x,g,o,lo,hi,expected);if(r!=6)$fatal(1,"VECTOR_FORMAT");
            wait_idle;bus.write32('h3034,g);bus.write32('h3038,o);bus.write32('h3018,lo);bus.write32('h301c,hi);
            bus.write32('h3004,5);wait_idle;sample(x);
            if(code!==expected[19:0] || frame!=={4'h1,expected[19:0]})$fatal(1,"DAC_GOLDEN n=%d got=%h expected=%h",n,code,expected);
            bus.read32('h3020,data);if(data!==expected)$fatal(1,"LAST_CODE");n=n+1;
        end
        bus.read32('h3028,data);if(data!=133)$fatal(1,"WRITE_COUNT %d",data);
        wait_idle;bus.write32('h3004,17);wait(clr_n);#1;if(code!==clear_code)$fatal(1,"CLEAR_CODE");
        wait_idle;bus.write32('h3024,13000000);bus.write32('h3004,5);wait_idle;
        bus.read32('h303c,data);if(data!=12500000)$fatal(1,"SPI_DIVIDER_ROUND");sample(0);
        // Reset aborts an incomplete frame and performs a fresh safe initialization.
        wait_idle;@(negedge clk);sample_data=32'h7fffffff;valid=1;wait(ready);@(negedge clk);valid=0;
        wait(!sync_n);repeat(8)@(negedge clk);rst=0;repeat(5)@(negedge clk);rst=1;wait_idle;
        if(code!==20'h80000 || control!==20'h312)$fatal(1,"RESET_RECOVERY");
        $display("TEST_PASS tb_dac_ad5791_if 133 golden samples, timing model, cfg, clamp, clear, divider, reset during SPI");$finish;
    end
    initial begin #10000000;$fatal(1,"TIMEOUT");end
endmodule
