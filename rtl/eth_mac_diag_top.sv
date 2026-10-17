module eth_mac_diag_top (
    input  wire        eth_rx_clk,
    output wire        eth_tx_clk,
    output wire [3:0]  eth_tx_data,
    output wire        eth_tx_ctl,
    output wire        eth1_tx_clk,
    output wire [3:0]  eth1_tx_data,
    output wire        eth1_tx_ctl,
    output wire        eth_rst_n,
    output wire [1:0]  led
);
    assign eth_rst_n = 1'b1;
    wire clk_in, clk_mmcm, clk90_mmcm, clk, clk90, clk_feedback, clock_locked;
    IBUF rx_clock_input (.I(eth_rx_clk), .O(clk_in));
    MMCME2_BASE #(
        .CLKIN1_PERIOD(8.0), .CLKFBOUT_MULT_F(8.0), .DIVCLK_DIVIDE(1),
        .CLKOUT0_DIVIDE_F(8.0), .CLKOUT1_DIVIDE(8), .CLKOUT1_PHASE(90.0)
    ) ethernet_clock_mmcm (
        .CLKIN1(clk_in), .CLKFBIN(clk_feedback), .RST(1'b0), .PWRDWN(1'b0),
        .CLKFBOUT(clk_feedback), .CLKOUT0(clk_mmcm), .CLKOUT1(clk90_mmcm),
        .LOCKED(clock_locked)
    );
    BUFG clock_buffer (.I(clk_mmcm), .O(clk));
    BUFG clock90_buffer (.I(clk90_mmcm), .O(clk90));

    logic [7:0] reset_pipe = 8'hff;
    always_ff @(posedge clk)
        reset_pipe <= {reset_pipe[6:0], ~clock_locked};
    wire rst = reset_pipe[7];

    logic [16:0] gap_count;
    logic [9:0] frame_index;
    logic frame_active;
    logic [31:0] frame_count;
    wire axis_ready;
    wire [7:0] axis_data;
    wire axis_valid = frame_active;
    wire axis_last = frame_index == 10'd577;

    function automatic [7:0] frame_byte(input [9:0] n);
        integer p;
        begin
            frame_byte = 8'h00;
            if (n <= 5) frame_byte = 8'hff;
            else if (n >= 6 && n <= 11) begin
                case (n-6)
                    0: frame_byte=8'h02; 1: frame_byte=8'h4b; 2: frame_byte=8'h39;
                    3: frame_byte=8'h2b; 4: frame_byte=8'h01; default: frame_byte=8'h01;
                endcase
            end else if (n == 12) frame_byte = 8'h08;
            else if (n == 13) frame_byte = 8'h00;
            else if (n >= 14 && n <= 33) begin
                case (n-14)
                    0: frame_byte=8'h45; 1: frame_byte=8'h00; 2: frame_byte=8'h02; 3: frame_byte=8'h34;
                    4: frame_byte=8'h00; 5: frame_byte=8'h00; 6: frame_byte=8'h40; 7: frame_byte=8'h00;
                    8: frame_byte=8'h40; 9: frame_byte=8'h11; 10: frame_byte=8'h6e; 11: frame_byte=8'h0f;
                    12: frame_byte=8'hc0; 13: frame_byte=8'ha8; 14: frame_byte=8'h0a; 15: frame_byte=8'h02;
                    default: frame_byte=8'hff;
                endcase
            end else if (n >= 34 && n <= 41) begin
                case (n-34)
                    0: frame_byte=8'hc3; 1: frame_byte=8'h50; 2: frame_byte=8'hc3; 3: frame_byte=8'h50;
                    4: frame_byte=8'h02; 5: frame_byte=8'h20; default: frame_byte=8'h00;
                endcase
            end else if (n >= 42) begin
                p = n-42;
                case (p)
                    0: frame_byte=8'h4b; 1: frame_byte=8'h39; 2: frame_byte=8'h46; 3: frame_byte=8'h4d;
                    4: frame_byte=8'h01; 5: frame_byte=8'h00; 6: frame_byte=8'h00; 7: frame_byte=8'h01;
                    16: frame_byte=8'h80; 17: frame_byte=8'hbb;
                    default: frame_byte=8'h00;
                endcase
            end
        end
    endfunction
    assign axis_data = frame_byte(frame_index);

    always_ff @(posedge clk) begin
        if (rst) begin
            gap_count <= 0;
            frame_index <= 0;
            frame_active <= 0;
            frame_count <= 0;
        end else if (!frame_active) begin
            if (gap_count == 17'd124999) begin
                gap_count <= 0;
                frame_index <= 0;
                frame_active <= 1;
            end else gap_count <= gap_count + 1'b1;
        end else if (axis_ready) begin
            if (axis_last) begin
                frame_active <= 0;
                frame_index <= 0;
                frame_count <= frame_count + 1'b1;
            end else frame_index <= frame_index + 1'b1;
        end
    end

    wire [7:0] gmii_txd;
    wire gmii_tx_en, gmii_tx_er;
    axis_gmii_tx #(.ENABLE_PADDING(1), .MIN_FRAME_LENGTH(64)) mac_tx (
        .clk(clk), .rst(rst),
        .s_axis_tdata(axis_data), .s_axis_tvalid(axis_valid), .s_axis_tready(axis_ready),
        .s_axis_tlast(axis_last), .s_axis_tuser(1'b0),
        .gmii_txd(gmii_txd), .gmii_tx_en(gmii_tx_en), .gmii_tx_er(gmii_tx_er),
        .ptp_ts(96'd0), .m_axis_ptp_ts(), .m_axis_ptp_ts_tag(), .m_axis_ptp_ts_valid(),
        .clk_enable(1'b1), .mii_select(1'b0), .cfg_ifg(8'd12), .cfg_tx_enable(1'b1),
        .start_packet(), .error_underflow()
    );

    rgmii_tx phy0 (
        .clk(clk), .clk90(clk90), .tx_byte(gmii_txd), .tx_valid(gmii_tx_en),
        .rgmii_tx_clk(eth_tx_clk), .rgmii_txd(eth_tx_data),
        .rgmii_tx_ctl(eth_tx_ctl)
    );
    rgmii_tx phy1 (
        .clk(clk), .clk90(clk90), .tx_byte(gmii_txd), .tx_valid(gmii_tx_en),
        .rgmii_tx_clk(eth1_tx_clk), .rgmii_txd(eth1_tx_data),
        .rgmii_tx_ctl(eth1_tx_ctl)
    );

    assign led = {frame_count[0], ~rst};
endmodule
