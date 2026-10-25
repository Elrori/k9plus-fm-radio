`timescale 1ns/1ps
module tb_wide_fir;
    logic clk=0,rst=1,valid_in=0;
    logic signed [23:0] i_in=0,q_in=0;
    wire valid_out;
    wire signed [23:0] i_out,q_out;
    reg [47:0] inputs[0:1023], expected[0:511];
    integer received=0;
    always #4 clk=~clk;
    wide_fir_dec2 dut(.*);
    always @(negedge clk) if(valid_out) begin
        if(received>=512 || {q_out,i_out} !== expected[received])
            $fatal(1,"sample %0d got=%h expected=%h",received,{q_out,i_out},expected[received]);
        received=received+1;
    end
    initial begin
        $readmemh("input.mem",inputs); $readmemh("expected.mem",expected);
        repeat(5) @(negedge clk); rst=0;
        for(integer n=0;n<1024;n=n+1) begin
            @(negedge clk); {q_in,i_in}=inputs[n];valid_in=1;
            @(negedge clk);valid_in=0;
            repeat(8+(n%3)) @(negedge clk);
        end
        repeat(20) @(negedge clk);
        if(received!=512) $fatal(1,"missing outputs: %0d",received);
        $display("WIDE_FIR_PASS 512 independent convolution vectors, impulse/random/fullscale/gaps");
        $finish;
    end
endmodule
