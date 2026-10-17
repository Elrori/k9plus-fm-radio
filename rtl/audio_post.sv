module audio_post (
    input  logic                    clk,
    input  logic                    rst,
    input  logic                    valid_in,
    input  logic signed [31:0]      sample_in,
    input  logic                    mute,
    output logic                    valid_out,
    output logic signed [15:0]      pcm_out,
    output logic                    clipped
);
    // Multiplier-free weak-signal audio conditioning.  The DC tracker forms an
    // approximately 60 Hz high-pass, rejecting the measured 50/60 Hz hum and
    // very-low-frequency discriminator wander without harming speech clarity.
    // 50 us de-emphasis beta is approximated by 1/4+1/16+1/64=0.328125.
    logic signed [39:0] dc_state, deemph_state;
    logic signed [39:0] hp_pipe, deemph_delta_pipe;
    logic signed [39:0] correction_a_pipe, correction_b_pipe;
    logic stage1, stage2, stage3;
    logic mute1, mute2, mute3;
    logic signed [39:0] x_ext, dc_delta, hp_now, deemph_next;

    function automatic signed [15:0] sat16(input signed [39:0] value);
        reg signed [39:0] scaled;
        begin
            scaled = value >>> 12;
            if (scaled > 32767) sat16 = 16'sh7fff;
            else if (scaled < -32768) sat16 = 16'sh8000;
            else sat16 = scaled[15:0];
        end
    endfunction

    always_comb begin
        x_ext = {{8{sample_in[31]}}, sample_in};
        dc_delta = x_ext - dc_state;
        hp_now = x_ext - (dc_state + (dc_delta >>> 7));
        deemph_next = deemph_state + correction_a_pipe + correction_b_pipe;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            dc_state <= 0; deemph_state <= 0;
            hp_pipe <= 0; deemph_delta_pipe <= 0;
            correction_a_pipe <= 0; correction_b_pipe <= 0;
            stage1 <= 0; stage2 <= 0; stage3 <= 0;
            mute1 <= 0; mute2 <= 0; mute3 <= 0;
            valid_out <= 0; pcm_out <= 0; clipped <= 0;
        end else begin
            valid_out <= stage3;
            stage1 <= valid_in;
            stage2 <= stage1;
            stage3 <= stage2;
            mute1 <= mute; mute2 <= mute1; mute3 <= mute2;

            if (valid_in) begin
                dc_state <= dc_state + (dc_delta >>> 7);
                hp_pipe <= hp_now;
            end
            if (stage1)
                deemph_delta_pipe <= hp_pipe - deemph_state;
            if (stage2) begin
                correction_a_pipe <= (deemph_delta_pipe >>> 2) +
                                     (deemph_delta_pipe >>> 4);
                correction_b_pipe <= deemph_delta_pipe >>> 6;
            end
            if (stage3) begin
                deemph_state <= deemph_next;
                pcm_out <= mute3 ? 16'sd0 : sat16(deemph_next);
                clipped <= !mute3 && ((deemph_next >>> 12) > 32767 ||
                                      (deemph_next >>> 12) < -32768);
            end
        end
    end
endmodule
