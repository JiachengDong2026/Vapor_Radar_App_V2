`default_nettype none
// Discipline a 100 Hz saw DDS. One PPS observation changes only the positive
// phase increment. The sample clock, carrier and running phase never jump.
module wms_pps_discipline #(parameter integer SYS_CLK_HZ=100000000)(
    input wire clk,rst_n,tracking,accept,
    input wire [31:0] tick,seq,phase,period,nominal,
    output wire [31:0] step
);
    reg have_edge,valid_step;
    reg [31:0] previous_tick,previous_seq,corrected,span,period_latched;
    wire [31:0] interval_ticks=tick-previous_tick;
    reg [38:0] turns;
    reg [63:0] product,numerator;
    reg [2:0] stage;
    wire busy,done;
    wire [63:0] quotient;
    // Limit catch-up to a quarter of one scan per second (0.25% at 100 Hz).
    // The phase register represents the last issued sample. Target a wrap
    // just after the edge so quantising to the sample grid does not move
    // it between adjacent UTC seconds on successive observations.
    wire [31:0] guard_phase=nominal>32'h08000000 ? 32'h10000000 : nominal<<1;
    wire signed [31:0] phase_error=$signed(phase + guard_phase);
    wire signed [31:0] limited_error=phase_error>32'sh40000000 ? 32'sh40000000 :
        phase_error < -32'sh40000000 ? -32'sh40000000 : phase_error;
    assign step=valid_step ? corrected : nominal;
    wms_unsigned_divider #(.W(64)) ratio(.clk(clk),.rst_n(rst_n && tracking),
        .start(stage==3),.numerator(numerator),.denominator({32'd0,span}),
        .busy(busy),.done(done),.quotient(quotient),.remainder());
    always @(posedge clk)begin
        if(!rst_n || (!tracking && !accept))begin
            have_edge<=0;valid_step<=0;stage<=0;
        end else begin
            if(accept)begin
                previous_tick<=tick;previous_seq<=seq;have_edge<=1;
                if(tracking && have_edge && seq==previous_seq+1'b1 &&
                   interval_ticks>=SYS_CLK_HZ-SYS_CLK_HZ/100 &&
                   interval_ticks<=SYS_CLK_HZ+SYS_CLK_HZ/100 && !busy && stage==0)begin
                    span<=interval_ticks;period_latched<=period;
                    turns<={7'd100,32'd0}-{{7{limited_error[31]}},limited_error};
                    stage<=1;
                end
            end
            case(stage)
                1:begin product<=turns*period_latched;stage<=2;end
                2:begin numerator<=product+{1'b0,span[31:1]};stage<=3;end
                3:stage<=0;
                default:begin end
            endcase
            if(done)begin
                corrected<=quotient==0 ? 32'd1 : quotient>64'h80000000 ? 32'h80000000 : quotient[31:0];
                valid_step<=1;
            end
        end
    end
endmodule
`default_nettype wire
