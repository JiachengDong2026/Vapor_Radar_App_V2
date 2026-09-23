`timescale 1ns/1ps
module ad5791_model(
    input wire sclk,input wire sync_n,input wire sdin,input wire rst_n,input wire clr_n,input wire ldac_n,
    output reg [19:0] code=0,output reg [19:0] control=20'he,output reg [19:0] clear_code=0,
    output reg [23:0] last_frame=0,output reg [31:0] frame_count=0
);
    reg [23:0] bits;
    integer falls=0;
    realtime t_sync=0,t_rise=0,t_fall=0,t_data=0,t_high=0,t_reset=0,t_clear=0;
    reg seen_fall=0,seen_high=0;
    always @(sdin)begin
        if(rst_n && !sync_n && seen_fall && $realtime-t_fall<12)$fatal(1,"SPI_DATA_HOLD");
        t_data=$realtime;
    end
    always @(negedge sync_n)begin
        if(rst_n)begin
            if(seen_high && $realtime-t_high<48)$fatal(1,"SPI_SYNC_HIGH");
            falls=0;bits=0;t_sync=$realtime;seen_fall=0;
        end
    end
    always @(negedge sclk)if(rst_n && !sync_n)begin
        if($realtime-t_sync<5)$fatal(1,"SPI_SYNC_SETUP");
        if($realtime-t_data<9)$fatal(1,"SPI_DATA_SETUP");
        if(seen_fall && $realtime-t_fall<40)$fatal(1,"SPI_PERIOD_1V8");
        if($realtime-t_rise<15)$fatal(1,"SPI_HIGH_WIDTH");
        t_fall=$realtime;seen_fall=1;bits={bits[22:0],sdin};falls=falls+1;
    end
    always @(posedge sclk)begin
        if(rst_n && !sync_n && seen_fall && $realtime-t_fall<9)$fatal(1,"SPI_LOW_WIDTH");
        t_rise=$realtime;
    end
    always @(posedge sync_n)if(rst_n && falls!=0)begin
        if(falls!=24)$fatal(1,"SPI_FRAME_LENGTH %d",falls);
        if($realtime-t_fall<2)$fatal(1,"SPI_LAST_FALL_HOLD");
        if(bits[23])$fatal(1,"UNEXPECTED_READ");
        last_frame=bits;frame_count=frame_count+1;
        case(bits[22:20])
            1:if(!ldac_n)code=bits[19:0];
            2:begin if(bits[19:10] || bits[0])$fatal(1,"RESERVED_CONTROL");control=bits[19:0];end
            3:clear_code=bits[19:0];
            default:$fatal(1,"UNEXPECTED_DAC_ADDRESS");
        endcase
        t_high=$realtime;seen_high=1;falls=0;
    end
    always @(negedge rst_n)begin code=0;control=14;clear_code=0;falls=0;t_reset=$realtime;seen_fall=0;end
    always @(posedge rst_n)if($realtime-t_reset<35)$fatal(1,"RESET_WIDTH");
    always @(negedge clr_n)begin t_clear=$realtime;if(rst_n)code=clear_code;end
    always @(posedge clr_n)if(t_clear!=0 && $realtime-t_clear<50)$fatal(1,"CLEAR_WIDTH");
endmodule
