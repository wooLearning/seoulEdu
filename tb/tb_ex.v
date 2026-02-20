/*
[TB_INFO_START]
Name: tb_ex
Target: ex
Role: Testbench for Example Module
Scenario:
  - Exhaustive 2-bit input combination test (00, 01, 10, 11)
CheckPoint:
  - Verifies AND gate truth table
  - Generates VCD for waveform inspection
[TB_INFO_END]
*/
`timescale 1ns/1ps
module tb_ex;
reg  i_a;
reg  i_b;
wire o_y;
ex dut (
    .i_a(i_a),
    .i_b(i_b),
    .o_y(o_y)
);
initial begin
    $dumpfile("tb_ex.vcd");
    $dumpvars(0, tb_ex);
    // @WAVE: i_a, i_b, o_y
    // @RUNTIME BEGIN : 0ns
    i_a = 0; i_b = 0; #10;
    i_a = 0; i_b = 1; #10;
    i_a = 1; i_b = 0; #10;
    i_a = 1; i_b = 1; #10;
    // @RUNTIME END : 40ns
    $finish;
end
endmodule
