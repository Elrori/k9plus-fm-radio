`timescale 1ns/1ps
module udp_audio_tx (
    input  logic                    clk,
    input  logic                    rst,
    input  logic                    sample_valid,
    input  logic signed [15:0]      sample,
    input  logic                    sample_clipped,
    input  logic [31:0]             tuned_hz,
    output logic [7:0]              tx_byte,
    output logic                    tx_valid,
    output logic                    active,
    output logic [31:0]             packet_count,
    output logic [31:0]             dropped_samples
);
    localparam integer LAST_DATA_BYTE = 585;
    localparam integer LAST_FRAME_BYTE = 589;
    logic signed [15:0] audio_mem [0:255];
    logic [7:0] write_index;
    logic packet_ready;
    logic [9:0] byte_index;
    logic [4:0] ifg_count;
    logic [31:0] crc, crc_next, final_crc;
    logic [31:0] packet_sequence, latched_tune, latched_drops, clip_count;
    integer payload_offset;
    integer sample_index;

    crc32_8bit crc_logic (.crc_in(crc), .data(tx_byte), .crc_out(crc_next));

    function automatic [7:0] ip_header_byte(input [4:0] n);
        begin
            case (n)
                0: ip_header_byte=8'h45; 1: ip_header_byte=8'h00;
                2: ip_header_byte=8'h02; 3: ip_header_byte=8'h34;
                4: ip_header_byte=8'h00; 5: ip_header_byte=8'h00;
                6: ip_header_byte=8'h40; 7: ip_header_byte=8'h00;
                8: ip_header_byte=8'h40; 9: ip_header_byte=8'h11;
                10: ip_header_byte=8'h6e; 11: ip_header_byte=8'h0f;
                12: ip_header_byte=8'hc0; 13: ip_header_byte=8'ha8;
                14: ip_header_byte=8'h0a; 15: ip_header_byte=8'h02;
                default: ip_header_byte=8'hff;
            endcase
        end
    endfunction

    function automatic [7:0] udp_header_byte(input [2:0] n);
        begin
            case (n)
                0: udp_header_byte=8'hc3; 1: udp_header_byte=8'h50;
                2: udp_header_byte=8'hc3; 3: udp_header_byte=8'h50;
                4: udp_header_byte=8'h02; 5: udp_header_byte=8'h20;
                default: udp_header_byte=8'h00;
            endcase
        end
    endfunction

    always_comb begin
        tx_valid = active;
        tx_byte = 8'h00;
        payload_offset = 0;
        sample_index = 0;
        if (byte_index <= 6) begin
            tx_byte = 8'h55;
        end else if (byte_index == 7) begin
            tx_byte = 8'hd5;
        end else if (byte_index >= 8 && byte_index <= 13) begin
            tx_byte = 8'hff;
        end else if (byte_index >= 14 && byte_index <= 19) begin
            case (byte_index-14)
                0: tx_byte=8'h02; 1: tx_byte=8'h4b; 2: tx_byte=8'h39;
                3: tx_byte=8'h2b; 4: tx_byte=8'h01; default: tx_byte=8'h01;
            endcase
        end else if (byte_index == 20) begin
            tx_byte = 8'h08;
        end else if (byte_index == 21) begin
            tx_byte = 8'h00;
        end else if (byte_index >= 22 && byte_index <= 41) begin
            tx_byte = ip_header_byte(byte_index-22);
        end else if (byte_index >= 42 && byte_index <= 49) begin
            tx_byte = udp_header_byte(byte_index-42);
        end else if (byte_index >= 50 && byte_index <= LAST_DATA_BYTE) begin
            payload_offset = byte_index - 50;
            case (payload_offset)
                0: tx_byte=8'h4b; 1: tx_byte=8'h39; 2: tx_byte=8'h46; 3: tx_byte=8'h4d;
                4: tx_byte=8'h01; 5: tx_byte=8'h00;
                6: tx_byte=8'h00; 7: tx_byte=8'h01;
                8: tx_byte=packet_sequence[7:0];
                9: tx_byte=packet_sequence[15:8];
                10: tx_byte=packet_sequence[23:16];
                11: tx_byte=packet_sequence[31:24];
                12: tx_byte=latched_tune[7:0];
                13: tx_byte=latched_tune[15:8];
                14: tx_byte=latched_tune[23:16];
                15: tx_byte=latched_tune[31:24];
                16: tx_byte=8'h80; 17: tx_byte=8'hbb;
                18: tx_byte=8'h00; 19: tx_byte=8'h00;
                20: tx_byte=latched_drops[7:0];
                21: tx_byte=latched_drops[15:8];
                22: tx_byte=latched_drops[23:16];
                23: tx_byte=latched_drops[31:24];
                default: begin
                    sample_index = (payload_offset - 24) >> 1;
                    if (payload_offset[0] == 1'b0)
                        tx_byte = audio_mem[sample_index][7:0];
                    else
                        tx_byte = audio_mem[sample_index][15:8];
                end
            endcase
        end else if (byte_index == 586) begin
            tx_byte = final_crc[7:0];
        end else if (byte_index == 587) begin
            tx_byte = final_crc[15:8];
        end else if (byte_index == 588) begin
            tx_byte = final_crc[23:16];
        end else if (byte_index == 589) begin
            tx_byte = final_crc[31:24];
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            write_index <= 0; packet_ready <= 0; byte_index <= 0; ifg_count <= 0;
            active <= 0; crc <= 32'hffffffff; final_crc <= 0;
            packet_sequence <= 0; packet_count <= 0;
            latched_tune <= 100_100_000; latched_drops <= 0;
            dropped_samples <= 0; clip_count <= 0;
        end else begin
            if (ifg_count != 0 && !active)
                ifg_count <= ifg_count - 1'b1;

            if (sample_valid) begin
                if (active || packet_ready) begin
                    dropped_samples <= dropped_samples + 1'b1;
                end else begin
                    audio_mem[write_index] <= sample;
                    if (sample_clipped) clip_count <= clip_count + 1'b1;
                    if (write_index == 8'hff) begin
                        write_index <= 0;
                        packet_ready <= 1;
                    end else begin
                        write_index <= write_index + 1'b1;
                    end
                end
            end

            if (!active && packet_ready && ifg_count == 0) begin
                active <= 1;
                packet_ready <= 0;
                byte_index <= 0;
                crc <= 32'hffffffff;
                latched_tune <= tuned_hz;
                latched_drops <= dropped_samples;
                packet_sequence <= packet_count;
                packet_count <= packet_count + 1'b1;
            end else if (active) begin
                if (byte_index >= 8 && byte_index <= LAST_DATA_BYTE)
                    crc <= crc_next;
                if (byte_index == LAST_DATA_BYTE)
                    final_crc <= ~crc_next;
                if (byte_index == LAST_FRAME_BYTE) begin
                    active <= 0;
                    byte_index <= 0;
                    ifg_count <= 12;
                end else begin
                    byte_index <= byte_index + 1'b1;
                end
            end
        end
    end
endmodule
