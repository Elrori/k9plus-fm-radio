module nco_mixer_2x (
    input  logic                    clk,
    input  logic                    rst,
    input  logic                    valid_in,
    input  logic                    rf_bit_0,
    input  logic                    rf_bit_1,
    input  logic [31:0]             phase_increment,
    output logic                    valid_out,
    output logic signed [15:0]      i_0,
    output logic signed [15:0]      q_0,
    output logic signed [15:0]      i_1,
    output logic signed [15:0]      q_1
);
    logic [31:0] phase, phase_1;
    (* rom_style = "block" *) logic signed [15:0] rom_sin0 [0:1023];
    (* rom_style = "block" *) logic signed [15:0] rom_cos0 [0:1023];
    (* rom_style = "block" *) logic signed [15:0] rom_sin1 [0:1023];
    (* rom_style = "block" *) logic signed [15:0] rom_cos1 [0:1023];
    logic signed [15:0] sin0_pipe, cos0_pipe, sin1_pipe, cos1_pipe;
    logic bit0_pipe, bit1_pipe, rom_valid;
    logic [9:0] addr0, addr1;

    initial begin
        $readmemh("mem/sine_q15_1024.mem", rom_sin0);
        $readmemh("mem/sine_q15_1024.mem", rom_cos0);
        $readmemh("mem/sine_q15_1024.mem", rom_sin1);
        $readmemh("mem/sine_q15_1024.mem", rom_cos1);
    end

    always_comb begin
        phase_1 = phase + phase_increment;
        addr0 = phase[31:22];
        addr1 = phase_1[31:22];
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            phase <= 0; rom_valid <= 0; valid_out <= 0;
            bit0_pipe <= 0; bit1_pipe <= 0;
            sin0_pipe <= 0; cos0_pipe <= 0; sin1_pipe <= 0; cos1_pipe <= 0;
            i_0 <= 0; q_0 <= 0; i_1 <= 0; q_1 <= 0;
        end else begin
            valid_out <= rom_valid;
            if (rom_valid) begin
                i_0 <= bit0_pipe ? cos0_pipe : -cos0_pipe;
                q_0 <= bit0_pipe ? -sin0_pipe : sin0_pipe;
                i_1 <= bit1_pipe ? cos1_pipe : -cos1_pipe;
                q_1 <= bit1_pipe ? -sin1_pipe : sin1_pipe;
            end
            rom_valid <= valid_in;
            if (valid_in) begin
                sin0_pipe <= rom_sin0[addr0];
                cos0_pipe <= rom_cos0[addr0 + 10'd256];
                sin1_pipe <= rom_sin1[addr1];
                cos1_pipe <= rom_cos1[addr1 + 10'd256];
                bit0_pipe <= rf_bit_0;
                bit1_pipe <= rf_bit_1;
                phase <= phase + (phase_increment << 1);
            end
        end
    end
endmodule
