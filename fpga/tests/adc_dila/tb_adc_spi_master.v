`timescale 1ns/1ps
module tb_adc_spi_master;
    reg clk=0, rst_n=0, start=0, read_enable=0, sdi=0;
    reg [23:0] tx_word=24'h96a53c;
    wire cs_n,sck,sdo,sdo_enable,busy,done;
    wire [7:0] read_data;
    wire [13:0] legacy_outputs,default_outputs;
    integer cycle=0, rises=0, falls=0, releases=0, last_fall=-100;
    integer cs_high_cycle=-100, bits=0, checked=0;
    reg old_cs=1,old_sck=0,old_done=0;
    reg [23:0] serial_word=0,expected_word;
    reg expected_read;
    reg [7:0] response=8'hb6;
    always #5 clk=~clk;
    adc_spi_master #(.HALF_TICKS(3),.CS_HOLD_TICKS(2)) dut(
        .clk(clk),.rst_n(rst_n),.start(start),.tx_word(tx_word),
        .read_enable(read_enable),.sdi(sdi),.cs_n(cs_n),.sck(sck),
        .sdo(sdo),.sdo_enable(sdo_enable),.busy(busy),.done(done),.read_data(read_data));
    adc_spi_master #(.HALF_TICKS(3)) compatibility(
        .clk(clk),.rst_n(rst_n),.start(start),.tx_word(tx_word),
        .read_enable(read_enable),.sdi(sdi),.cs_n(default_outputs[13]),.sck(default_outputs[12]),
        .sdo(default_outputs[11]),.sdo_enable(default_outputs[10]),.busy(default_outputs[9]),
        .done(default_outputs[8]),.read_data(default_outputs[7:0]));
    adc_spi_master_legacy_reference #(.HALF_TICKS(3)) reference(
        .clk(clk),.rst_n(rst_n),.start(start),.tx_word(tx_word),
        .read_enable(read_enable),.sdi(sdi),.cs_n(legacy_outputs[13]),.sck(legacy_outputs[12]),
        .sdo(legacy_outputs[11]),.sdo_enable(legacy_outputs[10]),.busy(legacy_outputs[9]),
        .done(legacy_outputs[8]),.read_data(legacy_outputs[7:0]));
    always @(negedge clk) begin
        if (bits>=16 && bits<24) sdi=response[23-bits];
        else sdi=0;
    end
    always @(posedge clk) begin
        #1;
        cycle=cycle+1;
        if(default_outputs !== legacy_outputs) $fatal(1,"default legacy waveform mismatch cycle %0d",cycle);
        if(!rst_n) begin
            if({cs_n,sck,busy,done} !== 4'b1000) $fatal(1,"reset outputs");
            old_cs=1;old_sck=0;old_done=0;bits=0;
        end else begin
            if(old_cs && !cs_n) begin
                if(cycle-cs_high_cycle<1) $fatal(1,"missing CS high interval");
                expected_word=tx_word;expected_read=read_enable;serial_word=0;bits=0;
            end
            if(!old_sck && sck) begin
                if(cs_n || !busy || done) $fatal(1,"invalid clock transaction state");
                if(sdo_enable !== !(expected_read && bits>=16)) $fatal(1,"SDIO direction");
                serial_word={serial_word[22:0],sdo};bits=bits+1;rises=rises+1;
            end
            if(old_sck && !sck) begin
                falls=falls+1;
                if(bits==24) last_fall=cycle;
            end
            if(bits==24 && cycle-last_fall<2 && (!busy || cs_n || done))
                $fatal(1,"final SCK hold/completion too early");
            if(!old_cs && cs_n) begin
                if(bits!=24 || cycle-last_fall!=2 || busy || !done || sck)
                    $fatal(1,"CS release/completion timing bits=%0d hold=%0d",bits,cycle-last_fall);
                if(expected_read) begin
                    if(serial_word[23:8]!==expected_word[23:8] || read_data!==response)
                        $fatal(1,"read transaction data actual=%h",read_data);
                end else if(serial_word!==expected_word) $fatal(1,"write serialization");
                cs_high_cycle=cycle;releases=releases+1;checked=checked+1;
            end
            if(done && old_done) $fatal(1,"done longer than one tick");
            if(done && (!cs_n || busy)) $fatal(1,"done before bus released");
            old_cs=cs_n;old_sck=sck;old_done=done;
        end
    end
    task launch;
        input rd;
        begin
            @(negedge clk);read_enable=rd;start=1;
            @(negedge clk);start=0;
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        launch(0);
        repeat(20) @(negedge clk);
        start=1;tx_word=24'h123456; // Busy pulse must not replace active transaction.
        @(negedge clk);start=0;
        wait(done);@(negedge clk);
        launch(1);wait(done);@(negedge clk);
        // Level-held requests exercise adjacent transactions and an idle CS interval.
        read_enable=0;tx_word=24'h56aa81;start=1;
        wait(releases==4);@(negedge clk);start=0;
        repeat(4) @(negedge clk);
        launch(0);wait(dut.finishing);@(negedge clk);rst_n=0;
        repeat(2) @(negedge clk);rst_n=1;
        launch(1);wait(releases==5);@(negedge clk);
        repeat(5) @(negedge clk);
        if(checked!=5) $fatal(1,"missing completed transactions");
        $display("ADC_SPI_MASTER_PASS completed=%0d hold_ticks=2 default_legacy_cycles=%0d reset_during_hold=1",checked,cycle);
        $finish;
    end
    initial begin #100000; $fatal(1,"timeout");end
endmodule
