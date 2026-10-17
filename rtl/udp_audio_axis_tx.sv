module udp_audio_axis_tx (
    input  logic               clk,
    input  logic               rst,
    input  logic               sample_valid,
    input  logic signed [15:0] sample,
    input  logic               sample_clipped,
    input  logic [31:0]        tuned_hz,
    input  logic [31:0]        rf_stats,
    input  logic [31:0]        rx_debug,
    input  logic [31:0]        channel_stats,
    output logic [7:0]         axis_data,
    output logic               axis_valid,
    input  logic               axis_ready,
    output logic               axis_last,
    output logic               active,
    output logic [31:0]        packet_count,
    output logic [31:0]        dropped_samples
);
    localparam integer LAST_FRAME_BYTE = 577;
    logic signed [15:0] audio_mem [0:255];
    logic [7:0] write_index;
    logic packet_ready;
    logic [9:0] byte_index;
    logic [31:0] packet_sequence, latched_tune, latched_status;
    logic [7:0] latched_flags;
    integer payload_offset;
    integer sample_index;

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
        axis_valid = active;
        axis_last = active && byte_index == LAST_FRAME_BYTE;
        axis_data = 8'h00;
        payload_offset = 0;
        sample_index = 0;
        if (byte_index <= 5) begin
            axis_data = 8'hff;
        end else if (byte_index >= 6 && byte_index <= 11) begin
            case (byte_index-6)
                0: axis_data=8'h02; 1: axis_data=8'h4b; 2: axis_data=8'h39;
                3: axis_data=8'h2b; 4: axis_data=8'h01; default: axis_data=8'h01;
            endcase
        end else if (byte_index == 12) begin
            axis_data = 8'h08;
        end else if (byte_index == 13) begin
            axis_data = 8'h00;
        end else if (byte_index >= 14 && byte_index <= 33) begin
            axis_data = ip_header_byte(byte_index-14);
        end else if (byte_index >= 34 && byte_index <= 41) begin
            axis_data = udp_header_byte(byte_index-34);
        end else if (byte_index >= 42 && byte_index <= LAST_FRAME_BYTE) begin
            payload_offset = byte_index - 42;
            case (payload_offset)
                0: axis_data=8'h4b; 1: axis_data=8'h39; 2: axis_data=8'h46; 3: axis_data=8'h4d;
                4: axis_data=8'h01; 5: axis_data=latched_flags;
                6: axis_data=8'h00; 7: axis_data=8'h01;
                8: axis_data=packet_sequence[7:0];
                9: axis_data=packet_sequence[15:8];
                10: axis_data=packet_sequence[23:16];
                11: axis_data=packet_sequence[31:24];
                12: axis_data=latched_tune[7:0];
                13: axis_data=latched_tune[15:8];
                14: axis_data=latched_tune[23:16];
                15: axis_data=latched_tune[31:24];
                16: axis_data=8'h80; 17: axis_data=8'hbb;
                18: axis_data=8'h00; 19: axis_data=8'h00;
                20: axis_data=latched_status[7:0];
                21: axis_data=latched_status[15:8];
                22: axis_data=latched_status[23:16];
                23: axis_data=latched_status[31:24];
                default: begin
                    sample_index = (payload_offset - 24) >> 1;
                    axis_data = payload_offset[0] ? audio_mem[sample_index][15:8]
                                                  : audio_mem[sample_index][7:0];
                end
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            write_index <= 0;
            packet_ready <= 0;
            byte_index <= 0;
            active <= 0;
            packet_sequence <= 0;
            packet_count <= 0;
            latched_tune <= 100_100_000;
            latched_status <= 0;
            latched_flags <= 0;
            dropped_samples <= 0;
        end else begin
            if (sample_valid) begin
                if (active || packet_ready) begin
                    dropped_samples <= dropped_samples + 1'b1;
                end else begin
                    audio_mem[write_index] <= sample;
                    if (write_index == 8'hff) begin
                        write_index <= 0;
                        packet_ready <= 1;
                    end else begin
                        write_index <= write_index + 1'b1;
                    end
                end
            end

            if (!active && packet_ready) begin
                active <= 1;
                packet_ready <= 0;
                byte_index <= 0;
                latched_tune <= tuned_hz;
                case (packet_count[1:0])
                    2'd1: begin latched_status <= rx_debug;      latched_flags <= 8'h02; end
                    2'd3: begin latched_status <= channel_stats; latched_flags <= 8'h04; end
                    default: begin latched_status <= rf_stats;   latched_flags <= 8'h01; end
                endcase
                packet_sequence <= packet_count;
                packet_count <= packet_count + 1'b1;
            end else if (active && axis_ready) begin
                if (byte_index == LAST_FRAME_BYTE) begin
                    active <= 0;
                    byte_index <= 0;
                end else begin
                    byte_index <= byte_index + 1'b1;
                end
            end
        end
    end

    wire unused_clipped = sample_clipped;
endmodule
