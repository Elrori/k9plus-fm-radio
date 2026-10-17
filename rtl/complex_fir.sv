module complex_fir #(
    parameter integer TAPS = 101,
    parameter integer SAMPLE_WIDTH = 24,
    parameter integer COEFF_WIDTH = 20,
    parameter integer COEFF_SHIFT = 18
) (
    input  logic                          clk,
    input  logic                          rst,
    input  logic                          valid_in,
    input  logic signed [SAMPLE_WIDTH-1:0] i_in,
    input  logic signed [SAMPLE_WIDTH-1:0] q_in,
    output logic                          valid_out,
    output logic signed [SAMPLE_WIDTH-1:0] i_out,
    output logic signed [SAMPLE_WIDTH-1:0] q_out
);
    (* ram_style = "block" *) logic signed [SAMPLE_WIDTH-1:0] hist_i [0:127];
    (* ram_style = "block" *) logic signed [SAMPLE_WIDTH-1:0] hist_q [0:127];
    (* rom_style = "block" *) logic signed [COEFF_WIDTH-1:0] coeff [0:TAPS-1];
    logic [6:0] write_ptr, read_ptr, issue_count;
    logic busy, issue_valid, issue_last, product_valid, product_last;
    logic signed [SAMPLE_WIDTH-1:0] data_i_pipe, data_q_pipe;
    logic signed [COEFF_WIDTH-1:0] coeff_pipe;
    logic signed [SAMPLE_WIDTH+COEFF_WIDTH-1:0] product_i, product_q;
    logic signed [47:0] acc_i, acc_q, sum_i, sum_q;

    initial $readmemh("mem/channel_fir_q18.mem", coeff);

    function automatic signed [SAMPLE_WIDTH-1:0] sat_sample(input signed [47:0] value);
        reg signed [47:0] shifted;
        begin
            shifted = value >>> COEFF_SHIFT;
            if (shifted > ((1 <<< (SAMPLE_WIDTH-1))-1))
                sat_sample = {1'b0, {(SAMPLE_WIDTH-1){1'b1}}};
            else if (shifted < -(1 <<< (SAMPLE_WIDTH-1)))
                sat_sample = {1'b1, {(SAMPLE_WIDTH-1){1'b0}}};
            else
                sat_sample = shifted[SAMPLE_WIDTH-1:0];
        end
    endfunction

    always_comb begin
        sum_i = acc_i + product_i;
        sum_q = acc_q + product_q;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            write_ptr <= 0; read_ptr <= 0; issue_count <= 0; busy <= 0;
            issue_valid <= 0; issue_last <= 0; product_valid <= 0; product_last <= 0;
            data_i_pipe <= 0; data_q_pipe <= 0; coeff_pipe <= 0;
            product_i <= 0; product_q <= 0; acc_i <= 0; acc_q <= 0;
            valid_out <= 0; i_out <= 0; q_out <= 0;
        end else begin
            valid_out <= 0;
            issue_valid <= 0;

            product_valid <= issue_valid;
            product_last <= issue_last;
            if (issue_valid) begin
                product_i <= data_i_pipe * coeff_pipe;
                product_q <= data_q_pipe * coeff_pipe;
            end

            if (product_valid) begin
                if (product_last) begin
                    i_out <= sat_sample(sum_i);
                    q_out <= sat_sample(sum_q);
                    valid_out <= 1;
                    acc_i <= 0; acc_q <= 0;
                    busy <= 0;
                end else begin
                    acc_i <= sum_i;
                    acc_q <= sum_q;
                end
            end

            if (busy && issue_count < TAPS) begin
                data_i_pipe <= hist_i[read_ptr];
                data_q_pipe <= hist_q[read_ptr];
                coeff_pipe <= coeff[issue_count];
                issue_valid <= 1;
                issue_last <= (issue_count == TAPS-1);
                issue_count <= issue_count + 1'b1;
                read_ptr <= read_ptr - 1'b1;
            end

            if (valid_in) begin
                // synthesis translate_off
                if (busy) $fatal(1, "complex_fir input overrun");
                // synthesis translate_on
                hist_i[write_ptr] <= i_in;
                hist_q[write_ptr] <= q_in;
                read_ptr <= write_ptr;
                write_ptr <= write_ptr + 1'b1;
                issue_count <= 0;
                acc_i <= 0; acc_q <= 0;
                busy <= 1;
            end
        end
    end
endmodule
