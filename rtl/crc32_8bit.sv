`timescale 1ns/1ps
module crc32_8bit (
    input  wire [31:0] crc_in,
    input  wire [7:0]  data,
    output wire [31:0] crc_out
);
    assign crc_out[0] = crc_in[2] ^ crc_in[8] ^ data[2];
    assign crc_out[1] = crc_in[0] ^ crc_in[3] ^ crc_in[9] ^ data[0] ^ data[3];
    assign crc_out[2] = crc_in[0] ^ crc_in[1] ^ crc_in[4] ^ crc_in[10] ^ data[0] ^ data[1] ^ data[4];
    assign crc_out[3] = crc_in[1] ^ crc_in[2] ^ crc_in[5] ^ crc_in[11] ^ data[1] ^ data[2] ^ data[5];
    assign crc_out[4] = crc_in[0] ^ crc_in[2] ^ crc_in[3] ^ crc_in[6] ^ crc_in[12] ^ data[0] ^ data[2] ^ data[3] ^ data[6];
    assign crc_out[5] = crc_in[1] ^ crc_in[3] ^ crc_in[4] ^ crc_in[7] ^ crc_in[13] ^ data[1] ^ data[3] ^ data[4] ^ data[7];
    assign crc_out[6] = crc_in[4] ^ crc_in[5] ^ crc_in[14] ^ data[4] ^ data[5];
    assign crc_out[7] = crc_in[0] ^ crc_in[5] ^ crc_in[6] ^ crc_in[15] ^ data[0] ^ data[5] ^ data[6];
    assign crc_out[8] = crc_in[1] ^ crc_in[6] ^ crc_in[7] ^ crc_in[16] ^ data[1] ^ data[6] ^ data[7];
    assign crc_out[9] = crc_in[7] ^ crc_in[17] ^ data[7];
    assign crc_out[10] = crc_in[2] ^ crc_in[18] ^ data[2];
    assign crc_out[11] = crc_in[3] ^ crc_in[19] ^ data[3];
    assign crc_out[12] = crc_in[0] ^ crc_in[4] ^ crc_in[20] ^ data[0] ^ data[4];
    assign crc_out[13] = crc_in[0] ^ crc_in[1] ^ crc_in[5] ^ crc_in[21] ^ data[0] ^ data[1] ^ data[5];
    assign crc_out[14] = crc_in[1] ^ crc_in[2] ^ crc_in[6] ^ crc_in[22] ^ data[1] ^ data[2] ^ data[6];
    assign crc_out[15] = crc_in[2] ^ crc_in[3] ^ crc_in[7] ^ crc_in[23] ^ data[2] ^ data[3] ^ data[7];
    assign crc_out[16] = crc_in[0] ^ crc_in[2] ^ crc_in[3] ^ crc_in[4] ^ crc_in[24] ^ data[0] ^ data[2] ^ data[3] ^ data[4];
    assign crc_out[17] = crc_in[0] ^ crc_in[1] ^ crc_in[3] ^ crc_in[4] ^ crc_in[5] ^ crc_in[25] ^ data[0] ^ data[1] ^ data[3] ^ data[4] ^ data[5];
    assign crc_out[18] = crc_in[0] ^ crc_in[1] ^ crc_in[2] ^ crc_in[4] ^ crc_in[5] ^ crc_in[6] ^ crc_in[26] ^ data[0] ^ data[1] ^ data[2] ^ data[4] ^ data[5] ^ data[6];
    assign crc_out[19] = crc_in[1] ^ crc_in[2] ^ crc_in[3] ^ crc_in[5] ^ crc_in[6] ^ crc_in[7] ^ crc_in[27] ^ data[1] ^ data[2] ^ data[3] ^ data[5] ^ data[6] ^ data[7];
    assign crc_out[20] = crc_in[3] ^ crc_in[4] ^ crc_in[6] ^ crc_in[7] ^ crc_in[28] ^ data[3] ^ data[4] ^ data[6] ^ data[7];
    assign crc_out[21] = crc_in[2] ^ crc_in[4] ^ crc_in[5] ^ crc_in[7] ^ crc_in[29] ^ data[2] ^ data[4] ^ data[5] ^ data[7];
    assign crc_out[22] = crc_in[2] ^ crc_in[3] ^ crc_in[5] ^ crc_in[6] ^ crc_in[30] ^ data[2] ^ data[3] ^ data[5] ^ data[6];
    assign crc_out[23] = crc_in[3] ^ crc_in[4] ^ crc_in[6] ^ crc_in[7] ^ crc_in[31] ^ data[3] ^ data[4] ^ data[6] ^ data[7];
    assign crc_out[24] = crc_in[0] ^ crc_in[2] ^ crc_in[4] ^ crc_in[5] ^ crc_in[7] ^ data[0] ^ data[2] ^ data[4] ^ data[5] ^ data[7];
    assign crc_out[25] = crc_in[0] ^ crc_in[1] ^ crc_in[2] ^ crc_in[3] ^ crc_in[5] ^ crc_in[6] ^ data[0] ^ data[1] ^ data[2] ^ data[3] ^ data[5] ^ data[6];
    assign crc_out[26] = crc_in[0] ^ crc_in[1] ^ crc_in[2] ^ crc_in[3] ^ crc_in[4] ^ crc_in[6] ^ crc_in[7] ^ data[0] ^ data[1] ^ data[2] ^ data[3] ^ data[4] ^ data[6] ^ data[7];
    assign crc_out[27] = crc_in[1] ^ crc_in[3] ^ crc_in[4] ^ crc_in[5] ^ crc_in[7] ^ data[1] ^ data[3] ^ data[4] ^ data[5] ^ data[7];
    assign crc_out[28] = crc_in[0] ^ crc_in[4] ^ crc_in[5] ^ crc_in[6] ^ data[0] ^ data[4] ^ data[5] ^ data[6];
    assign crc_out[29] = crc_in[0] ^ crc_in[1] ^ crc_in[5] ^ crc_in[6] ^ crc_in[7] ^ data[0] ^ data[1] ^ data[5] ^ data[6] ^ data[7];
    assign crc_out[30] = crc_in[0] ^ crc_in[1] ^ crc_in[6] ^ crc_in[7] ^ data[0] ^ data[1] ^ data[6] ^ data[7];
    assign crc_out[31] = crc_in[1] ^ crc_in[7] ^ data[1] ^ data[7];
endmodule
