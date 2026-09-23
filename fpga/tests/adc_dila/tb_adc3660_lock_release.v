`timescale 1ns/1ps
module tb_adc3660_lock_release;
    reg rst=0,dclk=0,run_clock=1,fclk=0,go=1;
    reg [3:0] edges=0;
    always #10 if(run_clock)dclk=~dclk;
    always @(dclk)if(rst)begin edges=edges+1'b1;fclk=edges[3];end
    wire rx_clk,locked,valid,align;wire [15:0] data;
    adc3660_ddr_rx #(.SIMULATION(1)) dut(.rst_n(rst),.dclk(dclk),.fclk(fclk),.da5(1'b1),.da6(1'b0),.go(go),
        .rx_clk(rx_clk),.clock_locked(locked),.word_valid(valid),.word_data(data),.alignment_toggle(align));
    integer n,words=0;
    always @(posedge rx_clk)if(valid)begin if(data!==16'hff00)$fatal(1,"LOCK_RECOVERY_DATA");words=words+1;end
    task assert_reset;
        begin #1;if(dut.capture_rst_n!==0 || valid!==0 || dut.active!==0 || dut.count!==0 || data!==0)$fatal(1,"LOCK_LOSS_DID_NOT_ASYNC_RESET");end
    endtask
    task assert_release;
        begin
            for(n=0;n<3;n=n+1)begin
                @(posedge rx_clk);#1;
                if(n<2 && dut.capture_rst_n!==0)$fatal(1,"LOCK_RELEASE_EARLY");
                if(valid!==0)$fatal(1,"LOCK_RELEASE_STALE_VALID");
            end
            if(dut.capture_rst_n!==1)$fatal(1,"LOCK_RELEASE_DID_NOT_COMPLETE");
        end
    endtask
    initial begin
        #3;rst=1;wait(words>=3);
        @(negedge rx_clk);#2;force dut.clock_locked=0;assert_reset;
        repeat(4)@(posedge rx_clk);if(valid)$fatal(1,"UNLOCKED_VALID");
        @(negedge rx_clk);#2;release dut.clock_locked;assert_release;wait(words>=6);
        @(negedge dclk);run_clock=0;#7;force dut.clock_locked=0;assert_reset;
        #80;release dut.clock_locked;#80;if(dut.capture_rst_n!==0 || valid!==0)$fatal(1,"RELEASE_WITHOUT_CLOCK");
        run_clock=1;assert_release;wait(words>=9);
        $display("ADC3660_LOCK_RELEASE_PASS async_loss three_edge_release stopped_clock no_stale_word words=%0d",words);$finish;
    end
    initial begin #10000;$fatal(1,"LOCK_RELEASE_TIMEOUT");end
endmodule
