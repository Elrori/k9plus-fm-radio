module eth_diag_top (
    input  wire        eth_rx_clk,
    output wire        eth_tx_clk,
    output wire [3:0]  eth_tx_data,
    output wire        eth_tx_ctl,
    output wire        eth1_tx_clk,
    output wire [3:0]  eth1_tx_data,
    output wire        eth1_tx_ctl,
    output wire [1:0]  led
);
    wire clk_in;
    wire clk_mmcm;
    wire clk90_mmcm;
    wire clk;
    wire clk90;
    wire clk_feedback;
    wire clock_locked;
    IBUF rx_clock_input (.I(eth_rx_clk), .O(clk_in));
    MMCME2_BASE #(
        .CLKIN1_PERIOD(8.0),
        .CLKFBOUT_MULT_F(8.0),
        .DIVCLK_DIVIDE(1),
        .CLKOUT0_DIVIDE_F(8.0),
        .CLKOUT1_DIVIDE(8),
        .CLKOUT1_PHASE(90.0)
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

    logic [11:0] sample_divider;
    logic signed [15:0] ramp;
    logic sample_valid;
    always_ff @(posedge clk) begin
        sample_valid <= 1'b0;
        if (reset_pipe[7]) begin
            sample_divider <= 0;
            ramp <= -16'sd16000;
        end else if (sample_divider == 12'd2603) begin
            sample_divider <= 0;
            ramp <= ramp + 16'sd125;
            sample_valid <= 1'b1;
        end else begin
            sample_divider <= sample_divider + 1'b1;
        end
    end

    wire [7:0] tx_byte;
    wire tx_valid, active;
    wire [31:0] packet_count, dropped_samples;
    udp_audio_tx packetizer (
        .clk(clk), .rst(reset_pipe[7]), .sample_valid(sample_valid),
        .sample(ramp), .sample_clipped(1'b0), .tuned_hz(32'd100_100_000),
        .tx_byte(tx_byte), .tx_valid(tx_valid), .active(active),
        .packet_count(packet_count), .dropped_samples(dropped_samples)
    );

    rgmii_tx phy0 (
        .clk(clk), .clk90(clk90), .tx_byte(tx_byte), .tx_valid(tx_valid),
        .rgmii_tx_clk(eth_tx_clk), .rgmii_txd(eth_tx_data),
        .rgmii_tx_ctl(eth_tx_ctl)
    );
    rgmii_tx phy1 (
        .clk(clk), .clk90(clk90), .tx_byte(tx_byte), .tx_valid(tx_valid),
        .rgmii_tx_clk(eth1_tx_clk), .rgmii_txd(eth1_tx_data),
        .rgmii_tx_ctl(eth1_tx_ctl)
    );

    assign led = {active, ~reset_pipe[7]};
endmodule
