module clock_gen (
    input  wire clk_25m,
    output wire clk_rf,
    output wire clk_eth,
    output wire rf_locked,
    output wire eth_locked
);
    wire rf_clk_unbuf, rf_fb_unbuf, rf_fb;
    wire eth_clk_unbuf, eth_fb_unbuf, eth_fb;

    // 25 MHz -> 120 MHz, VCO = 1200 MHz.
    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKIN1_PERIOD(40.0),
        .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(48.0),
        .CLKOUT0_DIVIDE_F(10.0)
    ) rf_mmcm (
        .CLKIN1(clk_25m), .CLKFBIN(rf_fb), .RST(1'b0), .PWRDWN(1'b0),
        .CLKFBOUT(rf_fb_unbuf), .CLKOUT0(rf_clk_unbuf), .LOCKED(rf_locked)
    );
    BUFG rf_fb_buf (.I(rf_fb_unbuf), .O(rf_fb));
    BUFG rf_clk_buf (.I(rf_clk_unbuf), .O(clk_rf));

    // 25 MHz -> 200 MHz reference for the RGMII IDELAYCTRL, VCO = 1000 MHz.
    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKIN1_PERIOD(40.0),
        .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(40.0),
        .CLKOUT0_DIVIDE_F(5.0)
    ) eth_mmcm (
        .CLKIN1(clk_25m), .CLKFBIN(eth_fb), .RST(1'b0), .PWRDWN(1'b0),
        .CLKFBOUT(eth_fb_unbuf), .CLKOUT0(eth_clk_unbuf), .LOCKED(eth_locked)
    );
    BUFG eth_fb_buf (.I(eth_fb_unbuf), .O(eth_fb));
    BUFG eth_clk_buf (.I(eth_clk_unbuf), .O(clk_eth));
endmodule
