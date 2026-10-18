module rgmii_tune_rx (
    input  wire        phy_clk,
    input  wire        idelay_refclk,
    input  wire        idelay_rst,
    input  wire        rst,
    input  wire [3:0]  rgmii_rxd,
    input  wire        rgmii_rx_ctl,
    output wire        clk,
    output logic [31:0] tune_hz,
    output logic [31:0] phase_increment,
    output logic        tune_toggle,
    output logic        bypass_mode,
    output logic [31:0] debug_status
);
    wire [4:0] ddr_q1, ddr_q2;
    wire [4:0] rgmii_input = {rgmii_rxd, rgmii_rx_ctl};
    wire [4:0] rgmii_delayed;
    assign clk = phy_clk;

    // XI050CD/K9+ board reference uses 12 fixed IDELAY taps on all five RGMII
    // receive pins.  At 200 MHz calibration this is about 0.94 ns and centers
    // the eye before the DDR input registers.
    IDELAYCTRL idelay_control (.REFCLK(idelay_refclk), .RST(idelay_rst), .RDY());
    genvar n;
    generate
        for (n = 0; n < 5; n = n + 1) begin : rx_delay_and_ddr
            IDELAYE2 #(
                .CINVCTRL_SEL("FALSE"), .DELAY_SRC("IDATAIN"),
                .HIGH_PERFORMANCE_MODE("TRUE"), .IDELAY_TYPE("FIXED"),
                .IDELAY_VALUE(12), .PIPE_SEL("FALSE"),
                .REFCLK_FREQUENCY(200.0), .SIGNAL_PATTERN("DATA")
            ) input_delay (
                .DATAOUT(rgmii_delayed[n]), .DATAIN(1'b0), .C(phy_clk),
                .CE(1'b0), .INC(1'b0), .IDATAIN(rgmii_input[n]),
                .CNTVALUEIN(5'd0), .CNTVALUEOUT(), .LD(1'b0),
                .LDPIPEEN(1'b0), .REGRST(1'b0), .CINVCTRL(1'b0)
            );
            IDDR #(.DDR_CLK_EDGE("SAME_EDGE_PIPELINED"), .SRTYPE("ASYNC")) input_ddr (
                .C(phy_clk), .CE(1'b1), .D(rgmii_delayed[n]), .R(1'b0), .S(1'b0),
                .Q1(ddr_q1[n]), .Q2(ddr_q2[n])
            );
        end
    endgenerate

    wire [7:0] gmii_rxd = {ddr_q2[4:1], ddr_q1[4:1]};
    wire gmii_rx_dv = ddr_q1[0];

    logic preamble_seen, in_frame;
    logic [7:0] byte_index;
    logic valid_ethertype, valid_protocol, valid_port, valid_magic;
    logic [31:0] pending_hz, pending_phase;
    logic gmii_rx_dv_previous;
    logic [31:0] magic_window;
    logic [3:0] command_index;
    logic command_active, command_is_mode;

    always_ff @(posedge clk) begin
        if (rst) begin
            preamble_seen <= 0;
            in_frame <= 0;
            byte_index <= 0;
            valid_ethertype <= 0;
            valid_protocol <= 0;
            valid_port <= 0;
            valid_magic <= 0;
            pending_hz <= 0;
            pending_phase <= 0;
            tune_hz <= 0;
            phase_increment <= 0;
            tune_toggle <= 0;
            bypass_mode <= 0;
            debug_status <= 0;
            gmii_rx_dv_previous <= 0;
            magic_window <= 0;
            command_index <= 0;
            command_active <= 0;
            command_is_mode <= 0;
        end else if (!gmii_rx_dv) begin
            gmii_rx_dv_previous <= 0;
            preamble_seen <= 0;
            in_frame <= 0;
            magic_window <= 0;
            command_active <= 0;
        end else if (!in_frame) begin
            gmii_rx_dv_previous <= 1;
            debug_status[31:24] <= gmii_rxd;
            debug_status[8] <= 1'b1;
            if (!gmii_rx_dv_previous)
                debug_status[7:0] <= debug_status[7:0] + (debug_status[7:0] != 8'hff);
            if (gmii_rxd == 8'h55) begin
                preamble_seen <= 1;
                debug_status[9] <= 1'b1;
            end else if (preamble_seen && gmii_rxd == 8'hd5) begin
                in_frame <= 1;
                byte_index <= 0;
                debug_status[10] <= 1'b1;
                valid_ethertype <= 1;
                valid_protocol <= 1;
                valid_port <= 1;
                valid_magic <= 1;
            end else begin
                preamble_seen <= 0;
            end
        end else begin
            gmii_rx_dv_previous <= 1;
            debug_status[31:24] <= gmii_rxd;
            magic_window <= {magic_window[23:0], gmii_rxd};
            if (byte_index > debug_status[23:16])
                debug_status[23:16] <= byte_index;
            // Search for the application marker instead of depending on fixed
            // IPv4 header offsets.  This also accepts future VLAN/IP-options
            // frames and lets repeated commands recover from a bad frame.
            if ({magic_window[23:0], gmii_rxd} == 32'h4b395455) begin
                command_active <= 1;
                command_is_mode <= 0;
                command_index <= 0;
                debug_status[14] <= 1'b1;
            end else if ({magic_window[23:0], gmii_rxd} == 32'h4b394d44) begin
                command_active <= 1;
                command_is_mode <= 1;
                command_index <= 0;
                debug_status[16] <= 1'b1;
            end else if (command_active) begin
                if (command_is_mode) begin
                    bypass_mode <= gmii_rxd[0];
                    command_active <= 0;
                    debug_status[17] <= 1'b1;
                end else case (command_index)
                    0: pending_hz[7:0] <= gmii_rxd;
                    1: pending_hz[15:8] <= gmii_rxd;
                    2: pending_hz[23:16] <= gmii_rxd;
                    3: pending_hz[31:24] <= gmii_rxd;
                    4: pending_phase[7:0] <= gmii_rxd;
                    5: pending_phase[15:8] <= gmii_rxd;
                    6: pending_phase[23:16] <= gmii_rxd;
                    7: begin
                        pending_phase[31:24] <= gmii_rxd;
                        command_active <= 0;
                        tune_hz <= pending_hz;
                        phase_increment <= {gmii_rxd, pending_phase[23:0]};
                        tune_toggle <= ~tune_toggle;
                        debug_status[15] <= 1'b1;
                    end
                    default: command_active <= 0;
                endcase
                command_index <= command_index + 1'b1;
            end
            case (byte_index)
                8'd12: begin valid_ethertype <= valid_ethertype && gmii_rxd == 8'h08; if (gmii_rxd == 8'h08) debug_status[11] <= 1'b1; end
                8'd13: begin valid_ethertype <= valid_ethertype && gmii_rxd == 8'h00; if (valid_ethertype && gmii_rxd == 8'h00) debug_status[12] <= 1'b1; end
                8'd23: begin valid_protocol <= valid_protocol && gmii_rxd == 8'h11; if (gmii_rxd == 8'h11) debug_status[13] <= 1'b1; end
                8'd36: valid_port <= valid_port && gmii_rxd == 8'hc3;
                8'd37: valid_port <= valid_port && gmii_rxd == 8'h51;
                8'd42: valid_magic <= valid_magic && gmii_rxd == 8'h4b;
                8'd43: valid_magic <= valid_magic && gmii_rxd == 8'h39;
                8'd44: valid_magic <= valid_magic && gmii_rxd == 8'h54;
                8'd45: valid_magic <= valid_magic && gmii_rxd == 8'h55;
                8'd46: pending_hz[7:0] <= gmii_rxd;
                8'd47: pending_hz[15:8] <= gmii_rxd;
                8'd48: pending_hz[23:16] <= gmii_rxd;
                8'd49: pending_hz[31:24] <= gmii_rxd;
                8'd50: pending_phase[7:0] <= gmii_rxd;
                8'd51: pending_phase[15:8] <= gmii_rxd;
                8'd52: pending_phase[23:16] <= gmii_rxd;
                8'd53: begin
                    pending_phase[31:24] <= gmii_rxd;
                    if (valid_ethertype && valid_protocol && valid_port && valid_magic) begin
                        tune_hz <= pending_hz;
                        phase_increment <= {gmii_rxd, pending_phase[23:0]};
                        tune_toggle <= ~tune_toggle;
                    end
                end
                default: begin end
            endcase
            byte_index <= byte_index + 1'b1;
        end
    end
endmodule
