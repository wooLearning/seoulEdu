/*
[MODULE_INFO_START]
Name: control_unit
Role: Central Control & Input Policy Manager
Summary:
  - Merges physical button inputs and UART command inputs (virtual buttons)
  - Manages system modes: Watch Mode (Stopwatch/Clock) vs Sensor Mode (SR04/DHT11)
  - Handles toggle switches for display formats and active sensor selection
  - Routes effective control signals to Watch, Sensor Controllers, and UART Reporter
  - Implements priority logic for display bridging
[MODULE_INFO_END]
*/

`timescale 1ns / 1ps

module control_unit (
  input  wire      iClk,
  input  wire      iRst,

  // Physical inputs
  input  wire      iSw0,
  input  wire      iSw1,
  input  wire      iSw2,
  input  wire      iSw3,
  input  wire      iPhysBtnC,
  input  wire      iPhysBtnU,
  input  wire      iPhysBtnD,
  input  wire      iPhysBtnL,
  input  wire      iPhysBtnR,

  // Decoder outputs
  input  wire      iDecBtnC,
  input  wire      iDecBtnU,
  input  wire      iDecBtnD,
  input  wire      iDecBtnL,
  input  wire      iDecBtnR,
  input  wire      iDecTglSw0,   // Toggle request for sw0
  input  wire      iDecTglSw1,   // Toggle request for sw1
  input  wire      iDecTglSw2,   // Toggle request for sw2
  input  wire      iDecTglSw3,   // Toggle request for sw3
  input  wire      iDecClrSwTgl, // Clear toggle register
  input  wire      iDecReqWatchRpt,  // Watch report request pulse
  input  wire      iDecReqSr04Rpt,   // SR04 report request pulse
  input  wire      iDecReqTempRpt,   // DHT11 temperature report request pulse
  input  wire      iDecReqHumRpt,    // DHT11 humidity report request pulse

  // Effective outputs
  output wire      oWatchMode,                // Effective mode after override mux
  output wire      oWatchDisplay,             // Effective watch display format after override mux
  output wire [1:0] oDisplaySelect,           // Effective FND source after override mux
  output wire      oBtnC,
  output wire      oBtnU,
  output wire      oBtnD,
  output wire      oBtnL,
  output wire      oBtnR,
  output wire      oReqWatchRpt,              // To uart_ascii_sender
  output wire      oReqSr04Rpt,               // To uart_ascii_sender
  output wire      oReqTempRpt,               // To uart_ascii_sender
  output wire      oReqHumRpt,                // To uart_ascii_sender
  output wire      oSr04Start,                // Sensor start pulse routed to SR04
  output wire      oDht11Start                // Sensor start pulse routed to DHT11
);

  reg  [3:0] rSwTgl;
  wire [3:0] wSwEff;
  wire      wSw2Eff;
  wire      wSw3Eff;

  always @(posedge iClk or posedge iRst) begin
    if (iRst) begin
      rSwTgl <= 4'b0000;
    end else begin
      if (iDecClrSwTgl) rSwTgl <= 4'b0000;
      else begin
        if (iDecTglSw0) rSwTgl[0] <= ~rSwTgl[0];
        if (iDecTglSw1) rSwTgl[1] <= ~rSwTgl[1];
        if (iDecTglSw2) rSwTgl[2] <= ~rSwTgl[2];
        if (iDecTglSw3) rSwTgl[3] <= ~rSwTgl[3];
      end
    end
  end

  assign wSwEff = {iSw3, iSw2, iSw1, iSw0} ^ rSwTgl;
  assign oWatchMode    = wSwEff[0];
  assign oWatchDisplay = wSwEff[1];
  assign wSw2Eff       = wSwEff[2];
  assign wSw3Eff       = wSwEff[3];

  // Display policy:
  // sw2=0 -> watch
  // sw2=1, sw3=0 -> SR04
  // sw2=1, sw3=1 -> DHT11
  assign oDisplaySelect = (!wSw2Eff) ? 2'b00 :
                          (!wSw3Eff) ? 2'b01 : 2'b10;

  assign oBtnC = iPhysBtnC | iDecBtnC;
  assign oBtnU = iPhysBtnU | iDecBtnU;
  assign oBtnD = iPhysBtnD | iDecBtnD;
  assign oBtnL = iPhysBtnL | iDecBtnL;
  assign oBtnR = iPhysBtnR | iDecBtnR;

  assign oReqWatchRpt = iDecReqWatchRpt;
  assign oReqSr04Rpt  = iDecReqSr04Rpt;
  assign oReqTempRpt  = iDecReqTempRpt;
  assign oReqHumRpt   = iDecReqHumRpt;
  // Unified sensor trigger policy:
  // - Start is generated only by C button input (physical or UART button emulation).
  // - Trigger target depends on active display source.
  //   01: SR04, 10: DHT11.
  assign oSr04Start  = (iPhysBtnC | iDecBtnC) && (oDisplaySelect == 2'b01);
  assign oDht11Start = (iPhysBtnC | iDecBtnC) && (oDisplaySelect == 2'b10);

endmodule
