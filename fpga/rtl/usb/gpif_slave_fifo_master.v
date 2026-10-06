`default_nettype none
// AN65974 synchronous 32-bit slave FIFO. All controls/data launch on PCLK.
// Dedicated thread flags: HIGH means ready / above the programmed watermark.
// With watermark=12 the write margin is eight words. A final word commits its
// DMA buffer with PKTEND in the SAME bus cycle as SLWR (no separate ZLP).
module gpif_slave_fifo_master #(
    parameter integer MAX_TX_BURST=64,
    parameter integer MAX_RX_BURST=16
)(
    input wire gpif_clk,rst_gpif_n,
    input wire tx_valid,
    output wire tx_ready,
    input wire [31:0] tx_data,
    input wire tx_last,
    output reg rx_valid,
    input wire rx_ready,
    output reg [31:0] rx_data,
    input wire [31:0] rx_free,
    input wire flag_tx_ready,flag_rx_ready,flag_tx_partial,flag_rx_partial,
    input wire [31:0] dq_in,
    output reg [31:0] dq_out,
    output reg dq_oe,
    output reg slcs_n,slwr_n,slrd_n,sloe_n,pktend_n,
    output reg [1:0] fifo_addr,
    output reg [31:0] tx_word_count,rx_word_count,tx_frame_count,error_count,stall_count,
    output wire idle
);
    localparam IDLE=0,TX_SETUP=1,TX=2,TURN_RX=3,RX_SETUP=4,RX=5,
               RX_WAIT=6,RX_RECOVER=7,TURN_TX=8,TX_FINISH=9;
    reg [3:0] state;
    reg [3:0] wait_count;
    reg [15:0] burst_count;
    reg [3:0] cooldown;
    (* IOB="TRUE" *) reg tx_room,rx_present,tx_margin,rx_margin;
    wire can_write=state==TX && tx_room && (tx_margin || cooldown==0);
    assign tx_ready=can_write;
    assign idle=state==IDLE && !rx_valid && slwr_n && slrd_n;
    always @(posedge gpif_clk or negedge rst_gpif_n) begin
        if(!rst_gpif_n) begin
            tx_room<=0;rx_present<=0;tx_margin<=0;rx_margin<=0;
        end else begin
            tx_room<=flag_tx_ready;rx_present<=flag_rx_ready;
            tx_margin<=flag_tx_partial;rx_margin<=flag_rx_partial;
        end
    end
    always @(posedge gpif_clk or negedge rst_gpif_n) begin
        if(!rst_gpif_n) begin
            state<=IDLE;wait_count<=0;burst_count<=0;cooldown<=0;
            rx_valid<=0;rx_data<=0;dq_out<=0;dq_oe<=0;
            slcs_n<=1;slwr_n<=1;slrd_n<=1;sloe_n<=1;pktend_n<=1;fifo_addr<=0;
            tx_word_count<=0;rx_word_count<=0;tx_frame_count<=0;error_count<=0;stall_count<=0;
        end else begin
            slcs_n<=0;slwr_n<=1;slrd_n<=1;pktend_n<=1;
            if(tx_valid && !tx_ready) stall_count<=stall_count+1'b1;
            if(rx_valid && rx_ready) rx_valid<=0;
            if(cooldown!=0) cooldown<=cooldown-1'b1;
            // Count strobes sampled by FX3 at this edge, not prefetched words.
            if(!slcs_n && !slwr_n) begin
                tx_word_count<=tx_word_count+1'b1;
                if(!pktend_n) tx_frame_count<=tx_frame_count+1'b1;
            end
            if(!slcs_n && !slrd_n) rx_word_count<=rx_word_count+1'b1;
            case(state)
                IDLE: begin
                    dq_oe<=0;sloe_n<=1;burst_count<=0;
                    if(tx_valid && tx_room) begin
                        fifo_addr<=0;dq_oe<=1;wait_count<=3;state<=TX_SETUP;
                    end else if(rx_present && rx_free>=2 && !rx_valid) begin
                        fifo_addr<=3;wait_count<=3;state<=RX_SETUP;
                    end
                end
                TX_SETUP: begin
                    if(wait_count!=0) wait_count<=wait_count-1'b1;
                    else begin state<=TX;burst_count<=0;end
                end
                TX: begin
                    if(can_write && tx_valid) begin
                        dq_out<=tx_data;slwr_n<=0;pktend_n<=!tx_last;
                        cooldown<=6;burst_count<=burst_count+1'b1;
                        if(tx_last || burst_count==MAX_TX_BURST-1) begin
                            // One extra state keeps DQ driven through the edge
                            // at which FX3 consumes the last launched word.
                            state<=TX_FINISH;wait_count<=6;
                        end
                    end else if(!tx_valid || (!tx_room && cooldown==0)) begin
                        state<=TX_FINISH;wait_count<=1;
                    end
                end
                TX_FINISH: begin
                    if(wait_count!=0) wait_count<=wait_count-1'b1;
                    else begin dq_oe<=0;sloe_n<=1;wait_count<=2;state<=TURN_RX;end
                end
                TURN_RX: begin
                    if(wait_count!=0) wait_count<=wait_count-1'b1;
                    else if(rx_present && rx_free>=2 && !rx_valid) begin
                        fifo_addr<=3;wait_count<=3;state<=RX_SETUP;
                    end else state<=IDLE;
                end
                RX_SETUP: begin
                    sloe_n<=0;
                    if(wait_count!=0) wait_count<=wait_count-1'b1;
                    else begin state<=RX;burst_count<=0;end
                end
                RX: begin
                    if(rx_present && rx_free>=2 && !rx_valid) begin
                        slrd_n<=0;wait_count<=3;state<=RX_WAIT;
                        burst_count<=burst_count+1'b1;
                    end else begin sloe_n<=1;wait_count<=2;state<=TURN_TX;end
                end
                RX_WAIT: begin
                    // Launched at L; FX3 samples at L+1 and changes DQ after
                    // L+3. Capture at L+4 leaves the entire tCO budget.
                    if(wait_count!=0) wait_count<=wait_count-1'b1;
                    else begin
                        if(rx_valid && !rx_ready) error_count<=error_count+1'b1;
                        else begin rx_data<=dq_in;rx_valid<=1;end
                        wait_count<=2;state<=RX_RECOVER;
                    end
                end
                RX_RECOVER: begin
                    if(wait_count!=0) wait_count<=wait_count-1'b1;
                    else if(burst_count<MAX_RX_BURST && rx_present && !tx_valid)
                        state<=RX;
                    else begin sloe_n<=1;wait_count<=2;state<=TURN_TX;end
                end
                TURN_TX: begin
                    if(wait_count!=0) wait_count<=wait_count-1'b1;
                    else state<=IDLE;
                end
                default: begin state<=IDLE;dq_oe<=0;sloe_n<=1;error_count<=error_count+1'b1;end
            endcase
        end
    end
endmodule
`default_nettype wire
