module fm_discriminator #(
    parameter integer DECIMATION = 20
) (
    input  logic                    clk,
    input  logic                    rst,
    input  logic                    valid_in,
    input  logic signed [23:0]      i_in,
    input  logic signed [23:0]      q_in,
    output logic                    valid_out,
    output logic signed [31:0]      phase_q28
);
    // Form the conjugate product at 960 kS/s, low-pass/decimate its Cartesian
    // components, and only then perform atan2. Filtering before the nonlinear
    // operation prevents much of the weak-signal threshold noise from becoming
    // irreversible phase impulses.
    logic have_previous, product_pending, busy;
    logic signed [23:0] i_previous, q_previous;
    logic signed [47:0] product_ii, product_qq, product_iq, product_qi;
    logic corr_valid;
    logic signed [48:0] corr_dot, corr_cross;

    wire filtered_dot_valid, filtered_cross_valid;
    wire signed [54:0] filtered_dot, filtered_cross;
    cic3_decimator #(
        .DECIMATION(DECIMATION), .INPUT_WIDTH(49), .ACC_WIDTH(72),
        .OUTPUT_WIDTH(55), .OUTPUT_SHIFT(8)
    ) dot_filter (
        .clk, .rst, .valid_in(corr_valid), .sample_in(corr_dot),
        .valid_out(filtered_dot_valid), .sample_out(filtered_dot)
    );
    cic3_decimator #(
        .DECIMATION(DECIMATION), .INPUT_WIDTH(49), .ACC_WIDTH(72),
        .OUTPUT_WIDTH(55), .OUTPUT_SHIFT(8)
    ) cross_filter (
        .clk, .rst, .valid_in(corr_valid), .sample_in(corr_cross),
        .valid_out(filtered_cross_valid), .sample_out(filtered_cross)
    );

    logic signed [54:0] x, y, next_x, next_y;
    logic signed [33:0] z, next_z;
    logic signed [31:0] angle [0:17];
    logic [4:0] iteration;
    localparam logic signed [33:0] PI_Q28 = 34'sd843314857;

    initial begin
        angle[0]=32'sd210828714; angle[1]=32'sd124459457; angle[2]=32'sd65760959;
        angle[3]=32'sd33381290; angle[4]=32'sd16755422; angle[5]=32'sd8385879;
        angle[6]=32'sd4193963; angle[7]=32'sd2097109; angle[8]=32'sd1048571;
        angle[9]=32'sd524287; angle[10]=32'sd262144; angle[11]=32'sd131072;
        angle[12]=32'sd65536; angle[13]=32'sd32768; angle[14]=32'sd16384;
        angle[15]=32'sd8192; angle[16]=32'sd4096; angle[17]=32'sd2048;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            have_previous <= 0; product_pending <= 0; corr_valid <= 0; busy <= 0;
            valid_out <= 0; phase_q28 <= 0; i_previous <= 0; q_previous <= 0;
            product_ii <= 0; product_qq <= 0; product_iq <= 0; product_qi <= 0;
            corr_dot <= 0; corr_cross <= 0;
            x <= 0; y <= 0; z <= 0; iteration <= 0;
        end else begin
            valid_out <= 0;
            corr_valid <= 0;

            if (valid_in) begin
                // synthesis translate_off
                if (product_pending) $fatal(1, "FM discriminator product overrun");
                // synthesis translate_on
                if (have_previous) begin
                    product_ii <= i_previous * i_in;
                    product_qq <= q_previous * q_in;
                    product_iq <= i_previous * q_in;
                    product_qi <= q_previous * i_in;
                    product_pending <= 1;
                end
                i_previous <= i_in;
                q_previous <= q_in;
                have_previous <= 1;
            end else if (product_pending) begin
                corr_dot <= product_ii + product_qq;
                corr_cross <= product_iq - product_qi;
                corr_valid <= 1;
                product_pending <= 0;
            end

            if (filtered_dot_valid) begin
                // synthesis translate_off
                if (!filtered_cross_valid || busy)
                    $fatal(1, "FM discriminator filtered-input overrun");
                // synthesis translate_on
                if (filtered_dot < 0) begin
                    x <= -filtered_dot; y <= -filtered_cross;
                    z <= filtered_cross >= 0 ? PI_Q28 : -PI_Q28;
                end else begin
                    x <= filtered_dot; y <= filtered_cross; z <= 0;
                end
                iteration <= 0;
                busy <= 1;
            end else if (busy) begin
                if (y >= 0) begin
                    next_x = x + (y >>> iteration);
                    next_y = y - (x >>> iteration);
                    next_z = z + angle[iteration];
                end else begin
                    next_x = x - (y >>> iteration);
                    next_y = y + (x >>> iteration);
                    next_z = z - angle[iteration];
                end
                x <= next_x; y <= next_y; z <= next_z;
                if (iteration == 17) begin
                    phase_q28 <= next_z[31:0];
                    valid_out <= 1;
                    busy <= 0;
                end else begin
                    iteration <= iteration + 1'b1;
                end
            end
        end
    end
endmodule
