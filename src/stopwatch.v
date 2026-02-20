/*
[MODULE_INFO_START]
Name: stopwatch
Role: Stopwatch Logic Core with Memory
Summary:
  - Timekeeping logic for precise stopwatch function (Hour, Min, Sec, Centisec)
  - Features: Run/Stop, Clear/Reset, and Lap Record functionality
  - Maintains a 30-slot memory (`stopwatch_mem`) for lap times
  - Allows reviewing stored lap records via Next/Prev buttons
StateDescription:
  - IDLE: Reset state (00:00:00:00)
  - RUN: Time counting active
  - STOP: Time counting paused
  - CLEAR: Clearing internal registers and memory (sequential erase)
[MODULE_INFO_END]
*/

`timescale 1ns / 1ps

module stopwatch (
  input        iClk,
  input        iClk100HzEn,
  input        iRst,
  input        iRunStop,
  input        iClear,
  input        iRecordNext,
  input        iRecordPrev,
  output reg [6:0] oHour,
  output reg [6:0] oMin,
  output reg [6:0] oSec,
  output reg [6:0] oCentisec,
  output            oMemWE,
  output [4:0]      oMemAddr,
  output [27:0]     oMemWData,
  input  [27:0]     iMemRData,
  output            oMemEn
);

  localparam [1:0] IDLE  = 2'b00;
  localparam [1:0] RUN   = 2'b01;
  localparam [1:0] STOP  = 2'b10;
  localparam [1:0] CLEAR = 2'b11;

  localparam integer LP_MEM_DEPTH = 30;

  reg [1:0] rCurState;
  reg [1:0] rNxtState;

  reg [6:0] rHour;
  reg [6:0] rMin;
  reg [6:0] rSec;
  reg [6:0] rCentisec;

  reg [27:0] rMemWData;
  reg        rMemWE;
  reg [4:0]  rMemAddr;

  reg [4:0] rRecordWrAddr;
  reg [4:0] rRecordRdAddr;
  reg [5:0] rRecordCount; // 0..30
  reg       rViewingRecord;
  reg [5:0] rClearCnt;

  // ---------------------------------------------------------------------------
  // State register
  // ---------------------------------------------------------------------------
  always @(posedge iClk or posedge iRst) begin
    if (iRst) rCurState <= IDLE;
    else      rCurState <= rNxtState;
  end

  // ---------------------------------------------------------------------------
  // Next-state logic
  // ---------------------------------------------------------------------------
  always @(*) begin
    case (rCurState)
      IDLE: begin
        if (iClear)         rNxtState = CLEAR;
        else if (iRunStop)  rNxtState = RUN;
        else                rNxtState = IDLE;
      end

      RUN: begin
        if (iClear)         rNxtState = CLEAR;
        else if (iRunStop)  rNxtState = STOP;
        else                rNxtState = RUN;
      end

      STOP: begin
        if (iClear)         rNxtState = CLEAR;
        else if (iRunStop)  rNxtState = RUN;
        else                rNxtState = STOP;
      end

      CLEAR: begin
        if (rClearCnt >= LP_MEM_DEPTH) rNxtState = IDLE;
        else                           rNxtState = CLEAR;
      end

      default: rNxtState = IDLE;
    endcase
  end

  // ---------------------------------------------------------------------------
  // Counter datapath
  // ---------------------------------------------------------------------------
  always @(posedge iClk or posedge iRst) begin
    if (iRst) begin
      rHour     <= 7'd0;
      rMin      <= 7'd0;
      rSec      <= 7'd0;
      rCentisec <= 7'd0;
    end else if (iClk100HzEn) begin
      case (rCurState)
        IDLE: begin
          rHour     <= 7'd0;
          rMin      <= 7'd0;
          rSec      <= 7'd0;
          rCentisec <= 7'd0;
        end

        RUN: begin
          if (rCentisec >= 99) begin
            rCentisec <= 0;
            if (rSec >= 59) begin
              rSec <= 0;
              if (rMin >= 59) begin
                rMin <= 0;
                if (rHour >= 99) rHour <= 0;
                else             rHour <= rHour + 1'b1;
              end else begin
                rMin <= rMin + 1'b1;
              end
            end else begin
              rSec <= rSec + 1'b1;
            end
          end else begin
            rCentisec <= rCentisec + 1'b1;
          end
        end

        CLEAR: begin
          rHour     <= 7'd0;
          rMin      <= 7'd0;
          rSec      <= 7'd0;
          rCentisec <= 7'd0;
        end

        default: begin
          rHour     <= rHour;
          rMin      <= rMin;
          rSec      <= rSec;
          rCentisec <= rCentisec;
        end
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  // Memory interface control
  // ---------------------------------------------------------------------------
  always @(*) begin
    rMemWE    = 1'b0;
    rMemAddr  = rRecordRdAddr;
    rMemWData = 28'd0;

    // Lap write on RUN -> STOP transition
    if ((rCurState == RUN) && (rNxtState == STOP) && (rRecordCount < LP_MEM_DEPTH)) begin
      rMemWE    = 1'b1;
      rMemAddr  = rRecordWrAddr;
      rMemWData = {rHour, rMin, rSec, rCentisec};
    end
    // Clear memory
    else if ((rCurState == CLEAR) && (rClearCnt < LP_MEM_DEPTH)) begin
      rMemWE    = 1'b1;
      rMemAddr  = rClearCnt[4:0];
      rMemWData = 28'd0;
    end
  end

  // ---------------------------------------------------------------------------
  // Write pointer / record count
  // ---------------------------------------------------------------------------
  always @(posedge iClk or posedge iRst) begin
    if (iRst) begin
      rRecordWrAddr <= 5'd0;
      rRecordCount  <= 6'd0;
    end else if ((rCurState == CLEAR) || iClear) begin
      rRecordWrAddr <= 5'd0;
      rRecordCount  <= 6'd0;
    end else if ((rCurState == RUN) && (rNxtState == STOP) && (rRecordCount < LP_MEM_DEPTH)) begin
      if (rRecordWrAddr < LP_MEM_DEPTH - 1) rRecordWrAddr <= rRecordWrAddr + 1'b1;
      else                                  rRecordWrAddr <= rRecordWrAddr;
      rRecordCount <= rRecordCount + 1'b1;
    end
  end

  // ---------------------------------------------------------------------------
  // Record viewer navigation
  // ---------------------------------------------------------------------------
  always @(posedge iClk or posedge iRst) begin
    if (iRst) begin
      rRecordRdAddr  <= 5'd0;
      rViewingRecord <= 1'b0;
    end else if (rCurState == CLEAR) begin
      rRecordRdAddr  <= 5'd0;
      rViewingRecord <= 1'b0;
    end else if ((rCurState == RUN) || iRunStop) begin
      rViewingRecord <= 1'b0;
    end else if (rCurState == STOP) begin
      if (iRecordNext) begin
        if (!rViewingRecord && (rRecordCount > 0)) begin
          rRecordRdAddr  <= 5'd0;
          rViewingRecord <= 1'b1;
        end else if (rViewingRecord && (rRecordRdAddr + 1 < rRecordCount)) begin
          rRecordRdAddr <= rRecordRdAddr + 1'b1;
        end
      end else if (iRecordPrev && rViewingRecord) begin
        if (rRecordRdAddr > 0) rRecordRdAddr <= rRecordRdAddr - 1'b1;
        else                   rViewingRecord <= 1'b0;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Clear counter
  // ---------------------------------------------------------------------------
  always @(posedge iClk or posedge iRst) begin
    if (iRst) begin
      rClearCnt <= 6'd0;
    end else if (rCurState == CLEAR) begin
      if (rClearCnt < LP_MEM_DEPTH) rClearCnt <= rClearCnt + 1'b1;
      else                          rClearCnt <= rClearCnt;
    end else begin
      rClearCnt <= 6'd0;
    end
  end

  // ---------------------------------------------------------------------------
  // Display output mux
  // ---------------------------------------------------------------------------
  wire [27:0] wRecordData = iMemRData;

  always @(*) begin
    if (rCurState == CLEAR) begin
      oHour     = 7'd99;
      oMin      = 7'd99;
      oSec      = 7'd99;
      oCentisec = 7'd99;
    end else if (rViewingRecord && (rRecordCount > 0)) begin
      oHour     = wRecordData[27:21];
      oMin      = wRecordData[20:14];
      oSec      = wRecordData[13:7];
      oCentisec = wRecordData[6:0];
    end else begin
      oHour     = rHour;
      oMin      = rMin;
      oSec      = rSec;
      oCentisec = rCentisec;
    end
  end

  assign oMemWE    = rMemWE;
  assign oMemAddr  = rMemAddr;
  assign oMemWData = rMemWData;
  assign oMemEn    = (rCurState == RUN) || (rCurState == STOP) || (rCurState == CLEAR);

endmodule




