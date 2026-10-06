`timescale 1ns/1ps
module tb_cfg_error_codes;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,valid=0,wr=0;reg [31:0] addr=0,data=0;reg [3:0] strb=15;
    wire ready,err;wire [31:0] rd;wire [15:0] codes;
    member1_adc_dila #(.SIMULATION(1)) dut(
        .sys_clk(clk),.rst_sys_n(rst),.timestamp_now(64'd0),.time_sync_valid(1'b1),
        .wms0_scan_start(1'b0),.wms0_cycle_id(32'd0),.wms0_sine_phase(32'd0),.wms0_phase_valid(1'b0),
        .wms1_scan_start(1'b0),.wms1_cycle_id(32'd0),.wms1_sine_phase(32'd0),.wms1_phase_valid(1'b0),
        .cfg_valid(valid),.cfg_write(wr),.cfg_addr(addr),.cfg_wdata(data),.cfg_wstrb(strb),
        .cfg_ready(ready),.cfg_rdata(rd),.cfg_error(err),.cfg_error_code(codes),
        .ADC_AD4630_BUSY(1'b0),.ADC_AD4630_SDO(8'd0),.ADC_ADC3660_DA5(1'b0),.ADC_ADC3660_DA6(1'b0),
        .ADC_ADC3660_DB5(1'b0),.ADC_ADC3660_DB6(1'b0),.ADC_ADC3660_DCLK(1'b0),.ADC_ADC3660_FCLK(1'b0),
        .raw0_ready(1'b1),.raw1_ready(1'b1),.dila0_ready(1'b1),.dila1_ready(1'b1));
    integer page,n=0;reg [31:0] base;reg [15:0] expected;
    task access;
        input w;input [31:0] a,d;input [3:0] code;input integer slot;
        begin
            @(negedge clk);valid=1;wr=w;addr=a;data=d;#1;
            expected=code<<(slot*4);
            if(!ready || err!==(code!=0) || codes!==expected)$fatal(1,"CFG_CODE addr=%h expected=%h got=%h ready=%b err=%b",a,expected,codes,ready,err);
            if(!w && code==0 && a[7:0]==4 && rd!==0)$fatal(1,"REJECT_CHANGED_ENABLE");
            @(negedge clk);valid=0;wr=0;#1;
            if(ready || err || codes)$fatal(1,"CFG_CODE_IDLE");n=n+1;
        end
    endtask
    initial begin
        repeat(5)@(negedge clk);rst=1;
        for(page=0;page<4;page=page+1)begin
            case(page)0:base='h4000;1:base='h4100;2:base='h5000;3:base='h5100;endcase
            access(0,base+1,0,5,page);access(0,base+'hfc,0,5,page);
            access(1,base,1,6,page);access(1,base+8,1,6,page);
            access(1,base+'h10,0,7,page);access(1,base+4,'h10,7,page);
            access(0,base+4,0,0,page);
            access(1,base+4,4,0,page);access(1,base+4,4,8,page);
            access(1,base+4,2,0,page);
            strb=0;access(1,base+4,'hffffffff,0,page);strb=15;
        end
        access(1,'h4030,1,7,0);
        access(1,'h4134,0,6,1);access(1,'h4140,0,6,1);access(0,'h4040,0,5,0);
        @(negedge clk);addr='h6000;valid=1;#1;if(ready || err || codes || rd)$fatal(1,"FOREIGN_PAGE");
        $display("CFG_ERROR_CODES_PASS checks=%0d all four packed nibbles, 5/6/7/8, masked writes, no write side effects",n);$finish;
    end
    initial begin #100000;$fatal(1,"TIMEOUT");end
endmodule
