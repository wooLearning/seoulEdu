/*
[MODULE_INFO_START]
Name: watch_top
Role: Watch System Top-Level Wrapper
Summary:
  - Wraps `clock_core` (Digital Time) and `stopwatch` (Stopwatch + Memory)
  - Muxes display output between Clock and Stopwatch based on Mode Switch (`iSw0`)
  - Manages blinking logic for Edit Mode visualization
  - Routes physical button events to the active core
[MODULE_INFO_END]
*/

`timescale 1ns / 1ps

module watch_top (
  input        iClk,
  input        iRst,
  input        iTick100Hz,

  // Switches
  input        iSw0, // 0: Stopwatch, 1: Clock
  input        iSw1, // 0: Sec.Centisec, 1: Hour.Min

  // Edge inputs
  input        iBtnCEdge,
  input        iBtnREdge,
  input        iBtnLEdge,
  input        iBtnUEdge,
  input        iBtnDEdge,

  // Display data/mask
  output [13:0] oDispData,
  output [3:0]  oBlinkMask,

  // Current selected time (used by UART report)
  output [6:0] oCurrentHour,
  output [6:0] oCurrentMin,
  output [6:0] oCurrentSec,
  output [6:0] oCurrentCenti
);

  wire [6:0] wClockHour;
  wire [6:0] wClockMin;
  wire [6:0] wClockSec;
  wire [6:0] wClockCenti;

  wire [6:0] wStopHour;
  wire [6:0] wStopMin;
  wire [6:0] wStopSec;
  wire [6:0] wStopCenti;

  wire [6:0] wDispHour;
  wire [6:0] wDispMin;
  wire [6:0] wDispSec;
  wire [6:0] wDispCenti;

  wire [1:0] wEditState;

  // Clock core is active only when iSw0=1 (clock mode)
  clock_core u_clock_core (
    .iClk(iClk),
    .iRst(iRst),
    .iTick(iTick100Hz),
    .iBtnRunStop(iSw0 ? iBtnCEdge : 1'b0),
    .iBtnInc(iSw0 ? iBtnUEdge : 1'b0),
    .iBtnDec(iSw0 ? iBtnDEdge : 1'b0),
    .iBtnLeft(iSw0 ? iBtnLEdge : 1'b0),
    .iBtnRight(iSw0 ? iBtnREdge : 1'b0),
    .oHour(wClockHour),
    .oMin(wClockMin),
    .oSec(wClockSec),
    .oCentisec(wClockCenti),
    .oEditState(wEditState)
  );

  wire        wMemWE;
  wire [4:0]  wMemAddr;
  wire [27:0] wMemWData;
  wire [27:0] wMemRData;
  wire        wStopwatchMemEn;

  // Stopwatch core is active only when iSw0=0 (stopwatch mode)
  stopwatch u_stopwatch (
    .iClk(iClk),
    .iClk100HzEn(iTick100Hz),
    .iRst(iRst),
    .iRunStop(!iSw0 ? iBtnCEdge : 1'b0),
    .iClear(!iSw0 ? iBtnUEdge : 1'b0),
    .iRecordNext(!iSw0 ? iBtnREdge : 1'b0),
    .iRecordPrev(!iSw0 ? iBtnLEdge : 1'b0),
    .oHour(wStopHour),
    .oMin(wStopMin),
    .oSec(wStopSec),
    .oCentisec(wStopCenti),
    .oMemWE(wMemWE),
    .oMemAddr(wMemAddr),
    .oMemWData(wMemWData),
    .iMemRData(wMemRData),
    .oMemEn(wStopwatchMemEn)
  );

  stopwatch_mem u_stopwatch_mem (
    .iClk(iClk),
    .iWE(wMemWE & wStopwatchMemEn),
    .iAddr(wMemAddr),
    .iWData(wMemWData),
    .oRData(wMemRData)
  );

  assign wDispHour  = iSw0 ? wClockHour  : wStopHour;
  assign wDispMin   = iSw0 ? wClockMin   : wStopMin;
  assign wDispSec   = iSw0 ? wClockSec   : wStopSec;
  assign wDispCenti = iSw0 ? wClockCenti : wStopCenti;

  assign oDispData = iSw1 ? {wDispHour, wDispMin} : {wDispSec, wDispCenti};

  reg [25:0] rBlinkCnt;
  wire wBlinkState = rBlinkCnt[25];

  always @(posedge iClk or posedge iRst) begin
    if (iRst) rBlinkCnt <= 26'd0;
    else      rBlinkCnt <= rBlinkCnt + 1'b1;
  end

  reg [3:0] rBlinkMask;
  always @(*) begin
    rBlinkMask = 4'b0000;

    // Clock edit blinking only when iSw0=1 and blink phase is OFF
    if (iSw0 && wBlinkState) begin
      case (wEditState)
        2'd1: if (!iSw1) rBlinkMask = 4'b1100; // sec edit in sec:cs view
        2'd2: if ( iSw1) rBlinkMask = 4'b0011; // min edit in hour:min view
        2'd3: if ( iSw1) rBlinkMask = 4'b1100; // hour edit in hour:min view
        default: rBlinkMask = 4'b0000;
      endcase
    end
  end

  assign oBlinkMask = rBlinkMask;

  assign oCurrentHour  = iSw0 ? wClockHour  : wStopHour;
  assign oCurrentMin   = iSw0 ? wClockMin   : wStopMin;
  assign oCurrentSec   = iSw0 ? wClockSec   : wStopSec;
  assign oCurrentCenti = iSw0 ? wClockCenti : wStopCenti;

endmodule



