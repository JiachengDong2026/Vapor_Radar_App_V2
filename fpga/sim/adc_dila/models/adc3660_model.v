`timescale 1ns/1ps
// Pin-level model: independent SPI register decoding and programmable bit mapper.
module adc3660_model(
    input wire rst_n,input wire sample_clk,input wire dclkin,input wire sen,input wire sclk,
    inout wire sdio,input wire stop_dclk,input wire slip,
    output wire dclk,output reg fclk,output reg da5,output reg da6,
    output reg db5,output reg db6,output reg configured,output reg [31:0] sample_count
);
    reg [7:0] regs[0:255];
    reg [23:0] cmd;
    integer spi_bits,i,edge_count;
    reg [15:0] history[0:7];
    reg [2:0] write_ptr;
    reg clock_started=0;
    always @(posedge sample_clk)clock_started=1;
    reg [15:0] current,previous,serial_word;
    reg previous_half;
    integer high_addr,low_addr;
    reg [7:0] high_id,low_id;
    assign #3 dclk=stop_dclk?1'b0:~dclkin;
    assign sdio=1'bz;
    function data_bit;
        input [7:0] id;
        input [15:0] word;
        reg [7:0] stripped;
        integer bit_index;
        begin
            stripped=id&8'h3f;bit_index=-1;
            case(stripped)
                8'h2d:bit_index=15;8'h2c:bit_index=14;8'h27:bit_index=13;8'h26:bit_index=12;
                8'h25:bit_index=11;8'h24:bit_index=10;8'h1f:bit_index=9;8'h1e:bit_index=8;
                8'h1d:bit_index=7;8'h1c:bit_index=6;8'h17:bit_index=5;8'h16:bit_index=4;
                8'h15:bit_index=3;8'h14:bit_index=2;8'h0f:bit_index=1;8'h0e:bit_index=0;
                default:bit_index=-1;
            endcase
            data_bit=bit_index<0?1'bx:word[bit_index];
        end
    endfunction
    initial begin
        cmd=0;spi_bits=0;sample_count=0;write_ptr=0;fclk=0;da5=0;da6=0;db5=0;db6=0;configured=0;
        for(i=0;i<256;i=i+1)regs[i]=0;
        for(i=0;i<8;i=i+1)history[i]=0;
    end
    always @(negedge rst_n)begin configured=0;for(i=0;i<256;i=i+1)regs[i]=0;end
    always @(negedge sen)begin cmd=0;spi_bits=0;end
    always @(posedge sclk)if(!sen)begin cmd={cmd[22:0],sdio};spi_bits=spi_bits+1;end
    always @(posedge sen)if(spi_bits==24)begin
        if(cmd[23:20]!=0)$fatal(1,"ADC3660 unsupported SPI command");
        regs[cmd[15:8]]=cmd[7:0];
        if(regs[8'h07]==8'h4b && regs[8'h13]==0 && regs[8'h1b]==8'h88 && regs[8'h60]==8'h2d && regs[8'h3b]==8'h4e && regs[8'h63]==8'h4a)begin
            if(regs[8'h0a]!=8'h7f || regs[8'h0b]!=8'hee || regs[8'h0c]!=8'hfc || regs[8'h19]!=8'h12 || regs[8'h1f]!=8'h50)
                $fatal(1,"ADC3660 output clock/buffer initialization mismatch");
            configured=1;
        end
    end
    always @(negedge sample_clk)if(clock_started)begin
        history[write_ptr]=16'h8000+sample_count;
        write_ptr=write_ptr+1'b1;sample_count=sample_count+1;
    end
    // At 2-wire 16-bit the first output edge follows the sampling edge by 23ns,
    // and represents the conversion two sampling clocks earlier (datasheet p10/11).
    initial begin
        @(posedge sample_clk);@(negedge sample_clk);#23;
        previous_half=0;edge_count=0;
        forever begin
            if(edge_count==0)begin
                fclk=~fclk;previous_half=fclk;
                serial_word=history[(write_ptr-3)&7];
            end
            high_addr=(previous_half?8'h60:8'h56)-edge_count;
            low_addr=(previous_half?8'h4c:8'h42)-edge_count;
            high_id=regs[high_addr];low_id=regs[low_addr];
            if(configured)begin da5=data_bit(high_id,serial_word);da6=data_bit(low_id,serial_word);end
            else begin da5=0;da6=0;end
            db5=da5;db6=da6;
            if(slip && edge_count==3)fclk=~fclk;
            edge_count=(edge_count+1)%8;
            #10;
        end
    end
endmodule
