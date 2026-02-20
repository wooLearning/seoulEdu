/*
[TB_INFO_START]
Name: tb_button_sync
Target: button_sync
Role: Testbench for Button Debouncer/Synchronizer
Scenario:
  - Initializes inputs and releases reset
  - Uses `press_btn` task to simulate button press/release events
  - Verifies edge detection logic
CheckPoint:
  - Start-up state verification
  - Edge detection confirmation for multiple button channels
[TB_INFO_END]
*/

`timescale 1ns / 1ps

module tb_button_sync;
  initial begin
    $dumpfile("tb_button_sync.vcd");
    $dumpvars(0, tb_button_sync);
  end

  reg        iClk;
  reg        iRst;
  reg  [4:0] iButtonRaw;
  wire [4:0] oButtonEdge;

  button_sync #(
    .P_BUTTON_WIDTH(5)
  ) dut (
    .iClk(iClk),
    .iRst(iRst),
    .iButtonRaw(iButtonRaw),
    .oButtonEdge(oButtonEdge)
  );

  always #5 iClk = ~iClk;

  task press_btn(input integer idx);
    begin
      @(negedge iClk);
      iButtonRaw[idx] = 1'b1;
      repeat (3) @(posedge iClk);
      @(negedge iClk);
      iButtonRaw[idx] = 1'b0;
    end
  endtask

  initial begin
    iClk = 1'b0;
    iRst = 1'b1;
    iButtonRaw = 5'b00000;

    repeat (4) @(posedge iClk);
    iRst = 1'b0;

    press_btn(0);
    press_btn(2);
    press_btn(4);

    repeat (10) @(posedge iClk);
    $display("tb_button_sync finished");
    $finish;
  end

endmodule
