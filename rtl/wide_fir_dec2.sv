// 12 MS/s -> 6 MS/s symmetric FIR. Coefficients include CIC /20 droop
// compensation. Full-rate clock is 120 MHz; one input arrives every 10 clocks.
module wide_fir_dec2 (
    input logic clk, rst, valid_in,
    input logic signed [23:0] i_in, q_in,
    output logic valid_out,
    output logic signed [23:0] i_out, q_out
);
    logic signed [23:0] hi [0:61], hq [0:61];
    `include "mem/wide_coeffs.vh"
    logic signed [24:0] pair_i [0:31], pair_q [0:31];
    (* use_dsp = "yes" *) logic signed [42:0] pi [0:31], pq [0:31];
    logic signed [47:0] si [0:4][0:31], sq [0:4][0:31];
    logic phase;
    logic [6:0] valid_pipe;
    integer j, level;

    function automatic signed [23:0] rounded_sat(input signed [47:0] x);
        reg signed [48:0] y;
        begin
            y = ($signed({x[47],x}) + 49'sd32768) >>> 16;
            if (y > 8388607) rounded_sat = 24'sh7fffff;
            else if (y < -8388608) rounded_sat = 24'sh800000;
            else rounded_sat = y[23:0];
        end
    endfunction

    always_comb begin
        pair_i[0] = {i_in[23],i_in} + {hi[61][23],hi[61]};
        pair_q[0] = {q_in[23],q_in} + {hq[61][23],hq[61]};
        for (integer k=1; k<31; k=k+1) begin
            pair_i[k] = {hi[k-1][23],hi[k-1]} + {hi[61-k][23],hi[61-k]};
            pair_q[k] = {hq[k-1][23],hq[k-1]} + {hq[61-k][23],hq[61-k]};
        end
        pair_i[31] = {hi[30][23],hi[30]};
        pair_q[31] = {hq[30][23],hq[30]};
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            phase <= 0; valid_pipe <= 0; valid_out <= 0;
            i_out <= 0; q_out <= 0;
            for (j=0; j<62; j=j+1) begin hi[j]<=0; hq[j]<=0; end
        end else begin
            valid_pipe <= {valid_pipe[5:0],valid_in && phase};
            valid_out <= valid_pipe[6];
            if (valid_in) begin
                phase <= !phase;
                hi[0] <= i_in; hq[0] <= q_in;
                for (j=1; j<62; j=j+1) begin hi[j]<=hi[j-1]; hq[j]<=hq[j-1]; end
                if (phase) begin
                    for (j=0; j<32; j=j+1) begin
                        pi[j] <= pair_i[j] * wide_coeff(j);
                        pq[j] <= pair_q[j] * wide_coeff(j);
                    end
                end
            end
            if (valid_pipe[0]) begin
                for (j=0; j<16; j=j+1) begin
                    si[0][j] <= $signed(pi[2*j]) + $signed(pi[2*j+1]);
                    sq[0][j] <= $signed(pq[2*j]) + $signed(pq[2*j+1]);
                end
            end
            for (level=1; level<5; level=level+1) begin
                if (valid_pipe[level]) begin
                    for (j=0; j<(16 >> level); j=j+1) begin
                        si[level][j] <= si[level-1][2*j] + si[level-1][2*j+1];
                        sq[level][j] <= sq[level-1][2*j] + sq[level-1][2*j+1];
                    end
                end
            end
            // One extra register stage aligns the rounded output with valid.
            if (valid_pipe[5]) begin
                i_out <= rounded_sat(si[4][0]);
                q_out <= rounded_sat(sq[4][0]);
            end
        end
    end
endmodule
