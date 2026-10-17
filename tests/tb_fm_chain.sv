`timescale 1ns/1ps

module tb_fm_chain;
    localparam real RF_SAMPLE_RATE = 240000000.0;
    localparam real CARRIER_HZ = 100100000.0;
    localparam real AUDIO_HZ = 1000.0;
    localparam real DEVIATION_HZ = 75000.0;
    localparam integer RF_CLOCK_CYCLES = 1440000; // 12 ms at 120 MHz

    logic clk = 0;
    logic rst = 1;
    logic rf_bit_0 = 0, rf_bit_1 = 0;
    integer pair_index = 0;
    integer pcm_file;
    integer pcm_count = 0;

    logic mix_valid;
    logic signed [15:0] mix_i0, mix_q0, mix_i1, mix_q1;
    logic channel_valid;
    logic signed [23:0] channel_i, channel_q;
    logic filter_valid;
    logic signed [23:0] filter_i, filter_q;
    logic discriminator_valid;
    logic signed [31:0] phase_q28;
    logic pcm_valid;
    logic signed [15:0] pcm;
    logic clipped;

    always #4.166666 clk = ~clk;

    function automatic logic sampled_fm(input integer sample_number);
        real t;
        real angle;
        begin
            t = sample_number / RF_SAMPLE_RATE;
            angle = 6.283185307179586 * CARRIER_HZ * t
                  + (DEVIATION_HZ / AUDIO_HZ)
                  * $sin(6.283185307179586 * AUDIO_HZ * t);
            sampled_fm = ($sin(angle) >= 0.0);
        end
    endfunction

    nco_mixer_2x mixer (
        .clk(clk), .rst(rst), .valid_in(1'b1),
        .rf_bit_0(rf_bit_0), .rf_bit_1(rf_bit_1),
        .phase_increment(32'd1791359276),
        .valid_out(mix_valid), .i_0(mix_i0), .q_0(mix_q0),
        .i_1(mix_i1), .q_1(mix_q1)
    );

    cic3_decimator_2x rf_decimator (
        .clk(clk), .rst(rst), .valid_in(mix_valid),
        .i_0(mix_i0), .q_0(mix_q0), .i_1(mix_i1), .q_1(mix_q1),
        .valid_out(channel_valid), .i_out(channel_i), .q_out(channel_q)
    );

    complex_fir channel_filter (
        .clk(clk), .rst(rst), .valid_in(channel_valid),
        .i_in(channel_i), .q_in(channel_q),
        .valid_out(filter_valid), .i_out(filter_i), .q_out(filter_q)
    );

    fm_discriminator discriminator (
        .clk(clk), .rst(rst), .valid_in(filter_valid),
        .i_in(filter_i), .q_in(filter_q),
        .valid_out(discriminator_valid), .phase_q28(phase_q28)
    );

    audio_post postprocess (
        .clk(clk), .rst(rst), .valid_in(discriminator_valid),
        .sample_in(phase_q28), .mute(1'b0),
        .valid_out(pcm_valid), .pcm_out(pcm), .clipped(clipped)
    );

    always @(negedge clk) begin
        if (!rst) begin
            rf_bit_0 <= sampled_fm(pair_index * 2);
            rf_bit_1 <= sampled_fm(pair_index * 2 + 1);
            pair_index <= pair_index + 1;
        end
    end

    always @(posedge clk) begin
        if (pcm_valid) begin
            $fdisplay(pcm_file, "%0d", pcm);
            pcm_count <= pcm_count + 1;
        end
    end

    initial begin
        pcm_file = $fopen("pcm.txt", "w");
        if (!pcm_file) $fatal(1, "cannot open PCM output");
        repeat (20) @(posedge clk);
        rst <= 0;
        repeat (RF_CLOCK_CYCLES) @(posedge clk);
        repeat (500) @(posedge clk);
        $fclose(pcm_file);
        $display("FM_CHAIN_DONE samples=%0d", pcm_count);
        if (pcm_count < 500) $fatal(1, "too few PCM samples");
        $finish;
    end
endmodule
