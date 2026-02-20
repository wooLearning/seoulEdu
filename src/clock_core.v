/*
[MODULE_INFO_START]
Name: clock_core
Role: Digital Clock Timekeeping Core
Summary:
  - Maintains current time (Hour, Minute, Second, Centisecond) based on 100Hz input tick
  - Implements two main modes: RUN (Timekeeping) and EDIT (Time Setting)
  - RUN Mode: Counts up time automatically; handles overflow (59->00, 12->01)
  - EDIT Mode: Allows user to modify specific time fields (Sec, Min, Hour)
  - Controls state transitions via external button inputs (Run/Stop, Inc, Dec, Left, Right)
StateDescription:
  - RUN: Normal operation; time advances with each iTick
  - EDIT_SEC: Edit Seconds field; Inc/Dec modifies seconds; Centiseconds reset
  - EDIT_MIN: Edit Minutes field; Inc/Dec modifies minutes
  - EDIT_HOUR: Edit Hours field; Inc/Dec modifies hours (1-12 range)
[MODULE_INFO_END]
*/

`timescale 1ns / 1ps

module clock_core (
  input iClk,        // System Clock (100MHz)
  input iRst,        // Hardware Reset
  input iTick,       // 100Hz Time Pulse
  input iBtnRunStop, // Toggle Run/Stop (Enter/Exit Edit Mode)
  input iBtnInc,     // Value Up
  input iBtnDec,     // Value Down
  input iBtnLeft,    // Cursor Left
  input iBtnRight,   // Cursor Right
  output reg [6:0] oSec,
  output reg [6:0] oMin,
  output reg [6:0] oHour,
  output reg [6:0] oCentisec,
  output reg [1:0] oEditState // 0:Run, 1:Sec, 2:Min, 3:Hour
);

  // States
  localparam RUN       = 2'd0;
  localparam EDIT_SEC  = 2'd1;
  localparam EDIT_MIN  = 2'd2;
  localparam EDIT_HOUR = 2'd3;

  always @(posedge iClk or posedge iRst) begin
    if (iRst) begin
      oCentisec  <= 0;
      oSec       <= 0;
      oMin       <= 0;
      oHour      <= 12; // Start at 12:00
      oEditState <= RUN;
    end
    else begin
      // 1. Run/Stop Toggle Logic (State Transition)
      if (iBtnRunStop) begin
        if (oEditState == RUN)
          oEditState <= EDIT_SEC; // Go to Edit Mode (Default: Sec)
        else
          oEditState <= RUN;      // Go back to Run Mode
      end
      
      // 2. State Machine Logic
      if (oEditState == RUN) begin
        // --- RUN MODE ---
        if (iTick) begin
          if (oCentisec >= 99) begin
            oCentisec <= 0;
            if (oSec >= 59) begin
              oSec <= 0;
              if (oMin >= 59) begin
                oMin <= 0;
                if (oHour >= 12) oHour <= 1;
                else oHour <= oHour + 1;
              end
              else oMin <= oMin + 1;
            end
            else oSec <= oSec + 1;
          end
          else oCentisec <= oCentisec + 1;
        end
      end
      else begin
        // --- EDIT MODE (Clock Stopped) ---
        // Verify time ranges just in case (e.g. if switching from a weird state)
        // (Optional safety, mostly handled by Inc/Dec logic)

        // 2-1. Cursor Navigation (Left/Right)
        if (iBtnLeft) begin
          case (oEditState)
            EDIT_SEC:  oEditState <= EDIT_MIN;
            EDIT_MIN:  oEditState <= EDIT_HOUR;
            EDIT_HOUR: oEditState <= EDIT_SEC; // Wrap around
          endcase
        end
        else if (iBtnRight) begin
          case (oEditState)
            EDIT_SEC:  oEditState <= EDIT_HOUR; // Wrap around
            EDIT_MIN:  oEditState <= EDIT_SEC;
            EDIT_HOUR: oEditState <= EDIT_MIN;
          endcase
        end

        // 2-2. Value Modification (Inc/Dec)
        if (iBtnInc) begin
          case (oEditState)
            EDIT_SEC: begin
              oCentisec <= 0; // Reset millis when editing seconds
              if (oSec >= 59) oSec <= 0; else oSec <= oSec + 1;
            end
            EDIT_MIN: begin
              if (oMin >= 59) oMin <= 0; else oMin <= oMin + 1;
            end
            EDIT_HOUR: begin
              if (oHour >= 12) oHour <= 1; else oHour <= oHour + 1;
            end
          endcase
        end
        else if (iBtnDec) begin
          case (oEditState)
            EDIT_SEC: begin
              oCentisec <= 0;
              if (oSec == 0) oSec <= 59; else oSec <= oSec - 1;
            end
            EDIT_MIN: begin
              if (oMin == 0) oMin <= 59; else oMin <= oMin - 1;
            end
            EDIT_HOUR: begin
              if (oHour == 1) oHour <= 12; else oHour <= oHour - 1;
            end
          endcase
        end
      end
    end
  end

endmodule



