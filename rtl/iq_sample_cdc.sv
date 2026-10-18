module iq_sample_cdc #(
    parameter integer INPUT_SHIFT = 8
) (
    input  logic                    wr_clk,
    input  logic                    wr_rst,
    input  logic                    enable_wr,
    input  logic                    sample_valid,
    input  logic signed [23:0]      i_sample,
    input  logic signed [23:0]      q_sample,
    input  logic                    rd_clk,
    input  logic                    fifo_rst,
    output logic [7:0]              rd_data,
    input  logic                    rd_en,
    output logic                    rd_empty,
    output logic [13:0]             rd_count,
    output logic [31:0]             overflow_bytes
);
    logic [15:0] pending_word;
    logic [1:0] pending_bytes;
    logic [7:0] fifo_din;
    logic fifo_wr_en, fifo_full;
    logic wr_rst_busy, rd_rst_busy;
    logic signed [7:0] i_quantized, q_quantized;

    function automatic signed [7:0] quantize(input signed [23:0] value);
        reg signed [23:0] shifted;
        begin
            shifted = value >>> INPUT_SHIFT;
            if (shifted > 127)
                quantize = 8'sh7f;
            else if (shifted < -128)
                quantize = 8'sh80;
            else
                quantize = shifted[7:0];
        end
    endfunction

    always_comb begin
        i_quantized = quantize(i_sample);
        q_quantized = quantize(q_sample);
    end

    always_ff @(posedge wr_clk) begin
        if (wr_rst || !enable_wr) begin
            pending_word <= 0;
            pending_bytes <= 0;
            fifo_din <= 0;
            fifo_wr_en <= 0;
            overflow_bytes <= 0;
        end else begin
            fifo_wr_en <= 0;
            if (pending_bytes != 0) begin
                if (!wr_rst_busy && !fifo_full) begin
                    fifo_din <= pending_word[7:0];
                    pending_word <= {8'h00, pending_word[15:8]};
                    pending_bytes <= pending_bytes - 1'b1;
                    fifo_wr_en <= 1;
                end else if (!wr_rst_busy && fifo_full) begin
                    // Count bytes, not samples, to match the packet header.
                    overflow_bytes <= overflow_bytes + 1'b1;
                    pending_word <= {8'h00, pending_word[15:8]};
                    pending_bytes <= pending_bytes - 1'b1;
                end
            end else if (sample_valid) begin
                // Signed I8,Q8 display samples.  Reducing the monitor stream
                // to two bytes/sample halves both network bandwidth and host
                // packet rate; it never enters the audio DSP path.
                pending_word <= {q_quantized, i_quantized};
                pending_bytes <= 2'd2;
            end
        end
    end

    xpm_fifo_async #(
        .CDC_SYNC_STAGES(2),
        .DOUT_RESET_VALUE("0"),
        .ECC_MODE("no_ecc"),
        .FIFO_MEMORY_TYPE("block"),
        .FIFO_READ_LATENCY(0),
        .FIFO_WRITE_DEPTH(8192),
        .FULL_RESET_VALUE(0),
        .PROG_EMPTY_THRESH(10),
        .PROG_FULL_THRESH(8000),
        .RD_DATA_COUNT_WIDTH(14),
        .READ_DATA_WIDTH(8),
        .READ_MODE("fwft"),
        .RELATED_CLOCKS(0),
        .SIM_ASSERT_CHK(0),
        .USE_ADV_FEATURES("0707"),
        .WAKEUP_TIME(0),
        .WRITE_DATA_WIDTH(8),
        .WR_DATA_COUNT_WIDTH(14)
    ) iq_fifo (
        .almost_empty(), .almost_full(), .data_valid(), .dbiterr(),
        .dout(rd_data), .empty(rd_empty), .full(fifo_full),
        .overflow(), .prog_empty(), .prog_full(), .rd_data_count(rd_count),
        .rd_rst_busy(rd_rst_busy), .sbiterr(), .underflow(), .wr_ack(),
        .wr_data_count(), .wr_rst_busy(wr_rst_busy),
        .din(fifo_din), .injectdbiterr(1'b0), .injectsbiterr(1'b0),
        .rd_clk(rd_clk), .rd_en(rd_en && !rd_rst_busy), .rst(fifo_rst),
        .sleep(1'b0), .wr_clk(wr_clk), .wr_en(fifo_wr_en)
    );
endmodule
