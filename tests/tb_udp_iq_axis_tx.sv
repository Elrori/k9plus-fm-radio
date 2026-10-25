`timescale 1ns/1ps
module tb_udp_iq_axis_tx;
    logic clk=0, rst=1, enable=0, ready=1;
    logic [15:0] fifo_data=16'h0100;
    logic fifo_empty=0;
    logic [12:0] fifo_count=13'd720;
    logic fifo_rd_en, valid, last, active;
    logic [7:0] data;
    logic [31:0] packet_count;
    integer fd;
    always #4 clk=~clk;

    udp_iq_axis_tx #(.COMPENSATED_DFE(1)) dut (
        .clk, .rst, .enable, .tuned_hz(32'd96_800_000),
        .overflow_bytes(32'd0), .fifo_data, .fifo_empty, .fifo_count,
        .fifo_rd_en, .axis_data(data), .axis_valid(valid),
        .axis_ready(ready), .axis_last(last), .active, .packet_count
    );

    always_ff @(posedge clk) begin
        if (fifo_rd_en) begin
            fifo_data[7:0] <= fifo_data[7:0] + 2;
            fifo_data[15:8] <= fifo_data[15:8] + 2;
            fifo_count <= fifo_count - 1'b1;
        end
        if (valid && ready) begin
            $fwrite(fd, "%02x\n", data);
            if (last) begin
                $fclose(fd);
                $display("IQ_AXIS_FRAME_DONE");
                $finish;
            end
        end
    end

    initial begin
        fd=$fopen("iq_axis_frame.hex", "w");
        repeat(8) @(posedge clk);
        rst<=0; enable<=1;
        repeat(4000) @(posedge clk);
        $fatal(1, "IQ packet timeout");
    end
endmodule
