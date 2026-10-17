module fm_discriminator (
    input  logic                    clk,
    input  logic                    rst,
    input  logic                    valid_in,
    input  logic signed [23:0]      i_in,
    input  logic signed [23:0]      q_in,
    output logic                    valid_out,
    output logic signed [31:0]      phase_q28
);
    logic have_previous, product_pending, sum_pending, busy;
    logic signed [23:0] i_previous, q_previous;
    logic signed [47:0] product_ii, product_qq, product_iq, product_qi;
    logic signed [48:0] dot_value, cross_value;
    logic signed [48:0] x, y, next_x, next_y;
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
            have_previous <= 0; product_pending <= 0; sum_pending <= 0; busy <= 0;
            valid_out <= 0; phase_q28 <= 0; i_previous <= 0; q_previous <= 0;
            product_ii <= 0; product_qq <= 0; product_iq <= 0; product_qi <= 0;
            dot_value <= 0; cross_value <= 0; x <= 0; y <= 0; z <= 0; iteration <= 0;
        end else begin
            valid_out <= 0;
            if (valid_in) begin
                // synthesis translate_off
                if (busy || product_pending || sum_pending)
                    $fatal(1, "FM discriminator input overrun");
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
                dot_value <= product_ii + product_qq;
                cross_value <= product_iq - product_qi;
                product_pending <= 0;
                sum_pending <= 1;
            end else if (sum_pending) begin
                if (dot_value < 0) begin
                    x <= -dot_value; y <= -cross_value;
                    z <= cross_value >= 0 ? PI_Q28 : -PI_Q28;
                end else begin
                    x <= dot_value; y <= cross_value; z <= 0;
                end
                iteration <= 0; sum_pending <= 0; busy <= 1;
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
