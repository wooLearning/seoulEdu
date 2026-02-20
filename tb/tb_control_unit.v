/*
[TB_INFO_START]
Name: tb_control_unit
Target: control_unit
Role: Testbench for Central Control Unit
Scenario:
  - Simulates physical switches and buttons
  - Simulates UART decoder pulses (virtual inputs)
  - Tasks: `pulse_tgl_sw`, `pulse_clr_tgl`
CheckPoint:
  - verifies Mode switching logic (Clock vs Stopwatch)
  - Verifies Display routing (Watch vs SR04 vs DHT11)
  - Verifies sensor trigger routing (SR04/DHT11)
[TB_INFO_END]
*/

`timescale 1ns / 1ps

module tb_control_unit;
  initial begin
    $dumpfile("tb_control_unit.vcd");
    $dumpvars(0, tb_control_unit);
  end

  reg iClk;
  reg iRst;

  reg iSw0, iSw1, iSw2, iSw3;
  reg iPhysBtnC, iPhysBtnU, iPhysBtnD, iPhysBtnL, iPhysBtnR;
  reg iDecBtnC, iDecBtnU, iDecBtnD, iDecBtnL, iDecBtnR;
  reg iDecTglSw0, iDecTglSw1, iDecTglSw2, iDecTglSw3, iDecClrSwTgl;
  reg iDecReqWatchRpt, iDecReqSr04Rpt, iDecReqTempRpt, iDecReqHumRpt;

  wire oWatchMode, oWatchDisplay;
  wire [1:0] oDisplaySelect;
  wire oBtnC, oBtnU, oBtnD, oBtnL, oBtnR;
  wire oReqWatchRpt, oReqSr04Rpt, oReqTempRpt, oReqHumRpt, oSr04Start, oDht11Start;

  control_unit dut (
    .iClk(iClk),
    .iRst(iRst),
    .iSw0(iSw0),
    .iSw1(iSw1),
    .iSw2(iSw2),
    .iSw3(iSw3),
    .iPhysBtnC(iPhysBtnC),
    .iPhysBtnU(iPhysBtnU),
    .iPhysBtnD(iPhysBtnD),
    .iPhysBtnL(iPhysBtnL),
    .iPhysBtnR(iPhysBtnR),
    .iDecBtnC(iDecBtnC),
    .iDecBtnU(iDecBtnU),
    .iDecBtnD(iDecBtnD),
    .iDecBtnL(iDecBtnL),
    .iDecBtnR(iDecBtnR),
    .iDecTglSw0(iDecTglSw0),
    .iDecTglSw1(iDecTglSw1),
    .iDecTglSw2(iDecTglSw2),
    .iDecTglSw3(iDecTglSw3),
    .iDecClrSwTgl(iDecClrSwTgl),
    .iDecReqWatchRpt(iDecReqWatchRpt),
    .iDecReqSr04Rpt(iDecReqSr04Rpt),
    .iDecReqTempRpt(iDecReqTempRpt),
    .iDecReqHumRpt(iDecReqHumRpt),
    .oWatchMode(oWatchMode),
    .oWatchDisplay(oWatchDisplay),
    .oDisplaySelect(oDisplaySelect),
    .oBtnC(oBtnC),
    .oBtnU(oBtnU),
    .oBtnD(oBtnD),
    .oBtnL(oBtnL),
    .oBtnR(oBtnR),
    .oReqWatchRpt(oReqWatchRpt),
    .oReqSr04Rpt(oReqSr04Rpt),
    .oReqTempRpt(oReqTempRpt),
    .oReqHumRpt(oReqHumRpt),
    .oSr04Start(oSr04Start),
    .oDht11Start(oDht11Start)
  );

  always #5 iClk = ~iClk;

  task clear_decoder_pulses;
    begin
      iDecBtnC = 1'b0;
      iDecBtnU = 1'b0;
      iDecBtnD = 1'b0;
      iDecBtnL = 1'b0;
      iDecBtnR = 1'b0;
      iDecTglSw0 = 1'b0;
      iDecTglSw1 = 1'b0;
      iDecTglSw2 = 1'b0;
      iDecTglSw3 = 1'b0;
      iDecClrSwTgl = 1'b0;
      iDecReqWatchRpt = 1'b0;
      iDecReqSr04Rpt = 1'b0;
      iDecReqTempRpt = 1'b0;
      iDecReqHumRpt = 1'b0;
    end
  endtask

  task pulse_tgl_sw0;
    begin
      @(posedge iClk);
      iDecTglSw0 <= 1'b1;
      @(posedge iClk);
      iDecTglSw0 <= 1'b0;
    end
  endtask

  task pulse_tgl_sw1;
    begin
      @(posedge iClk);
      iDecTglSw1 <= 1'b1;
      @(posedge iClk);
      iDecTglSw1 <= 1'b0;
    end
  endtask

  task pulse_tgl_sw2;
    begin
      @(posedge iClk);
      iDecTglSw2 <= 1'b1;
      @(posedge iClk);
      iDecTglSw2 <= 1'b0;
    end
  endtask

  task pulse_tgl_sw3;
    begin
      @(posedge iClk);
      iDecTglSw3 <= 1'b1;
      @(posedge iClk);
      iDecTglSw3 <= 1'b0;
    end
  endtask

  task pulse_clr_tgl;
    begin
      @(posedge iClk);
      iDecClrSwTgl <= 1'b1;
      @(posedge iClk);
      iDecClrSwTgl <= 1'b0;
    end
  endtask

  initial begin
    iClk = 1'b0;
    iRst = 1'b1;

    iSw0 = 1'b0;
    iSw1 = 1'b1;
    iSw2 = 1'b1;
    iSw3 = 1'b0; // physical default -> sr04

    iPhysBtnC = 1'b0;
    iPhysBtnU = 1'b0;
    iPhysBtnD = 1'b0;
    iPhysBtnL = 1'b0;
    iPhysBtnR = 1'b0;

    clear_decoder_pulses();

    repeat (4) @(posedge iClk);
    iRst = 1'b0;

    // Default path uses physical switches.
    #1;
    if (oWatchMode !== iSw0) begin
      $display("oWatchMode default mismatch");
      $finish;
    end
    if (oWatchDisplay !== iSw1) begin
      $display("oWatchDisplay default mismatch");
      $finish;
    end
    if (oDisplaySelect !== ((!iSw2) ? 2'b00 : ((!iSw3) ? 2'b01 : 2'b10))) begin
      $display("oDisplaySelect default mismatch");
      $finish;
    end

    // Toggle sw0 once -> watch mode should invert.
    pulse_tgl_sw0();
    #1;
    if (oWatchMode !== ~iSw0) begin
      $display("oWatchMode toggle mismatch");
      $finish;
    end

    // Toggle sw1 once -> watch display should invert.
    pulse_tgl_sw1();
    #1;
    if (oWatchDisplay !== ~iSw1) begin
      $display("oWatchDisplay toggle mismatch");
      $finish;
    end

    // Toggle sw2 once: sensor->watch group switch.
    pulse_tgl_sw2();
    #1;
    if (oDisplaySelect !== 2'b00) begin
      $display("oDisplaySelect sw2-toggle mismatch");
      $finish;
    end

    // Toggle sw2 again: back to sensor group (with sw3=0 -> sr04).
    pulse_tgl_sw2();
    #1;
    if (oDisplaySelect !== 2'b01) begin
      $display("oDisplaySelect sw2-toggle-back mismatch");
      $finish;
    end

    // Button merge check (separate path check, no simultaneous assert).
    @(posedge iClk);
    iDecBtnU  <= 1'b1;
    #1;
    if (oBtnU !== 1'b1) begin
      $display("oBtnU decoder path mismatch");
      $finish;
    end
    @(posedge iClk);
    iDecBtnU  <= 1'b0;

    @(posedge iClk);
    iPhysBtnC <= 1'b1;
    #1;
    if (oBtnC !== 1'b1) begin
      $display("oBtnC physical path mismatch");
      $finish;
    end
    @(posedge iClk);
    iPhysBtnC <= 1'b0;

    // Trigger route check in sr04 display.
    @(posedge iClk);
    iDecBtnC <= 1'b1;
    #1;
    if (oSr04Start !== 1'b1) begin
      $display("sr04 start should assert in sr04 display");
      $finish;
    end
    if (oDht11Start !== 1'b0) begin
      $display("dht11 start should stay low in sr04 display");
      $finish;
    end
    @(posedge iClk);
    iDecBtnC <= 1'b0;

    // Toggle sw3 once: sr04 -> dht11.
    pulse_tgl_sw3();
    #1;
    if (oDisplaySelect !== 2'b10) begin
      $display("oDisplaySelect sw3-toggle mismatch");
      $finish;
    end

    // Trigger route check in dht11 display.
    @(posedge iClk);
    iDecBtnC <= 1'b1;
    #1;
    if (oSr04Start !== 1'b0) begin
      $display("sr04 start should stay low in dht11 display");
      $finish;
    end
    if (oDht11Start !== 1'b1) begin
      $display("dht11 start should assert in dht11 display");
      $finish;
    end
    @(posedge iClk);
    iDecBtnC <= 1'b0;

    // Report request pass-through check.
    @(posedge iClk);
    iDecReqWatchRpt <= 1'b1;
    iDecReqSr04Rpt  <= 1'b1;
    iDecReqTempRpt  <= 1'b1;
    iDecReqHumRpt   <= 1'b1;
    #1;
    if (!oReqWatchRpt || !oReqSr04Rpt || !oReqTempRpt || !oReqHumRpt) begin
      $display("report request pass-through mismatch");
      $finish;
    end
    @(posedge iClk);
    clear_decoder_pulses();

    // Clear toggles and return to physical switches.
    pulse_clr_tgl();
    #1;
    if (oWatchMode !== iSw0) begin
      $display("oWatchMode clear mismatch");
      $finish;
    end
    if (oWatchDisplay !== iSw1) begin
      $display("oWatchDisplay clear mismatch");
      $finish;
    end
    if (oDisplaySelect !== ((!iSw2) ? 2'b00 : ((!iSw3) ? 2'b01 : 2'b10))) begin
      $display("oDisplaySelect clear mismatch");
      $finish;
    end

    repeat (8) @(posedge iClk);
    $display("tb_control_unit finished");
    $finish;
  end

endmodule
