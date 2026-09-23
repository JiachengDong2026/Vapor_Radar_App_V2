`timescale 1ns/1ps
// Datasheet pin model. SPI register decoder and data serializer do not reuse DUT helpers.
module ad4630_model #(
    parameter real FPGA_OUTPUT_DELAY_NS=4.0,
    parameter real BOARD_FLIGHT_NS=1.0,
    parameter real CONVERSION_MAX_NS=300.0,
    parameter real DATA_DELAY_NS=5.6,
    parameter real CSEN_DELAY_NS=6.8,
    parameter real REGISTER_DELAY_NS=9.4
)(
    input wire rst_n,input wire cnv,input wire cs_n,input wire sck,input wire sdi,
    input wire stall_busy,
    output reg busy,output reg [7:0] sdo,
    output reg [31:0] conversions,output reg configured
);
    // Delayed physical pins model outbound FPGA pad budget plus board flight.
    // ADC output uses the official worst-case delay plus return board flight.
    wire pin_sck,pin_csn,pin_cnv,pin_sdi,pin_rst;
    assign #(FPGA_OUTPUT_DELAY_NS+BOARD_FLIGHT_NS) pin_sck=sck;
    assign #(FPGA_OUTPUT_DELAY_NS+BOARD_FLIGHT_NS) pin_csn=cs_n;
    assign #(FPGA_OUTPUT_DELAY_NS+BOARD_FLIGHT_NS) pin_cnv=cnv;
    assign #(FPGA_OUTPUT_DELAY_NS+BOARD_FLIGHT_NS) pin_sdi=sdi;
    assign #(FPGA_OUTPUT_DELAY_NS+BOARD_FLIGHT_NS) pin_rst=rst_n;
    realtime last_cnv_rise=0,last_cnv_fall=0,last_sck_rise=0,last_sck_fall=0,last_cs_fall=0;
    realtime last_activity=0;
    always @(pin_csn or pin_sck or pin_sdi)if(pin_rst && configured)begin
        if(last_cnv_rise!=0 && $realtime-last_cnv_rise<9.8)$fatal(1,"AD4630_QUIET_AFTER_CNV");
        last_activity=$realtime;
    end
    reg [7:0] next_sdo;
    reg register_mode;
    reg [7:0] modes;
    reg [23:0] command;
    reg [23:0] conversion_word;
    reg [5:0] edges;
    reg [2:0] group;
    reg [7:0] read_word;
    reg reading;
    function [23:0] pattern;
        input [31:0] index;
        begin
            case(index%8)
                0:pattern=24'h123456;1:pattern=24'hfedcba;
                2:pattern=24'h7fffff;3:pattern=24'h800000;
                4:pattern=24'h000001;5:pattern=24'hffffff;
                6:pattern=24'h555555;default:pattern=24'haaaaaa;
            endcase
        end
    endfunction
    initial begin register_mode=0;modes=0;command=0;conversion_word=0;edges=0;group=0;read_word=0;reading=0;busy=0;sdo=0;conversions=0;configured=0;end
    always @(negedge pin_rst)begin register_mode=0;modes=0;configured=0;conversions=0;busy=0;end
    always @(posedge pin_cnv)if(pin_rst)begin
        if(!configured)$fatal(1,"AD4630 conversion before explicit mode initialization");
        conversion_word=pattern(conversions);conversions=conversions+1;busy=1;
        #(CONVERSION_MAX_NS+BOARD_FLIGHT_NS);if(!stall_busy)busy=0;
    end
    always @(negedge pin_csn)begin
        command=0;edges=0;group=0;reading=0;sdo=0;last_cs_fall=$realtime;
        if(!register_mode)begin
            sdo <= #(CSEN_DELAY_NS+BOARD_FLIGHT_NS) {4'd0,conversion_word[20],conversion_word[21],conversion_word[22],conversion_word[23]};
        end
    end
    always @(posedge pin_sck)if(!pin_csn)begin
        if(edges==0 && $realtime-last_cs_fall<(register_mode?11.6:9.8))$fatal(1,"AD4630_CS_SETUP");
        if(edges!=0 && $realtime-last_sck_fall<(register_mode?5.2:4.2))$fatal(1,"AD4630_SCK_LOW");
        last_sck_rise=$realtime;
        command={command[22:0],pin_sdi};edges=edges+1;
        if(register_mode && edges==16 && command[15])begin reading=1;read_word=(command[14:0]==15'h20)?modes:0;end
    end
    always @(negedge pin_sck)if(!pin_csn)begin
        if($realtime-last_sck_rise<(register_mode?5.2:4.2))$fatal(1,"AD4630_SCK_HIGH");
        last_sck_fall=$realtime;
        if(register_mode)begin
            if(reading && edges>=16 && edges<24)sdo[0] <= #(REGISTER_DELAY_NS+BOARD_FLIGHT_NS) read_word[23-edges];
        end else if(edges<6)begin
            group=edges;
            next_sdo={4'd0,conversion_word[20-group*4],conversion_word[21-group*4],conversion_word[22-group*4],conversion_word[23-group*4]};
            sdo <= #(DATA_DELAY_NS+BOARD_FLIGHT_NS) next_sdo;
        end
    end
    always @(negedge pin_cnv)if(pin_rst && last_cnv_rise!=0)begin
        if($realtime-last_cnv_rise<10)$fatal(1,"AD4630_CNV_HIGH");last_cnv_fall=$realtime;
    end
    always @(posedge pin_cnv)if(pin_rst)begin
        if(configured && $realtime-last_activity<19.6)$fatal(1,"AD4630_QUIET_BEFORE_CNV");
        if(last_cnv_rise!=0 && $realtime-last_cnv_rise<500)$fatal(1,"AD4630_CNV_PERIOD");
        if(last_cnv_fall!=0 && $realtime-last_cnv_fall<20)$fatal(1,"AD4630_CNV_LOW");last_cnv_rise=$realtime;
    end
    always @(posedge pin_csn)begin
        if(edges!=0 && $realtime-last_sck_fall<(register_mode?5.2:4.2))$fatal(1,"AD4630_CS_HOLD");
        if(edges==24)begin
            if(command==24'hbfff00)register_mode=1;
            else if(register_mode && !command[23])begin
                if(command[22:8]==15'h20)modes=command[7:0];
                if(command[22:8]==15'h14 && command[0])begin
                    if(modes!=8'h80)$fatal(1,"AD4630 unexpected lane/mode %h",modes);
                    configured=1;register_mode=0;
                end
            end
        end
    end
endmodule
