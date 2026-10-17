module cic3_decimator_2x #(
    parameter integer DECIMATION_PAIRS = 125,
    parameter integer INPUT_WIDTH = 16,
    parameter integer ACC_WIDTH = 44,
    parameter integer OUTPUT_WIDTH = 24,
    parameter integer OUTPUT_SHIFT = 16
) (
    input  logic                          clk,
    input  logic                          rst,
    input  logic                          valid_in,
    input  logic signed [INPUT_WIDTH-1:0] i_0,
    input  logic signed [INPUT_WIDTH-1:0] q_0,
    input  logic signed [INPUT_WIDTH-1:0] i_1,
    input  logic signed [INPUT_WIDTH-1:0] q_1,
    output logic                          valid_out,
    output logic signed [OUTPUT_WIDTH-1:0] i_out,
    output logic signed [OUTPUT_WIDTH-1:0] q_out
);
    localparam integer COUNT_WIDTH = $clog2(DECIMATION_PAIRS);
    logic [COUNT_WIDTH-1:0] count;
    logic signed [ACC_WIDTH-1:0] ii1, ii2, ii3, qi1, qi2, qi3;
    logic signed [ACC_WIDTH-1:0] id1, id2, id3, qd1, qd2, qd3;
    logic signed [ACC_WIDTH-1:0] isnap, qsnap, ic1, qc1, ic2, qc2;
    logic snap_valid, c1_valid, c2_valid;

    logic signed [ACC_WIDTH-1:0] xi0, xi1, xq0, xq1;
    logic signed [ACC_WIDTH-1:0] ni1, ni2, ni3, nq1, nq2, nq3;
    always_comb begin
        xi0 = {{(ACC_WIDTH-INPUT_WIDTH){i_0[INPUT_WIDTH-1]}}, i_0};
        xi1 = {{(ACC_WIDTH-INPUT_WIDTH){i_1[INPUT_WIDTH-1]}}, i_1};
        xq0 = {{(ACC_WIDTH-INPUT_WIDTH){q_0[INPUT_WIDTH-1]}}, q_0};
        xq1 = {{(ACC_WIDTH-INPUT_WIDTH){q_1[INPUT_WIDTH-1]}}, q_1};
        // Exact look-ahead form for two sequential input samples.
        ni1 = ii1 + xi0 + xi1;
        ni2 = ii2 + (ii1 <<< 1) + (xi0 <<< 1) + xi1;
        ni3 = ii3 + (ii2 <<< 1) + ii1 + (ii1 <<< 1) +
              xi0 + (xi0 <<< 1) + xi1;
        nq1 = qi1 + xq0 + xq1;
        nq2 = qi2 + (qi1 <<< 1) + (xq0 <<< 1) + xq1;
        nq3 = qi3 + (qi2 <<< 1) + qi1 + (qi1 <<< 1) +
              xq0 + (xq0 <<< 1) + xq1;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            count <= 0;
            ii1 <= 0; ii2 <= 0; ii3 <= 0;
            qi1 <= 0; qi2 <= 0; qi3 <= 0;
            id1 <= 0; id2 <= 0; id3 <= 0;
            qd1 <= 0; qd2 <= 0; qd3 <= 0;
            isnap <= 0; qsnap <= 0; ic1 <= 0; qc1 <= 0; ic2 <= 0; qc2 <= 0;
            snap_valid <= 0; c1_valid <= 0; c2_valid <= 0;
            valid_out <= 0; i_out <= 0; q_out <= 0;
        end else begin
            valid_out <= c2_valid;
            snap_valid <= 0;
            c1_valid <= snap_valid;
            c2_valid <= c1_valid;
            if (snap_valid) begin
                ic1 <= isnap - id1; id1 <= isnap;
                qc1 <= qsnap - qd1; qd1 <= qsnap;
            end
            if (c1_valid) begin
                ic2 <= ic1 - id2; id2 <= ic1;
                qc2 <= qc1 - qd2; qd2 <= qc1;
            end
            if (c2_valid) begin
                i_out <= (ic2 - id3) >>> OUTPUT_SHIFT; id3 <= ic2;
                q_out <= (qc2 - qd3) >>> OUTPUT_SHIFT; qd3 <= qc2;
            end
            if (valid_in) begin
                ii1 <= ni1; ii2 <= ni2; ii3 <= ni3;
                qi1 <= nq1; qi2 <= nq2; qi3 <= nq3;
                if (count == DECIMATION_PAIRS-1) begin
                    count <= 0;
                    isnap <= ni3; qsnap <= nq3;
                    snap_valid <= 1;
                end else begin
                    count <= count + 1'b1;
                end
            end
        end
    end
endmodule
