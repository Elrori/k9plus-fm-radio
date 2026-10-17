module cic3_decimator #(
    parameter integer DECIMATION = 20,
    parameter integer INPUT_WIDTH = 32,
    parameter integer ACC_WIDTH = 64,
    parameter integer OUTPUT_WIDTH = 32,
    parameter integer OUTPUT_SHIFT = 13
) (
    input  logic                           clk,
    input  logic                           rst,
    input  logic                           valid_in,
    input  logic signed [INPUT_WIDTH-1:0]  sample_in,
    output logic                           valid_out,
    output logic signed [OUTPUT_WIDTH-1:0] sample_out
);
    localparam integer COUNT_WIDTH = $clog2(DECIMATION);
    logic [COUNT_WIDTH-1:0] count;
    logic signed [ACC_WIDTH-1:0] int1, int2, int3;
    logic signed [ACC_WIDTH-1:0] delay1, delay2, delay3;
    logic signed [ACC_WIDTH-1:0] snapshot, comb1, comb2;
    logic snapshot_valid, comb1_valid, comb2_valid;
    logic [1:0] update_stage;
    logic signed [ACC_WIDTH-1:0] sample_pending, stage_value, stage_sum;

    always_ff @(posedge clk) begin
        if (rst) begin
            count <= 0; int1 <= 0; int2 <= 0; int3 <= 0;
            delay1 <= 0; delay2 <= 0; delay3 <= 0;
            snapshot <= 0; comb1 <= 0; comb2 <= 0;
            snapshot_valid <= 0; comb1_valid <= 0; comb2_valid <= 0;
            valid_out <= 0; sample_out <= 0;
            update_stage <= 0; sample_pending <= 0; stage_value <= 0; stage_sum <= 0;
        end else begin
            valid_out <= comb2_valid;
            snapshot_valid <= 0;
            comb1_valid <= snapshot_valid;
            comb2_valid <= comb1_valid;
            if (snapshot_valid) begin
                comb1 <= snapshot - delay1;
                delay1 <= snapshot;
            end
            if (comb1_valid) begin
                comb2 <= comb1 - delay2;
                delay2 <= comb1;
            end
            if (comb2_valid) begin
                sample_out <= (comb2 - delay3) >>> OUTPUT_SHIFT;
                delay3 <= comb2;
            end
            if (valid_in && update_stage == 0) begin
                sample_pending <= sample_in;
                update_stage <= 1;
            end else if (update_stage == 1) begin
                stage_sum = int1 + sample_pending;
                int1 <= stage_sum;
                stage_value <= stage_sum;
                update_stage <= 2;
            end else if (update_stage == 2) begin
                stage_sum = int2 + stage_value;
                int2 <= stage_sum;
                stage_value <= stage_sum;
                update_stage <= 3;
            end else if (update_stage == 3) begin
                stage_sum = int3 + stage_value;
                int3 <= stage_sum;
                update_stage <= 0;
                if (count == DECIMATION-1) begin
                    count <= 0; snapshot <= stage_sum; snapshot_valid <= 1;
                end else begin
                    count <= count + 1'b1;
                end
            end
        end
    end
endmodule
