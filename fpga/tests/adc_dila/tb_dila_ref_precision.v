`timescale 1ns/1ps
module tb_dila_ref_precision;
    reg [31:0] phase = 0;
    reg [31:0] phase_1f = 0;
    reg [31:0] phase_2f_correction = 0;
    wire signed [17:0] sin_1f, cos_1f, sin_2f, cos_2f;
    dila_ref_gen dut(.phase(phase), .phase_1f(phase_1f),
        .phase_2f_correction(phase_2f_correction), .sin_1f(sin_1f),
        .cos_1f(cos_1f), .sin_2f(sin_2f), .cos_2f(cos_2f));
    `include "dila_sine_lut.vh"
    integer cell_index, sub_index, n, k, c, checks = 0;
    integer sum0, sum1, sum2, sum3, oldsum0, oldsum1;
    integer saved_sin, saved_cos;
    reg [31:0] angle1, angle2, quarter1, quarter2, offset, nominal;
    reg [63:0] nominal_wide;
    real ideal, error, max_error = 0.0, sq_error = 0.0;
    real mean, max_mean = 0.0, oldmean, max_oldmean = 0.0;
    real pi = 3.14159265358979323846;

    task check_value;
        input signed [17:0] actual;
        input [31:0] angle;
        begin
            ideal = 131071.0 * $sin(2.0*pi*angle/4294967296.0);
            error = actual - ideal;
            sq_error = sq_error + error*error;
            if(error < 0.0) error = -error;
            if(error > max_error) max_error = error;
            if(error > 2.0 || (^actual) === 1'bx)
                $fatal(1, "Reference error angle=%h got=%0d ideal=%f error=%f", angle, actual, ideal, error);
            checks = checks + 1;
        end
    endtask

    task check_outputs;
        begin
            angle1 = phase + phase_1f;
            angle2 = (phase << 1) + phase_2f_correction;
            quarter1 = angle1 + 32'h40000000;
            quarter2 = angle2 + 32'h40000000;
            check_value(sin_1f, angle1);
            check_value(cos_1f, quarter1);
            check_value(sin_2f, angle2);
            check_value(cos_2f, quarter2);
        end
    endtask

    initial begin
        // Every LUT cell, 256 fractional positions, alternating ignored-bit
        // extremes. Non-grid corrections exercise carry and phase wrapping.
        phase_1f = 32'hb2c76543;
        phase_2f_correction = 32'h7f19fedc;
        for(cell_index=0; cell_index<1024; cell_index=cell_index+1)
            for(sub_index=0; sub_index<256; sub_index=sub_index+1) begin
                phase = (cell_index << 22) | (sub_index << 14) |
                    ((sub_index & 1) ? 32'd1023 : 32'd0);
                #1; check_outputs;
            end
        phase_1f = 0;
        phase_2f_correction = 0;
        // Exact grid nodes, all quadrant boundaries, and wrap on both sides.
        for(cell_index=0; cell_index<1024; cell_index=cell_index+1) begin
            phase = cell_index << 22;
            #1;
            if(sin_1f !== sine_lut(cell_index))
                $fatal(1, "Grid node changed index=%0d", cell_index);
            check_outputs;
        end
        for(k=0; k<4; k=k+1)
            for(n=-2049; n<=2049; n=n+1) begin
                phase = (k << 30) + n;
                #1; check_outputs;
            end
        // Half-wave odd symmetry is exact, including negative rounding ties.
        for(n=0; n<4096; n=n+1) begin
            phase = n*32'd1048573;
            #1; saved_sin=sin_1f; saved_cos=cos_1f;
            phase = phase + 32'h80000000;
            #1;
            if(sin_1f !== -saved_sin || cos_1f !== -saved_cos)
                $fatal(1, "Half-wave symmetry error phase=%h", phase);
        end
        // 25 updates/cycle at 20 kHz / 500 kHz. Check exact rational phase
        // points and the implemented rounded DDS increment (171798692).
        // Sweep 257 initial sub-cell phases; 2f also samples a full cycle.
        for(c=0; c<2; c=c+1)
            for(k=0; k<=256; k=k+1) begin
                offset = k*32'd16383;
                sum0=0; sum1=0; sum2=0; sum3=0; oldsum0=0; oldsum1=0;
                for(n=0; n<25; n=n+1) begin
                    nominal_wide = n;
                    nominal_wide = (nominal_wide << 32)/25;
                    nominal = c ? n*32'd171798692 : nominal_wide[31:0];
                    phase = offset + nominal;
                    #1; check_outputs;
                    sum0=sum0+sin_1f; sum1=sum1+cos_1f;
                    sum2=sum2+sin_2f; sum3=sum3+cos_2f;
                    angle1=phase; quarter1=phase+32'h40000000;
                    oldsum0=oldsum0+sine_lut(angle1[31:22]);
                    oldsum1=oldsum1+sine_lut(quarter1[31:22]);
                end
                for(n=0; n<4; n=n+1) begin
                    case(n)
                        0: mean=sum0/25.0;
                        1: mean=sum1/25.0;
                        2: mean=sum2/25.0;
                        3: mean=sum3/25.0;
                    endcase
                    if(mean < 0.0) mean=-mean;
                    if(mean > max_mean) max_mean=mean;
                    if(mean > 0.5)
                        $fatal(1, "Reference DC leakage mode=%0d offset=%h channel=%0d mean=%f",c,offset,n,mean);
                end
                oldmean=oldsum0/25.0;
                if(oldmean<0.0) oldmean=-oldmean;
                if(oldmean>max_oldmean) max_oldmean=oldmean;
                oldmean=oldsum1/25.0;
                if(oldmean<0.0) oldmean=-oldmean;
                if(oldmean>max_oldmean) max_oldmean=oldmean;
            end
        $display("DILA_REF_PRECISION_PASS checks=%0d max_error_lsb=%f rms_error_lsb=%f max_25point_mean_lsb=%f old_max_25point_mean_lsb=%f",checks,max_error,$sqrt(sq_error/checks),max_mean,max_oldmean);
        $finish;
    end
    initial begin #2000000; $fatal(1, "Reference precision watchdog"); end
endmodule
