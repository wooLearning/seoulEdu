/*
[MODULE_INFO_START]
Name: uart_ascii_sender
Role: UART ASCII Response Generator & Multiplexer
Summary:
  - Serializes system state and measurement data into ASCII strings for transmission
  - Handles Loopback, Watch Time ("WATCH HH:MM:SS"), SR04 Distance ("SR04 xxx cm"), and DHT11 Data ("TEMP xx C", "HUM xx %")
  - Arbitrates between multiple report requests
  - Uses internal functions to convert binary values to ASCII digits
StateDescription:
  - ST_IDLE: Wait for report request or loopback data
  - ST_LOAD_DATA: Prepare next character from active source
  - ST_ASSERT: Assert Data Valid when TX path can accept push
[MODULE_INFO_END]
*/

`timescale 1ns / 1ps

module uart_ascii_sender (
  input  wire       iClk,
  input  wire       iRst,
  input  wire       iTxFifoFull, // TX FIFO backpressure (1: block push, 0: accept push)
  output reg  [7:0] oTxData,
  output reg        oTxPushValid,

  // Loopback input
  input  wire [7:0] iLoopData,
  input  wire       iLoopValid,

  // Report requests
  input  wire       iReqWatchReport,
  input  wire       iReqSr04Report,
  input  wire       iReqTempReport,
  input  wire       iReqHumReport,

  // Snapshot sources
  input  wire [6:0] iWatchHour,
  input  wire [6:0] iWatchMin,
  input  wire [6:0] iWatchSec,
  input  wire [9:0] iSr04DistanceCm,
  input  wire       iSr04DistanceValid,
  input  wire [7:0] iDhtHumInt,
  input  wire [7:0] iDhtTempInt,
  input  wire       iDhtDataValid
);

  localparam [2:0] ST_IDLE      = 3'd0;
  localparam [2:0] ST_LOAD_DATA = 3'd1;
  localparam [2:0] ST_ASSERT    = 3'd2;

  localparam [2:0] SRC_LOOP  = 3'd0;
  localparam [2:0] SRC_WATCH = 3'd1;
  localparam [2:0] SRC_SR04  = 3'd2;
  localparam [2:0] SRC_TEMP  = 3'd3;
  localparam [2:0] SRC_HUM   = 3'd4;

  reg [2:0] rCurState;
  reg [2:0] rNxtState;
  reg [2:0] rActiveSrc;
  reg [5:0] rCharIdx;
  reg [5:0] rLastIdx;

  reg       rLoopPending;
  reg [7:0] rLoopBuf;
  reg       rWatchPending;
  reg       rSr04Pending;
  reg       rTempPending;
  reg       rHumPending;

  reg [6:0] rSnapHour;
  reg [6:0] rSnapMin;
  reg [6:0] rSnapSec;
  reg [9:0] rSnapSr04Cm;
  reg       rSnapSr04Valid;
  reg [7:0] rSnapDhtHum;
  reg [7:0] rSnapDhtTemp;
  reg       rSnapDhtValid;

  function [7:0] f_ascii_digit;//ascii 30 is 0
    input [3:0] val;
    begin
      f_ascii_digit = 8'h30 + val;
    end
  endfunction

  function [7:0] f_watch_char;
    input [5:0] idx;
    input [6:0] hh;
    input [6:0] mm;
    input [6:0] ss;
    begin
      case (idx)
        0:  f_watch_char = 8'h0D;
        1:  f_watch_char = 8'h0A;
        2:  f_watch_char = "W";
        3:  f_watch_char = "A";
        4:  f_watch_char = "T";
        5:  f_watch_char = "C";
        6:  f_watch_char = "H";
        7:  f_watch_char = " ";
        8:  f_watch_char = f_ascii_digit((hh / 10) % 10);
        9:  f_watch_char = f_ascii_digit(hh % 10);
        10: f_watch_char = ":";
        11: f_watch_char = f_ascii_digit((mm / 10) % 10);
        12: f_watch_char = f_ascii_digit(mm % 10);
        13: f_watch_char = ":";
        14: f_watch_char = f_ascii_digit((ss / 10) % 10);
        15: f_watch_char = f_ascii_digit(ss % 10);
        16: f_watch_char = 8'h0D;
        17: f_watch_char = 8'h0A;
        default: f_watch_char = " ";
      endcase
    end
  endfunction

  function [7:0] f_sr04_char;
    input [5:0] idx;
    input [9:0] cm;
    input       valid;
    reg [3:0] h;
    reg [3:0] t;
    reg [3:0] o;
    begin
      h = (cm / 100) % 10;
      t = (cm / 10) % 10;
      o = cm % 10;
      case (idx)
        0:  f_sr04_char = 8'h0D;
        1:  f_sr04_char = 8'h0A;
        2:  f_sr04_char = "S";
        3:  f_sr04_char = "R";
        4:  f_sr04_char = "0";
        5:  f_sr04_char = "4";
        6:  f_sr04_char = " ";
        7:  f_sr04_char = valid ? f_ascii_digit(h) : "-";
        8:  f_sr04_char = valid ? f_ascii_digit(t) : "-";
        9:  f_sr04_char = valid ? f_ascii_digit(o) : "-";
        10: f_sr04_char = "c";
        11: f_sr04_char = "m";
        12: f_sr04_char = 8'h0D;
        13: f_sr04_char = 8'h0A;
        default: f_sr04_char = " ";
      endcase
    end
  endfunction

  function [7:0] f_temp_char;
    input [5:0] idx;
    input [7:0] temp;
    input       valid;
    reg [3:0] t;
    reg [3:0] o;
    begin
      t = (temp / 10) % 10;
      o = temp % 10;
      case (idx)
        0:  f_temp_char = 8'h0D;
        1:  f_temp_char = 8'h0A;
        2:  f_temp_char = "T";
        3:  f_temp_char = "E";
        4:  f_temp_char = "M";
        5:  f_temp_char = "P";
        6:  f_temp_char = " ";
        7:  f_temp_char = valid ? f_ascii_digit(t) : "-";
        8:  f_temp_char = valid ? f_ascii_digit(o) : "-";
        9:  f_temp_char = "C";
        10: f_temp_char = 8'h0D;
        11: f_temp_char = 8'h0A;
        default: f_temp_char = " ";
      endcase
    end
  endfunction

  function [7:0] f_hum_char;
    input [5:0] idx;
    input [7:0] hum;
    input       valid;
    reg [3:0] t;
    reg [3:0] o;
    begin
      t = (hum / 10) % 10;
      o = hum % 10;
      case (idx)
        0:  f_hum_char = 8'h0D;
        1:  f_hum_char = 8'h0A;
        2:  f_hum_char = "H";
        3:  f_hum_char = "U";
        4:  f_hum_char = "M";
        5:  f_hum_char = " ";
        6:  f_hum_char = valid ? f_ascii_digit(t) : "-";
        7:  f_hum_char = valid ? f_ascii_digit(o) : "-";
        8:  f_hum_char = "%";
        9:  f_hum_char = 8'h0D;
        10: f_hum_char = 8'h0A;
        default: f_hum_char = " ";
      endcase
    end
  endfunction

  always @(*) begin
    rNxtState = rCurState;

    case (rCurState)
      ST_IDLE: begin
        if (rLoopPending || rWatchPending || rSr04Pending || rTempPending || rHumPending) rNxtState = ST_LOAD_DATA;
        else                                                                                rNxtState = ST_IDLE;
      end

      ST_LOAD_DATA: rNxtState = ST_ASSERT;

      ST_ASSERT: begin
        if (!iTxFifoFull) begin
          if (rCharIdx < rLastIdx) rNxtState = ST_LOAD_DATA;
          else                     rNxtState = ST_IDLE;
        end else begin
          rNxtState = ST_ASSERT;
        end
      end

      default: rNxtState = ST_IDLE;
    endcase
  end

  always @(posedge iClk or posedge iRst) begin
    if (iRst) rCurState <= ST_IDLE;
    else      rCurState <= rNxtState;
  end

  always @(posedge iClk or posedge iRst) begin
    if (iRst) begin
      rActiveSrc     <= SRC_LOOP;
      rCharIdx       <= 6'd0;
      rLastIdx       <= 6'd0;
      rLoopPending   <= 1'b0;
      rLoopBuf       <= 8'd0;
      rWatchPending  <= 1'b0;
      rSr04Pending   <= 1'b0;
      rTempPending   <= 1'b0;
      rHumPending    <= 1'b0;
      rSnapHour      <= 7'd0;
      rSnapMin       <= 7'd0;
      rSnapSec       <= 7'd0;
      rSnapSr04Cm    <= 10'd0;
      rSnapSr04Valid <= 1'b0;
      rSnapDhtHum    <= 8'd0;
      rSnapDhtTemp   <= 8'd0;
      rSnapDhtValid  <= 1'b0;
      oTxData        <= 8'd0;
      oTxPushValid   <= 1'b0;
    end else begin
      oTxPushValid <= 1'b0;

      // Latch incoming requests while sender is busy.
      if (iLoopValid) begin
        rLoopPending <= 1'b1;
        rLoopBuf     <= iLoopData;
      end
      if (iReqWatchReport) rWatchPending <= 1'b1;
      if (iReqSr04Report)  rSr04Pending  <= 1'b1;
      if (iReqTempReport)  rTempPending  <= 1'b1;
      if (iReqHumReport)   rHumPending   <= 1'b1;

      case (rCurState)
        ST_IDLE: begin
          if (rLoopPending) begin
            rActiveSrc   <= SRC_LOOP;
            rCharIdx     <= 6'd0;
            rLastIdx     <= 6'd0;
            rLoopPending <= 1'b0;
          end else if (rWatchPending) begin
            rActiveSrc    <= SRC_WATCH;
            rCharIdx      <= 6'd0;
            rLastIdx      <= 6'd17;
            rWatchPending <= 1'b0;
            rSnapHour     <= iWatchHour;
            rSnapMin      <= iWatchMin;
            rSnapSec      <= iWatchSec;
          end else if (rSr04Pending) begin
            rActiveSrc     <= SRC_SR04;
            rCharIdx       <= 6'd0;
            rLastIdx       <= 6'd13;
            rSr04Pending   <= 1'b0;
            rSnapSr04Cm    <= iSr04DistanceCm;
            rSnapSr04Valid <= iSr04DistanceValid;
          end else if (rTempPending) begin
            rActiveSrc    <= SRC_TEMP;
            rCharIdx      <= 6'd0;
            rLastIdx      <= 6'd11;
            rTempPending  <= 1'b0;
            rSnapDhtTemp  <= iDhtTempInt;
            rSnapDhtValid <= iDhtDataValid;
          end else if (rHumPending) begin
            rActiveSrc    <= SRC_HUM;
            rCharIdx      <= 6'd0;
            rLastIdx      <= 6'd10;
            rHumPending   <= 1'b0;
            rSnapDhtHum   <= iDhtHumInt;
            rSnapDhtValid <= iDhtDataValid;
          end
        end

        ST_LOAD_DATA: begin
          case (rActiveSrc)
            SRC_LOOP:  oTxData <= rLoopBuf;
            SRC_WATCH: oTxData <= f_watch_char(rCharIdx, rSnapHour, rSnapMin, rSnapSec);
            SRC_SR04:  oTxData <= f_sr04_char(rCharIdx, rSnapSr04Cm, rSnapSr04Valid);
            SRC_TEMP:  oTxData <= f_temp_char(rCharIdx, rSnapDhtTemp, rSnapDhtValid);
            default:   oTxData <= f_hum_char(rCharIdx, rSnapDhtHum, rSnapDhtValid);
          endcase
        end

        ST_ASSERT: begin
          if (!iTxFifoFull) begin
            oTxPushValid <= 1'b1;
          end
          if (!iTxFifoFull && (rCharIdx < rLastIdx)) begin
            rCharIdx <= rCharIdx + 1'b1;
          end
        end

        default: ;
      endcase
    end
  end

endmodule
