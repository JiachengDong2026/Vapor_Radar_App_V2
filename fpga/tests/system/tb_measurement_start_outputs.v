`timescale 1ns/1ps
module tb_measurement_start_outputs;
    reg clk=0,rst_n=0;
    reg [2:0] start_event=0;
    wire [2:0] start_pulse;
    integer tick=0,k;
    integer raised[0:2],width[0:2],rises[0:2],falls[0:2];
    reg [2:0] previous=0;
    measurement_start_outputs dut(.clk(clk),.rst_n(rst_n),
        .start_event(start_event),.start_pulse(start_pulse));
    always #5 clk=~clk;
    always @(posedge clk)begin
        tick=tick+1;
        #1;
        if(rst_n)begin
            for(k=0;k<3;k=k+1)begin
                if(start_pulse[k] && !previous[k])begin
                    if(!start_event[k])$fatal(1,"Observation rose without a source event");
                    raised[k]=tick;rises[k]=rises[k]+1;
                end
                if(!start_pulse[k] && previous[k])begin
                    width[k]=tick-raised[k];falls[k]=falls[k]+1;
                    if(width[k]!=1000)$fatal(1,"Pulse width %d: %d clocks",k,width[k]);
                end
            end
        end
        previous=start_pulse;
    end
    initial begin
        for(k=0;k<3;k=k+1)begin raised[k]=0;width[k]=0;rises[k]=0;falls[k]=0;end
        repeat(3)@(negedge clk);rst_n=1;
        @(negedge clk);start_event=3'b001;
        @(negedge clk);start_event=0;
        repeat(10)@(negedge clk);start_event=3'b110;
        @(negedge clk);start_event=0;
        // A duplicate while high neither queues a new edge nor stretches width.
        repeat(40)@(negedge clk);start_event=3'b111;
        @(negedge clk);start_event=0;
        repeat(1100)@(negedge clk);
        for(k=0;k<3;k=k+1)if(rises[k]!=1 || falls[k]!=1)$fatal(1,"Duplicate or missing pulse");
        start_event=7;@(negedge clk);start_event=0;
        repeat(5)@(negedge clk);rst_n=0;
        #1;if(start_pulse!=0)$fatal(1,"Reset did not clear outputs immediately");
        repeat(3)@(negedge clk);rst_n=1;
        repeat(5)@(negedge clk);if(start_pulse!=0)$fatal(1,"Stale pulse after reset");
        start_event=7;@(negedge clk);start_event=0;
        repeat(1005)@(negedge clk);
        for(k=0;k<3;k=k+1)if(rises[k]!=3 || falls[k]!=2)$fatal(1,"Rearming after reset failed");
        $display("MEASUREMENT_START_OUTPUTS_PASS exact_10us_independent_edges_no_retrigger_reset_rearm");$finish;
    end
    initial begin #100000;$fatal(1,"Observation test timeout");end
endmodule
