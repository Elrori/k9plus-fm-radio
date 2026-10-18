`timescale 1ns/1ps
// Exercise both discriminator modes with a real-valued complex IF oscillator.
// A constant 10-kHz offset must produce exactly the same Q28 frequency estimate
// regardless of whether the complex correlation spans 1 or 2 IF samples.
module tb_fm_discriminator_lag;
    logic clk = 0;
    always #4.166667 clk = ~clk; // 120-MHz fabric clock
    logic rst = 1, valid_in = 0;
    logic signed [23:0] i_in = 0, q_in = 0;
    wire v1, v2, v_legacy;
    wire signed [31:0] p1, p2, p_legacy;
    logic signed [63:0] sum1 = 0, sum2 = 0;
    integer count1 = 0, count2 = 0;
    real phase, expected, mean1, mean2, difference1, difference2, allowed;

    fm_discriminator #(.CORR_LAG(1)) ref_dut (
        .clk(clk), .rst(rst), .valid_in(valid_in), .i_in(i_in), .q_in(q_in),
        .valid_out(v1), .phase_q28(p1));
    fm_discriminator_legacy golden (
        .clk(clk), .rst(rst), .valid_in(valid_in), .i_in(i_in), .q_in(q_in),
        .valid_out(v_legacy), .phase_q28(p_legacy));
    fm_discriminator #(.CORR_LAG(2)) lag2_dut (
        .clk(clk), .rst(rst), .valid_in(valid_in), .i_in(i_in), .q_in(q_in),
        .valid_out(v2), .phase_q28(p2));

    always @(posedge clk) begin
        if (!rst && (v1 !== v_legacy || (v1 && p1 !== p_legacy)))
            $fatal(1, "lag1 diverged from frozen original RTL");
        if (rst) begin
            sum1 <= 0; sum2 <= 0; count1 <= 0; count2 <= 0;
        end else begin
            if (v1) begin
                if (count1 >= 10) sum1 <= sum1 + $signed(p1);
                count1 <= count1 + 1;
            end
            if (v2) begin
                if (count2 >= 10) sum2 <= sum2 + $signed(p2);
                count2 <= count2 + 1;
            end
        end
    end

    task automatic run_case(input integer hz);
        begin
            rst = 1;
            valid_in = 0; i_in = 0; q_in = 0;
            repeat (10) @(negedge clk);
            rst = 0;
            for (integer n = 0; n < 2500; n = n + 1) begin
                @(negedge clk);
                phase = 6.283185307179586 * hz * n / 960000.0;
                i_in = $rtoi(200000.0 * $cos(phase));
                q_in = $rtoi(200000.0 * $sin(phase));
                valid_in = 1;
                @(negedge clk);
                valid_in = 0;
                repeat (123) @(negedge clk);
            end
            repeat (2000) @(negedge clk); // flush 48-kS/s CIC and CORDIC
            if (count1 < 90 || count2 < 90)
                $fatal(1, "missing samples ref=%0d lag2=%0d", count1, count2);
            expected = (6.283185307179586 * hz / 960000.0) * 268435456.0;
            mean1 = 1.0 * sum1 / (count1 - 10);
            mean2 = 1.0 * sum2 / (count2 - 10);
            difference1 = mean1 - expected;
            difference2 = mean2 - expected;
            allowed = (hz < 0 ? -hz : hz) * 6.283185307179586
                      / 960000.0 * 268435456.0 * 0.03 + 15000.0;
            $display("LAG_CASE hz=%0d ref=%f lag2=%f expected=%f",
                      hz, mean1, mean2, expected);
            if (difference1 > allowed || difference1 < -allowed ||
                difference2 > allowed || difference2 < -allowed)
                $fatal(1, "frequency estimate beyond 3 percent for hz=%0d", hz);
        end
    endtask

    initial begin
        run_case(10000);
        run_case(-15000);
        $display("LAG_RTL_PASS");
        $display("LAG1_BIT_EXACT_BASELINE_PASS");
        $finish;
    end
endmodule
