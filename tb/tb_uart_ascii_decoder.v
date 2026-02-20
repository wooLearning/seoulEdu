/*
[TB_INFO_START]
Name: tb_uart_ascii_decoder
Target: uart_ascii_decoder
Role: Testbench for ASCII Command Decoder
Scenario:
  - Sends various ASCII characters via `send_byte_expect` task
CheckPoint:
  - Verifies mapping of characters to control pulses (e.g., 'c' -> BtnC)
  - Checks latching/clearing of toggle signals
  - Verifies pass-through for loopback data
[TB_INFO_END]
*/

`timescale 1ns / 1ps

module tb_uart_ascii_decoder;
  // initial begin
  //   $dumpfile("tb_uart_ascii_decoder.vcd");
  //   $dumpvars(0, tb_uart_ascii_decoder);
  // end

  reg        iClk;
  reg        iRst;
  reg  [7:0] iRxData;
  reg        iRxValid;

  wire oBtnC, oBtnU, oBtnD, oBtnL, oBtnR;
  wire oTglSw0, oTglSw1, oTglSw2, oTglSw3, oClrSwTgl;
  wire oReqWatchRpt, oReqSr04Rpt, oReqTempRpt, oReqHumRpt;
  wire [7:0] oLoopData;
  wire oLoopValid;
  wire [13:0] wPulseBus;

  localparam [13:0] EXP_BTN_C         = 14'b10000000000000;
  localparam [13:0] EXP_BTN_U         = 14'b01000000000000;
  localparam [13:0] EXP_BTN_D         = 14'b00100000000000;
  localparam [13:0] EXP_BTN_L         = 14'b00010000000000;
  localparam [13:0] EXP_BTN_R         = 14'b00001000000000;
  localparam [13:0] EXP_TGL_SW0       = 14'b00000100000000;
  localparam [13:0] EXP_TGL_SW1       = 14'b00000010000000;
  localparam [13:0] EXP_TGL_SW2       = 14'b00000001000000;
  localparam [13:0] EXP_TGL_SW3       = 14'b00000000100000;
  localparam [13:0] EXP_CLR_SW_TGL    = 14'b00000000010000;
  localparam [13:0] EXP_REQ_WATCH_RPT = 14'b00000000001000;
  localparam [13:0] EXP_REQ_SR04_RPT  = 14'b00000000000100;
  localparam [13:0] EXP_REQ_TEMP_RPT  = 14'b00000000000010;
  localparam [13:0] EXP_REQ_HUM_RPT   = 14'b00000000000001;

  assign wPulseBus = {
    oBtnC, oBtnU, oBtnD, oBtnL, oBtnR,
    oTglSw0, oTglSw1, oTglSw2, oTglSw3, oClrSwTgl,
    oReqWatchRpt, oReqSr04Rpt, oReqTempRpt, oReqHumRpt
  };

  uart_ascii_decoder dut (
    .iClk(iClk),
    .iRst(iRst),
    .iRxData(iRxData),
    .iRxValid(iRxValid),
    .oBtnC(oBtnC),
    .oBtnU(oBtnU),
    .oBtnD(oBtnD),
    .oBtnL(oBtnL),
    .oBtnR(oBtnR),
    .oTglSw0(oTglSw0),
    .oTglSw1(oTglSw1),
    .oTglSw2(oTglSw2),
    .oTglSw3(oTglSw3),
    .oClrSwTgl(oClrSwTgl),
    .oReqWatchRpt(oReqWatchRpt),
    .oReqSr04Rpt(oReqSr04Rpt),
    .oReqTempRpt(oReqTempRpt),
    .oReqHumRpt(oReqHumRpt),
    .oLoopData(oLoopData),
    .oLoopValid(oLoopValid)
  );

  always #5 iClk = ~iClk;

  task send_byte_expect(
    input [7:0] ch,
    input [13:0] exp_pulse_bus
  );
    begin
      @(posedge iClk);
      iRxData  <= ch;
      iRxValid <= 1'b1;
      @(posedge iClk);
      #1;

      if (wPulseBus !== exp_pulse_bus) begin
        $display("pulse bus mismatch for '%c' exp=%014b act=%014b", ch, exp_pulse_bus, wPulseBus);
        $finish;
      end

      if (oLoopValid !== 1'b1) begin
        $display("oLoopValid mismatch for '%c'", ch);
        $finish;
      end
      if (oLoopData !== ch) begin
        $display("oLoopData mismatch for '%c'", ch);
        $finish;
      end

      @(posedge iClk);
      iRxValid <= 1'b0;
      iRxData  <= 8'd0;

      // Pulse outputs must clear on the next cycle.
      @(posedge iClk);
      #1;
      if (oBtnC || oBtnU || oBtnD || oBtnL || oBtnR) begin
        $display("button pulse not cleared after '%c'", ch);
        $finish;
      end
      if (oTglSw0 || oTglSw1 || oTglSw2 || oTglSw3 || oClrSwTgl) begin
        $display("toggle pulse not cleared after '%c'", ch);
        $finish;
      end
      if (oReqWatchRpt || oReqSr04Rpt || oReqTempRpt || oReqHumRpt) begin
        $display("report pulse not cleared after '%c'", ch);
        $finish;
      end
    end
  endtask

  initial begin
    iClk = 1'b0;
    iRst = 1'b1;
    iRxData = 8'd0;
    iRxValid = 1'b0;

    repeat (4) @(posedge iClk);
    iRst = 1'b0;
    send_byte_expect("c", EXP_BTN_C);//63
    send_byte_expect("u", EXP_BTN_U);//75
    send_byte_expect("d", EXP_BTN_D);//75
    send_byte_expect("l", EXP_BTN_L);//75
    send_byte_expect("r", EXP_BTN_R);//75
    send_byte_expect("1", EXP_TGL_SW0);
    send_byte_expect("3", EXP_TGL_SW1);
    send_byte_expect("5", EXP_TGL_SW2);
    send_byte_expect("6", EXP_TGL_SW3);
    send_byte_expect("w", EXP_REQ_WATCH_RPT);//77
    send_byte_expect("s", EXP_REQ_SR04_RPT);//73  
    send_byte_expect("t", EXP_REQ_TEMP_RPT);//74
    send_byte_expect("h", EXP_REQ_HUM_RPT);//68
    send_byte_expect("x", EXP_CLR_SW_TGL);//78

    repeat (10) @(posedge iClk);
    $display("tb_uart_ascii_decoder finished");
    $finish;
  end

endmodule
