`timescale 1ns/1ps
module tb_iq_sample_cdc;
    logic wr_clk=0, rd_clk=0, wr_rst=1, fifo_rst=1, enable=0, valid=0;
    logic signed [23:0] i_sample=0, q_sample=0;
    wire [15:0] data;
    wire empty;
    wire [12:0] count;
    wire [31:0] overflow;
    wire rd_en = !empty;
    integer received=0;
    reg [15:0] expected [0:2];

    always #4 wr_clk = ~wr_clk;
    always #5 rd_clk = ~rd_clk;

    iq_sample_cdc #(.INPUT_SHIFT(0)) dut (
        .wr_clk, .wr_rst, .enable_wr(enable), .sample_valid(valid),
        .i_sample, .q_sample, .rd_clk, .fifo_rst,
        .rd_data(data), .rd_en, .rd_empty(empty), .rd_count(count),
        .overflow_bytes(overflow)
    );

    task send_sample(input integer i_value, input integer q_value);
        begin
            @(posedge wr_clk); i_sample <= i_value; q_sample <= q_value; valid <= 1;
            @(posedge wr_clk); valid <= 0;
            repeat(6) @(posedge wr_clk);
        end
    endtask

    always @(posedge rd_clk) begin
        if (rd_en) begin
            if (data !== expected[received]) begin
                $display("IQ_CDC_FAIL index=%0d got=%04x expected=%04x", received, data, expected[received]);
                $fatal(1);
            end
            received <= received + 1;
        end
    end

    initial begin
        expected[0]=16'hfe01;
        expected[1]=16'hfc03;
        expected[2]=16'hfa05;
        repeat(8) @(posedge wr_clk);
        wr_rst <= 0; fifo_rst <= 0; enable <= 1;
        wait(dut.wr_rst_busy == 0 && dut.rd_rst_busy == 0);
        wait(dut.stream_ready == 1);
        repeat(2) @(posedge wr_clk);
        send_sample(1,-2);
        send_sample(3,-4);
        wait(received == 2);
        @(posedge wr_clk); enable <= 0; wr_rst <= 1; fifo_rst <= 1;
        repeat(6) @(posedge wr_clk);
        wr_rst <= 0; fifo_rst <= 0; enable <= 1;
        wait(dut.wr_rst_busy == 0 && dut.rd_rst_busy == 0);
        wait(dut.stream_ready == 1);
        repeat(2) @(posedge wr_clk);
        send_sample(5,-6);
        wait(received == 3);
        if (overflow != 0) $fatal(1,"unexpected overflow");
        $display("IQ_CDC_PASS words=%0d",received);
        $finish;
    end

    initial begin
        #20000; $fatal(1,"timeout");
    end
endmodule
