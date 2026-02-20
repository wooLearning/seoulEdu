/*
[MODULE_INFO_START]
Name: uart_ascii_decoder
Role: UART ASCII Command Parser
Summary:
  - Decodes received ASCII characters into internal control signals
  - Maps characters to Virtual Buttons ('c', 'u', 'd', 'l', 'r')
  - Maps characters to Switch Toggles ('0'-'6', 'x')
  - Maps characters to Report Requests ('w', 's', 't', 'h')
  - Passes through loopback data
[MODULE_INFO_END]
*/

`timescale 1ns / 1ps

module uart_ascii_decoder (
  input  wire       iClk,
  input  wire       iRst,
  input  wire [7:0] iRxData,   // UART RX byte (ASCII command)
  input  wire       iRxValid,  // 1-cycle strobe when iRxData is valid

  output reg        oBtnC,     // Virtual Center button pulse from 'c'/'C'
  output reg        oBtnU,     // Virtual Up button pulse from 'u'/'U'
  output reg        oBtnD,     // Virtual Down button pulse from 'd'/'D'
  output reg        oBtnL,     // Virtual Left button pulse from 'l'/'L'
  output reg        oBtnR,     // Virtual Right button pulse from 'r'/'R'

  output reg        oTglSw0,   // Toggle pulse for sw0
  output reg        oTglSw1,   // Toggle pulse for sw1
  output reg        oTglSw2,   // Toggle pulse for sw2
  output reg        oTglSw3,   // Toggle pulse for sw3
  output reg        oClrSwTgl, // Clear toggle register in control_unit

  output reg        oReqWatchRpt,  // Request watch UART report pulse ('w'/'W')
  output reg        oReqSr04Rpt,   // Request SR04 UART report pulse ('s'/'S')
  output reg        oReqTempRpt,   // Request DHT11 temp UART report pulse ('t'/'T')
  output reg        oReqHumRpt,    // Request DHT11 humidity UART report pulse ('h'/'H')

  output reg [7:0]  oLoopData,             // Loopback byte for sender
  output reg        oLoopValid             // 1-cycle loopback valid strobe
);

  always @(posedge iClk or posedge iRst) begin
    if (iRst) begin
      oBtnC <= 1'b0;
      oBtnU <= 1'b0;
      oBtnD <= 1'b0;
      oBtnL <= 1'b0;
      oBtnR <= 1'b0;

      oTglSw0     <= 1'b0;
      oTglSw1     <= 1'b0;
      oTglSw2     <= 1'b0;
      oTglSw3     <= 1'b0;
      oClrSwTgl   <= 1'b0;

      oReqWatchRpt <= 1'b0;
      oReqSr04Rpt  <= 1'b0;
      oReqTempRpt  <= 1'b0;
      oReqHumRpt   <= 1'b0;

      oLoopData  <= 8'd0;
      oLoopValid <= 1'b0;
    end else begin
      // One-cycle pulse defaults
      oBtnC <= 1'b0;
      oBtnU <= 1'b0;
      oBtnD <= 1'b0;
      oBtnL <= 1'b0;
      oBtnR <= 1'b0;

      oTglSw0 <= 1'b0;
      oTglSw1 <= 1'b0;
      oTglSw2 <= 1'b0;
      oTglSw3 <= 1'b0;
      oClrSwTgl <= 1'b0;

      oReqWatchRpt <= 1'b0;
      oReqSr04Rpt  <= 1'b0;
      oReqTempRpt  <= 1'b0;
      oReqHumRpt   <= 1'b0;

      oLoopValid <= 1'b0;

      if (iRxValid) begin
        oLoopData  <= iRxData;
        oLoopValid <= 1'b1;

        case (iRxData)
          // C button emulation.
          // control_unit uses this pulse as unified sensor start source.
          "c", "C": oBtnC <= 1'b1;
          "u", "U": oBtnU <= 1'b1;
          "d", "D": oBtnD <= 1'b1;
          "l", "L": oBtnL <= 1'b1;
          "r", "R": oBtnR <= 1'b1;

          // Toggle commands:
          // sw0: mode toggle, sw1: watch-display toggle
          // sw2: watch/sensor group toggle, sw3: sensor select toggle.
          "0", "1": oTglSw0 <= 1'b1;
          "2", "3": oTglSw1 <= 1'b1;
          "4", "5": oTglSw2 <= 1'b1;
          "6":      oTglSw3 <= 1'b1;

          "x", "X": oClrSwTgl <= 1'b1;

          "w", "W": oReqWatchRpt <= 1'b1;
          "s", "S": oReqSr04Rpt  <= 1'b1;
          "t", "T": oReqTempRpt  <= 1'b1;
          "h", "H": oReqHumRpt   <= 1'b1;

          default: ;
        endcase
      end
    end
  end

endmodule



