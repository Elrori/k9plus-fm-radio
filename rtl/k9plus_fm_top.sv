module k9plus_fm_top (
    input  wire        clk_25m,
    input  wire        rf_p,
    input  wire        rf_n,
    input  wire [3:0]  key_n,
    output wire [3:0]  led,
    output wire        eth_tx_clk,
    output wire [3:0]  eth_tx_data,
    output wire        eth_tx_ctl,
    output wire        eth_rst_n,
    input  wire        eth_rx_clk,
    input  wire [3:0]  eth_rx_data,
    input  wire        eth_rx_ctl,
    output wire        eth_mdc,
    inout  wire        eth_mdio
);
    // 96.8 MHz / 240 MHz * 2^32, rounded to the nearest integer.
    localparam [31:0] INITIAL_PHASE_INC = 32'd1732303476;
    localparam [31:0] TUNE_STEP_INC = 32'd1789570;
    localparam [31:0] MIN_PHASE_INC = 32'd1574821342;
    localparam [31:0] MAX_PHASE_INC = 32'd1932735283;

    wire clk_rf, rf_locked;
    wire clk_idelay_ref, idelay_ref_locked;
    clock_gen clocks (
        .clk_25m(clk_25m), .clk_rf(clk_rf), .clk_eth(clk_idelay_ref),
        .rf_locked(rf_locked), .eth_locked(idelay_ref_locked)
    );

    // Match the verified LiteEth target: PHY0 RX_CLK is the Ethernet clock
    // domain and is returned on TX_CLK with zero added delay.
    wire clk_eth;

    logic [7:0] rf_reset_pipe = 8'hff;
    logic [7:0] eth_reset_pipe = 8'hff;
    always_ff @(posedge clk_rf)
        rf_reset_pipe <= !rf_locked ? 8'hff : {rf_reset_pipe[6:0], 1'b0};
    always_ff @(posedge clk_eth)
        eth_reset_pipe <= {eth_reset_pipe[6:0], 1'b0};
    wire rf_rst = rf_reset_pipe[7];
    wire eth_rst = eth_reset_pipe[7];

    // Match the verified XI050CD example: actively deassert PHY reset on W22.
    assign eth_rst_n = 1'b1;
    assign eth_mdc = 1'b0;
    assign eth_mdio = 1'bz;
    wire [31:0] net_tune_hz_eth, net_phase_eth;
    wire net_tune_toggle_eth;
    wire net_bypass_request_eth;
    wire [31:0] net_rx_debug;
    rgmii_tune_rx tune_receiver (
        .phy_clk(eth_rx_clk), .idelay_refclk(clk_idelay_ref),
        .idelay_rst(!idelay_ref_locked), .clk(clk_eth), .rst(eth_rst), .rgmii_rxd(eth_rx_data),
        .rgmii_rx_ctl(eth_rx_ctl), .tune_hz(net_tune_hz_eth),
        .phase_increment(net_phase_eth), .tune_toggle(net_tune_toggle_eth),
        .bypass_mode(net_bypass_request_eth),
        .debug_status(net_rx_debug)
    );

    wire rf_bit;
    wire rf_sample_0, rf_sample_1;
    IBUFDS #(.DIFF_TERM("FALSE"), .IBUF_LOW_PWR("FALSE"), .IOSTANDARD("LVDS_25"))
        rf_ibuf (.I(rf_p), .IB(rf_n), .O(rf_bit));
    IDDR #(.DDR_CLK_EDGE("SAME_EDGE_PIPELINED"), .SRTYPE("SYNC")) rf_iddr (
        .C(clk_rf), .CE(1'b1), .D(rf_bit), .R(rf_rst), .S(1'b0),
        .Q1(rf_sample_0), .Q2(rf_sample_1)
    );

    // A mode request is applied only between Ethernet frames.  This prevents
    // a host command from truncating an audio or raw frame already in flight.
    logic tx_bypass_mode;
    wire audio_tx_active, raw_tx_active;
    always_ff @(posedge clk_eth) begin
        if (eth_rst)
            tx_bypass_mode <= 0;
        else if (!tx_bypass_mode && net_bypass_request_eth && !audio_tx_active)
            tx_bypass_mode <= 1;
        else if (tx_bypass_mode && !net_bypass_request_eth && !raw_tx_active)
            tx_bypass_mode <= 0;
    end

    (* ASYNC_REG = "TRUE" *) logic bypass_meta_rf, bypass_sync_rf;
    always_ff @(posedge clk_rf) begin
        bypass_meta_rf <= tx_bypass_mode;
        bypass_sync_rf <= bypass_meta_rf;
    end

    wire [7:0] raw_fifo_data;
    wire raw_fifo_empty;
    wire [12:0] raw_fifo_count;
    wire raw_fifo_rd_en;
    wire [31:0] raw_overflow_rf;
    raw_sample_cdc raw_cdc (
        .wr_clk(clk_rf), .wr_rst(rf_rst), .raw_enable_wr(bypass_sync_rf),
        .sample_0(rf_sample_0), .sample_1(rf_sample_1),
        .rd_clk(clk_eth), .fifo_rst(eth_rst || !tx_bypass_mode),
        .rd_data(raw_fifo_data), .rd_en(raw_fifo_rd_en),
        .rd_empty(raw_fifo_empty), .rd_count(raw_fifo_count),
        .overflow_bytes(raw_overflow_rf)
    );

    // Measure the raw 1-bit stream over 65536 RF clock cycles (131072 samples).
    // Each 16-bit result is normalized to 0..65535: upper half is one density,
    // lower half is transition density.  This distinguishes a saturated input,
    // a random threshold-noise stream, and a coherent RF carrier on live hardware.
    logic [15:0] rf_stat_window;
    logic [17:0] rf_ones_acc, rf_trans_acc;
    logic rf_previous;
    logic [31:0] rf_stats_hold;
    wire [17:0] rf_ones_next = rf_ones_acc + rf_sample_0 + rf_sample_1;
    wire [17:0] rf_trans_next = rf_trans_acc +
        (rf_previous ^ rf_sample_0) + (rf_sample_0 ^ rf_sample_1);
    always_ff @(posedge clk_rf) begin
        if (rf_rst) begin
            rf_stat_window <= 0;
            rf_ones_acc <= 0;
            rf_trans_acc <= 0;
            rf_previous <= 0;
            rf_stats_hold <= 0;
        end else begin
            rf_previous <= rf_sample_1;
            if (rf_stat_window == 16'hffff) begin
                rf_stat_window <= 0;
                rf_ones_acc <= 0;
                rf_trans_acc <= 0;
                rf_stats_hold[31:16] <= rf_ones_next[17] ? 16'hffff : rf_ones_next[16:1];
                rf_stats_hold[15:0] <= rf_trans_next[17] ? 16'hffff : rf_trans_next[16:1];
            end else begin
                rf_stat_window <= rf_stat_window + 1'b1;
                rf_ones_acc <= rf_ones_next;
                rf_trans_acc <= rf_trans_next;
            end
        end
    end

    logic [2:0] key_sync_0, key_sync_1;
    logic [19:0] key_divider;
    logic [2:0] key_previous;
    logic [7:0] key0_hold, key1_hold;
    logic [31:0] phase_increment, tuned_hz;
    (* ASYNC_REG = "TRUE" *) logic net_toggle_meta, net_toggle_sync;
    (* ASYNC_REG = "TRUE" *) logic [31:0] net_hz_meta, net_hz_sync;
    (* ASYNC_REG = "TRUE" *) logic [31:0] net_phase_meta, net_phase_sync;
    logic net_toggle_seen;
    always_ff @(posedge clk_rf) begin
        net_toggle_meta <= net_tune_toggle_eth;
        net_toggle_sync <= net_toggle_meta;
        net_hz_meta <= net_tune_hz_eth;
        net_hz_sync <= net_hz_meta;
        net_phase_meta <= net_phase_eth;
        net_phase_sync <= net_phase_meta;
        key_sync_0 <= key_n[2:0];
        key_sync_1 <= key_sync_0;
        if (rf_rst) begin
            key_divider <= 0; key_previous <= 3'b111;
            key0_hold <= 0; key1_hold <= 0;
            net_toggle_seen <= net_toggle_sync;
            phase_increment <= INITIAL_PHASE_INC;
            tuned_hz <= 96_800_000;
        end else begin
            key_divider <= key_divider + 1'b1;
            if (key_divider == 0) begin
                key_previous <= key_sync_1;
                key0_hold <= key_sync_1[0] ? 0 : key0_hold + (key0_hold != 8'hff);
                key1_hold <= key_sync_1[1] ? 0 : key1_hold + (key1_hold != 8'hff);
                if (!key_sync_1[0] &&
                    (key_previous[0] || (key0_hold >= 8'd60 && key0_hold[3:0] == 0)) &&
                    phase_increment > MIN_PHASE_INC) begin
                    phase_increment <= phase_increment - TUNE_STEP_INC;
                    tuned_hz <= tuned_hz - 100_000;
                end
                if (!key_sync_1[1] &&
                    (key_previous[1] || (key1_hold >= 8'd60 && key1_hold[3:0] == 0)) &&
                    phase_increment < MAX_PHASE_INC) begin
                    phase_increment <= phase_increment + TUNE_STEP_INC;
                    tuned_hz <= tuned_hz + 100_000;
                end
            end
            if (net_toggle_sync != net_toggle_seen) begin
                net_toggle_seen <= net_toggle_sync;
                if (net_hz_sync >= 32'd88_000_000 && net_hz_sync <= 32'd108_000_000) begin
                    phase_increment <= net_phase_sync;
                    tuned_hz <= net_hz_sync;
                end
            end
        end
    end

    wire mixer_valid;
    wire signed [15:0] mix_i0, mix_q0, mix_i1, mix_q1;
    nco_mixer_2x mixer (
        .clk(clk_rf), .rst(rf_rst), .valid_in(!rf_rst),
        .rf_bit_0(rf_sample_0), .rf_bit_1(rf_sample_1), .phase_increment,
        .valid_out(mixer_valid), .i_0(mix_i0), .q_0(mix_q0), .i_1(mix_i1), .q_1(mix_q1)
    );

    wire iq_valid;
    wire signed [23:0] cic_i, cic_q;
    cic3_decimator_2x rf_decimator (
        .clk(clk_rf), .rst(rf_rst), .valid_in(mixer_valid),
        .i_0(mix_i0), .q_0(mix_q0), .i_1(mix_i1), .q_1(mix_q1),
        .valid_out(iq_valid), .i_out(cic_i), .q_out(cic_q)
    );

    wire channel_valid;
    wire signed [23:0] channel_i, channel_q;
    complex_fir channel_filter (
        .clk(clk_rf), .rst(rf_rst), .valid_in(iq_valid), .i_in(cic_i), .q_in(cic_q),
        .valid_out(channel_valid), .i_out(channel_i), .q_out(channel_q)
    );

    // Channel-envelope telemetry for distinguishing a captured FM carrier
    // from discriminator threshold noise.  Values are average and peak
    // |I|+|Q| over 256 channel samples, both scaled down by 512.
    wire [23:0] channel_abs_i = channel_i[23] ? (~channel_i + 1'b1) : channel_i;
    wire [23:0] channel_abs_q = channel_q[23] ? (~channel_q + 1'b1) : channel_q;
    wire [24:0] channel_mag_now = {1'b0, channel_abs_i} + {1'b0, channel_abs_q};
    logic [7:0] channel_stat_count;
    logic [32:0] channel_mag_acc;
    logic [24:0] channel_mag_peak;
    logic [31:0] channel_stats_hold;
    wire [32:0] channel_mag_acc_next = channel_mag_acc + channel_mag_now;
    always_ff @(posedge clk_rf) begin
        if (rf_rst) begin
            channel_stat_count <= 0;
            channel_mag_acc <= 0;
            channel_mag_peak <= 0;
            channel_stats_hold <= 0;
        end else if (channel_valid) begin
            if (channel_stat_count == 8'hff) begin
                channel_stats_hold[31:16] <= channel_mag_acc_next[32] ?
                    16'hffff : {1'b0, channel_mag_acc_next[31:17]};
                channel_stats_hold[15:0] <= (channel_mag_now > channel_mag_peak ?
                    channel_mag_now : channel_mag_peak) >> 9;
                channel_stat_count <= 0;
                channel_mag_acc <= 0;
                channel_mag_peak <= 0;
            end else begin
                channel_stat_count <= channel_stat_count + 1'b1;
                channel_mag_acc <= channel_mag_acc_next;
                if (channel_mag_now > channel_mag_peak)
                    channel_mag_peak <= channel_mag_now;
            end
        end
    end

    wire discriminator_valid;
    wire signed [31:0] phase_q28;
    fm_discriminator discriminator (
        .clk(clk_rf), .rst(rf_rst), .valid_in(channel_valid),
        .i_in(channel_i), .q_in(channel_q), .valid_out(discriminator_valid), .phase_q28
    );

    wire pcm_valid_rf, pcm_clipped_rf;
    wire signed [15:0] pcm_rf;
    audio_post audio (
        .clk(clk_rf), .rst(rf_rst), .valid_in(discriminator_valid), .sample_in(phase_q28),
        .mute(!key_sync_1[2]), .valid_out(pcm_valid_rf), .pcm_out(pcm_rf), .clipped(pcm_clipped_rf)
    );

    // Sparse event CDC: data is held stable before the toggle reaches clk_eth.
    logic signed [15:0] pcm_hold_rf;
    logic clip_hold_rf, pcm_toggle_rf, audio_activity;
    always_ff @(posedge clk_rf) begin
        if (rf_rst) begin
            pcm_hold_rf <= 0; clip_hold_rf <= 0; pcm_toggle_rf <= 0; audio_activity <= 0;
        end else if (pcm_valid_rf) begin
            pcm_hold_rf <= pcm_rf; clip_hold_rf <= pcm_clipped_rf;
            pcm_toggle_rf <= ~pcm_toggle_rf; audio_activity <= ~audio_activity;
        end
    end

    (* ASYNC_REG = "TRUE" *) logic pcm_toggle_meta, pcm_toggle_sync;
    logic pcm_toggle_seen;
    (* ASYNC_REG = "TRUE" *) logic signed [15:0] pcm_meta, pcm_sync;
    (* ASYNC_REG = "TRUE" *) logic clip_meta, clip_sync;
    (* ASYNC_REG = "TRUE" *) logic [31:0] tune_meta, tune_sync;
    (* ASYNC_REG = "TRUE" *) logic [31:0] stats_meta, stats_sync;
    (* ASYNC_REG = "TRUE" *) logic [31:0] channel_stats_meta, channel_stats_sync;
    (* ASYNC_REG = "TRUE" *) logic [31:0] raw_overflow_meta, raw_overflow_sync;
    logic pcm_valid_eth;
    always_ff @(posedge clk_eth) begin
        pcm_toggle_meta <= pcm_toggle_rf; pcm_toggle_sync <= pcm_toggle_meta;
        pcm_meta <= pcm_hold_rf; pcm_sync <= pcm_meta;
        clip_meta <= clip_hold_rf; clip_sync <= clip_meta;
        tune_meta <= tuned_hz; tune_sync <= tune_meta;
        stats_meta <= rf_stats_hold; stats_sync <= stats_meta;
        channel_stats_meta <= channel_stats_hold; channel_stats_sync <= channel_stats_meta;
        raw_overflow_meta <= raw_overflow_rf; raw_overflow_sync <= raw_overflow_meta;
        if (eth_rst) begin pcm_toggle_seen <= pcm_toggle_sync; pcm_valid_eth <= 0; end
        else begin
            pcm_valid_eth <= (pcm_toggle_sync != pcm_toggle_seen);
            if (pcm_toggle_sync != pcm_toggle_seen)
                pcm_toggle_seen <= pcm_toggle_sync;
        end
    end

    wire [7:0] audio_frame_byte, raw_frame_byte, eth_frame_byte;
    wire audio_frame_valid, audio_frame_ready, audio_frame_last;
    wire raw_frame_valid, raw_frame_ready, raw_frame_last;
    wire eth_frame_valid, eth_frame_ready, eth_frame_last;
    wire [31:0] packet_count, dropped_samples;
    udp_audio_axis_tx packetizer (
        .clk(clk_eth), .rst(eth_rst || tx_bypass_mode),
        .sample_valid(pcm_valid_eth), .sample(pcm_sync), .sample_clipped(clip_sync),
        .tuned_hz(tune_sync), .rf_stats(stats_sync), .rx_debug(net_rx_debug),
        .channel_stats(channel_stats_sync), .axis_data(audio_frame_byte),
        .axis_valid(audio_frame_valid), .axis_ready(audio_frame_ready),
        .axis_last(audio_frame_last),
        .active(audio_tx_active), .packet_count, .dropped_samples
    );

    wire [31:0] raw_packet_count;
    udp_raw_axis_tx raw_packetizer (
        .clk(clk_eth), .rst(eth_rst || !tx_bypass_mode), .enable(tx_bypass_mode),
        .tuned_hz(tune_sync), .overflow_bytes(raw_overflow_sync),
        .fifo_data(raw_fifo_data), .fifo_empty(raw_fifo_empty),
        .fifo_count(raw_fifo_count), .fifo_rd_en(raw_fifo_rd_en),
        .axis_data(raw_frame_byte), .axis_valid(raw_frame_valid),
        .axis_ready(raw_frame_ready), .axis_last(raw_frame_last),
        .active(raw_tx_active), .packet_count(raw_packet_count)
    );

    assign eth_frame_byte = tx_bypass_mode ? raw_frame_byte : audio_frame_byte;
    assign eth_frame_valid = tx_bypass_mode ? raw_frame_valid : audio_frame_valid;
    assign eth_frame_last = tx_bypass_mode ? raw_frame_last : audio_frame_last;
    assign raw_frame_ready = tx_bypass_mode && eth_frame_ready;
    assign audio_frame_ready = !tx_bypass_mode && eth_frame_ready;

    wire [7:0] gmii_txd;
    wire gmii_tx_en, gmii_tx_er;
    axis_gmii_tx #(.ENABLE_PADDING(1), .MIN_FRAME_LENGTH(64)) mac_tx (
        .clk(clk_eth), .rst(eth_rst),
        .s_axis_tdata(eth_frame_byte), .s_axis_tvalid(eth_frame_valid),
        .s_axis_tready(eth_frame_ready), .s_axis_tlast(eth_frame_last),
        .s_axis_tuser(1'b0), .gmii_txd(gmii_txd),
        .gmii_tx_en(gmii_tx_en), .gmii_tx_er(gmii_tx_er),
        .ptp_ts(96'd0), .m_axis_ptp_ts(), .m_axis_ptp_ts_tag(),
        .m_axis_ptp_ts_valid(), .clk_enable(1'b1), .mii_select(1'b0),
        .cfg_ifg(8'd12), .cfg_tx_enable(1'b1),
        .start_packet(), .error_underflow()
    );
    rgmii_tx rgmii (
        .clk(clk_eth), .clk90(clk_eth), .tx_byte(gmii_txd), .tx_valid(gmii_tx_en),
        .rgmii_tx_clk(eth_tx_clk), .rgmii_txd(eth_tx_data), .rgmii_tx_ctl(eth_tx_ctl)
    );

    assign led = {audio_tx_active || raw_tx_active, tx_bypass_mode, !eth_rst, rf_locked};
endmodule
