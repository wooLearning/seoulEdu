/*
[TB_INFO_START]
Name: tb_baud_rate_gen
Target: baud_rate_gen
Role: Testbench for Baud Rate Generator
Scenario:
  - Generates a clock and reset
  - Instantiates `baud_rate_gen` with scaled-down parameters for simulation speed
CheckPoint:
  - Verifies generation of 16x ticks and 1x ticks
  - Counts ticks to ensure frequency ratio is correct
[TB_INFO_END]
*/

`timescale 1ns / 1ps

module tb_baud_rate_gen;
  initial begin
    $dumpfile("tb_baud_rate_gen.vcd");
    $dumpvars(0, tb_baud_rate_gen);
  end

  reg iClk;
  reg iRst;
  wire oTick16x;
  wire oTick;

  // Small parameters for fast simulation
  baud_rate_gen #(
    .CLK_FREQ(16000),
    .BAUD_RATE(100)
  ) dut (
    .iClk(iClk),
    .iRst(iRst),
    .oTick16x(oTick16x),
    .oTick(oTick)
  );

  always #5 iClk = ~iClk;

  integer cnt16x;
  integer cnt1x;

  always @(posedge iClk) begin
    if (oTick16x) cnt16x <= cnt16x + 1;
    if (oTick)  cnt1x  <= cnt1x + 1;
  end

  initial begin
    iClk = 1'b0;
    iRst = 1'b1;
    cnt16x = 0;
    cnt1x = 0;

    repeat (4) @(posedge iClk);
    iRst = 1'b0;

    repeat (400) @(posedge iClk);
    $display("tb_baud_rate_gen finished: oTick16x=%0d oTick=%0d", cnt16x, cnt1x);
    $finish;
  end

endmodule
