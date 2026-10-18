`timescale 1ns/1ps
module udp_raw_axis_tx #(
    parameter integer RAW_BYTES = 1440
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        enable,
    input  logic [31:0] tuned_hz,
    input  logic [31:0] overflow_bytes,
    input  logic [7:0]  fifo_data,
    input  logic        fifo_empty,
    input  logic [12:0] fifo_count,
    output logic        fifo_rd_en,
    output logic [7:0]  axis_data,
    output logic        axis_valid,
    input  logic        axis_ready,
    output logic        axis_last,
    output logic        active,
    output logic [31:0] packet_count
);
    localparam integer PAYLOAD_BYTES = 32 + RAW_BYTES;
    localparam integer LAST_FRAME_BYTE = 14 + 20 + 8 + PAYLOAD_BYTES - 1;
    localparam [31:0] SAMPLE_RATE = 32'd240_000_000;

    logic [10:0] byte_index;
    logic [31:0] latched_sequence, latched_tune, latched_overflow;
    logic [63:0] transmitted_samples, latched_sample_index;
    integer payload_offset;

    function automatic [7:0] ip_header_byte(input [4:0] n);
        begin
            case (n)
                0: ip_header_byte=8'h45; 1: ip_header_byte=8'h00;
                2: ip_header_byte=8'h05; 3: ip_header_byte=8'hdc;
                4: ip_header_byte=8'h00; 5: ip_header_byte=8'h00;
                6: ip_header_byte=8'h40; 7: ip_header_byte=8'h00;
                8: ip_header_byte=8'h40; 9: ip_header_byte=8'h11;
                10: ip_header_byte=8'h6a; 11: ip_header_byte=8'h67;
                12: ip_header_byte=8'hc0; 13: ip_header_byte=8'ha8;
                14: ip_header_byte=8'h0a; 15: ip_header_byte=8'h02;
                default: ip_header_byte=8'hff;
            endcase
        end
    endfunction

    function automatic [7:0] udp_header_byte(input [2:0] n);
        begin
            case (n)
                0: udp_header_byte=8'hc3; 1: udp_header_byte=8'h52;
                2: udp_header_byte=8'hc3; 3: udp_header_byte=8'h52;
                4: udp_header_byte=8'h05; 5: udp_header_byte=8'hc8;
                default: udp_header_byte=8'h00;
            endcase
        end
    endfunction

    always_comb begin
        axis_valid = active;
        axis_last = active && byte_index == LAST_FRAME_BYTE;
        axis_data = 0;
        fifo_rd_en = 0;
        payload_offset = 0;
        if (byte_index <= 5) begin
            axis_data = 8'hff;
        end else if (byte_index >= 6 && byte_index <= 11) begin
            case (byte_index-6)
                0: axis_data=8'h02; 1: axis_data=8'h4b; 2: axis_data=8'h39;
                3: axis_data=8'h2b; 4: axis_data=8'h01; default: axis_data=8'h02;
            endcase
        end else if (byte_index == 12) begin
            axis_data = 8'h08;
        end else if (byte_index == 13) begin
            axis_data = 8'h00;
        end else if (byte_index >= 14 && byte_index <= 33) begin
            axis_data = ip_header_byte(byte_index-14);
        end else if (byte_index >= 34 && byte_index <= 41) begin
            axis_data = udp_header_byte(byte_index-34);
        end else begin
            payload_offset = byte_index - 42;
            case (payload_offset)
                0: axis_data=8'h4b; 1: axis_data=8'h39; 2: axis_data=8'h52; 3: axis_data=8'h46;
                4: axis_data=8'h01;
                5: axis_data=(latched_overflow != 0) ? 8'h01 : 8'h00;
                6: axis_data=8'h20; 7: axis_data=8'h00;
                8: axis_data=latched_sequence[7:0];
                9: axis_data=latched_sequence[15:8];
                10: axis_data=latched_sequence[23:16];
                11: axis_data=latched_sequence[31:24];
                12: axis_data=latched_tune[7:0];
                13: axis_data=latched_tune[15:8];
                14: axis_data=latched_tune[23:16];
                15: axis_data=latched_tune[31:24];
                16: axis_data=SAMPLE_RATE[7:0];
                17: axis_data=SAMPLE_RATE[15:8];
                18: axis_data=SAMPLE_RATE[23:16];
                19: axis_data=SAMPLE_RATE[31:24];
                20: axis_data=latched_sample_index[7:0];
                21: axis_data=latched_sample_index[15:8];
                22: axis_data=latched_sample_index[23:16];
                23: axis_data=latched_sample_index[31:24];
                24: axis_data=latched_sample_index[39:32];
                25: axis_data=latched_sample_index[47:40];
                26: axis_data=latched_sample_index[55:48];
                27: axis_data=latched_sample_index[63:56];
                28: axis_data=latched_overflow[7:0];
                29: axis_data=latched_overflow[15:8];
                30: axis_data=latched_overflow[23:16];
                31: axis_data=latched_overflow[31:24];
                default: begin
                    axis_data = fifo_data;
                    fifo_rd_en = active && axis_ready && !fifo_empty;
                end
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (rst || !enable) begin
            byte_index <= 0;
            active <= 0;
            packet_count <= 0;
            latched_sequence <= 0;
            latched_tune <= 0;
            latched_overflow <= 0;
            transmitted_samples <= 0;
            latched_sample_index <= 0;
        end else begin
            if (!active && fifo_count >= RAW_BYTES) begin
                active <= 1;
                byte_index <= 0;
                latched_sequence <= packet_count;
                latched_tune <= tuned_hz;
                latched_overflow <= overflow_bytes;
                latched_sample_index <= transmitted_samples;
                packet_count <= packet_count + 1'b1;
            end else if (active && axis_ready) begin
                if (byte_index == LAST_FRAME_BYTE) begin
                    active <= 0;
                    byte_index <= 0;
                    transmitted_samples <= transmitted_samples + RAW_BYTES*8;
                end else begin
                    byte_index <= byte_index + 1'b1;
                end
            end
        end
    end
endmodule
