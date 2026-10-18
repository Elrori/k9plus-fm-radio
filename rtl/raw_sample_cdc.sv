module raw_sample_cdc (
    input  logic        wr_clk,
    input  logic        wr_rst,
    input  logic        raw_enable_wr,
    input  logic        sample_0,
    input  logic        sample_1,
    input  logic        rd_clk,
    input  logic        fifo_rst,
    output logic [7:0]  rd_data,
    input  logic        rd_en,
    output logic        rd_empty,
    output logic [12:0] rd_count,
    output logic [31:0] overflow_bytes
);
    logic [7:0] pack_shift;
    logic [1:0] pair_count;
    logic [7:0] fifo_din;
    logic fifo_wr_en, fifo_full;
    logic wr_rst_busy, rd_rst_busy;

    always_ff @(posedge wr_clk) begin
        if (wr_rst || !raw_enable_wr) begin
            pack_shift <= 0;
            pair_count <= 0;
            fifo_din <= 0;
            fifo_wr_en <= 0;
            overflow_bytes <= 0;
        end else begin
            fifo_wr_en <= 0;
            pack_shift <= {sample_1, sample_0, pack_shift[7:2]};
            if (pair_count == 2'd3) begin
                pair_count <= 0;
                if (wr_rst_busy) begin
                    // The first few packed bytes after a mode transition are
                    // intentionally discarded while XPM releases reset.  They
                    // precede sample index zero and are not a FIFO overflow.
                    fifo_wr_en <= 0;
                end else if (!fifo_full) begin
                    // Samples are chronological from LSB to MSB:
                    // bit 0=sample_0 of the oldest pair, bit 1=sample_1.
                    fifo_din <= {sample_1, sample_0, pack_shift[7:2]};
                    fifo_wr_en <= 1;
                end else begin
                    overflow_bytes <= overflow_bytes + 1'b1;
                end
            end else begin
                pair_count <= pair_count + 1'b1;
            end
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
        .READ_DATA_WIDTH(8),
        .READ_MODE("fwft"),
        .RELATED_CLOCKS(0),
        .SIM_ASSERT_CHK(0),
        .USE_ADV_FEATURES("0707"),
        .WAKEUP_TIME(0),
        .WRITE_DATA_WIDTH(8),
        .WR_DATA_COUNT_WIDTH(13)
    ) raw_fifo (
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
