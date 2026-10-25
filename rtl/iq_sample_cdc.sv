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
    output logic [15:0]             rd_data,
    input  logic                    rd_en,
    output logic                    rd_empty,
    output logic [12:0]             rd_count,
    output logic [31:0]             overflow_bytes
);
    logic [15:0] fifo_din;
    logic fifo_wr_en, fifo_full;
    logic wr_rst_busy, rd_rst_busy;
    logic [5:0] startup_guard;
    logic stream_ready;
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
        // Cross the clock boundary as one atomic complex sample.  A byte-wide
        // FIFO can cold-start on either byte phase if its two clock domains
        // leave reset at different instants; a 16-bit {Q,I} word makes that
        // failure structurally impossible.
        fifo_din = {q_quantized, i_quantized};
        stream_ready = startup_guard[5];
        fifo_wr_en = enable_wr && !wr_rst && stream_ready && sample_valid &&
                     !wr_rst_busy && !fifo_full;
    end

    always_ff @(posedge wr_clk) begin
        if (wr_rst || !enable_wr || wr_rst_busy) begin
            overflow_bytes <= 0;
            startup_guard <= 0;
        end else if (!stream_ready) begin
            // At FPGA cold boot the XPM reset request crosses from the
            // Ethernet clock domain.  wr_rst_busy can initially read low for
            // a few RF clocks before the reset reaches this domain.  Do not
            // accept a partial I/Q word during that window: require 32 clean
            // clocks after the final busy interval.  JTAG configuration and
            // SPI-flash boot then start on the same byte boundary.
            overflow_bytes <= 0;
            startup_guard <= startup_guard + 1'b1;
        end else begin
            // The public counter remains byte-based even though the FIFO now
            // drops a complete complex sample atomically.
            if (sample_valid && !wr_rst_busy && fifo_full)
                overflow_bytes <= overflow_bytes + 2;
        end
    end

    xpm_fifo_async #(
        .CDC_SYNC_STAGES(2),
        .DOUT_RESET_VALUE("0"),
        .ECC_MODE("no_ecc"),
        .FIFO_MEMORY_TYPE("block"),
        .FIFO_READ_LATENCY(0),
        .FIFO_WRITE_DEPTH(4096),
        .FULL_RESET_VALUE(0),
        .PROG_EMPTY_THRESH(10),
        .PROG_FULL_THRESH(4000),
        .RD_DATA_COUNT_WIDTH(13),
        .READ_DATA_WIDTH(16),
        .READ_MODE("fwft"),
        .RELATED_CLOCKS(0),
        .SIM_ASSERT_CHK(0),
        .USE_ADV_FEATURES("0707"),
        .WAKEUP_TIME(0),
        .WRITE_DATA_WIDTH(16),
        .WR_DATA_COUNT_WIDTH(13)
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
