`timescale 1ns/1ps
module tb_udp_audio_tx;
    logic clk = 0;
    logic rst = 1;
    logic sample_valid = 0;
    logic signed [15:0] sample = 0;
    logic sample_clipped = 0;
    logic [7:0] tx_byte;
    logic tx_valid, active;
    logic [31:0] packet_count, dropped_samples;
    integer i, fd;
    logic saw_frame = 0;

    always #4 clk = ~clk;

    udp_audio_tx dut (
        .clk, .rst, .sample_valid, .sample, .sample_clipped,
        .tuned_hz(32'd100_100_000), .tx_byte, .tx_valid, .active,
        .packet_count, .dropped_samples
    );

    always @(posedge clk) begin
        if (tx_valid) begin
            $fwrite(fd, "%02x\n", tx_byte);
            saw_frame <= 1;
        end else if (saw_frame) begin
            $fclose(fd);
            $display("UDP_FRAME_DONE");
            $finish;
        end
    end

    initial begin
        fd = $fopen("frame.hex", "w");
        repeat (8) @(posedge clk);
        rst <= 0;
        for (i = 0; i < 256; i = i + 1) begin
            repeat (10) @(posedge clk);
            sample <= i - 128;
            sample_valid <= 1;
            @(posedge clk);
            sample_valid <= 0;
        end
        repeat (5000) @(posedge clk);
        $fatal(1, "packet timeout");
    end
endmodule
