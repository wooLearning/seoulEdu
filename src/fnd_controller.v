/*
[MODULE_INFO_START]
Name: fnd_controller
Role: 4-Digit 7-Segment Display Controller
Summary:
  - Multiplexes 4 digits on a 7-segment display using Time-Division Multiplexing (TDM)
  - Scans through 4 digits based on `iScanTick`
  - Decodes 4-bit BCD values to 7-segment font patterns (0-9)
  - Manages Anode control signals (`oFndCom`) for active digit selection
  - Hardcoded Decimal Point on the 3rd digit (Index 2) for clock formatting (e.g., 12.34)
[MODULE_INFO_END]
*/

`timescale 1ns / 1ps

module fnd_controller (
  input        iClk,
  input        iRst,
  input        iScanTick,
  input  [13:0] iDigit,
  output [ 7:0] oFndFont,
  output [ 3:0] oFndCom
);

// Internal signals
reg  [1:0] rFndSel;
wire [3:0] wDigit1, wDigit10, wDigit100, wDigit1000;
wire [3:0] wSelectedDigit;
reg  [3:0] rFndCom;
reg  [3:0] rMuxOut;
reg  [7:0] rFndFont;

// Counter logic (FND scan counter)
always @(posedge iClk, posedge iRst) begin
  if (iRst) begin
    rFndSel <= 2'b00;
  end
  else if (iScanTick) begin
    rFndSel <= rFndSel + 1;
  end
end

// Digit Splitter logic (???)
assign wDigit1    = iDigit[6:0] % 10;
assign wDigit10   = iDigit[6:0] / 10;
assign wDigit100  = iDigit[13:7] % 10;
assign wDigit1000 = iDigit[13:7] / 10;

// Decoder logic (2-to-4 decoder)
always @(rFndSel) begin
  case (rFndSel)
    2'b00:
      rFndCom = 4'b1110;
    2'b01:
      rFndCom = 4'b1101;
    2'b10:
      rFndCom = 4'b1011;
    2'b11:
      rFndCom = 4'b0111;
    default:
      rFndCom = 4'b1111;
  endcase
end

// Mux logic (4x1 multiplexer)
always @(*) begin
  case (rFndSel)
    2'b00:
      rMuxOut <= wDigit1;
    2'b01:
      rMuxOut <= wDigit10;
    2'b10:
      rMuxOut <= wDigit100;
    2'b11:
      rMuxOut <= wDigit1000;
    default:
      rMuxOut <= wDigit1;
  endcase
end

assign wSelectedDigit = rMuxOut;

// BCD to 7-segment logic
always @(wSelectedDigit) begin
  case (wSelectedDigit)
    4'd0:
      rFndFont = 8'hC0;
    4'd1:
      rFndFont = 8'hf9;
    4'd2:
      rFndFont = 8'ha4;
    4'd3:
      rFndFont = 8'hB0;
    4'd4:
      rFndFont = 8'h99;
    4'd5:
      rFndFont = 8'h92;
    4'd6:
      rFndFont = 8'h82;
    4'd7:
      rFndFont = 8'hf8;
    4'd8:
      rFndFont = 8'h80;
    4'd9:
      rFndFont = 8'h90;
    default:
      rFndFont = 8'hFF;
  endcase
end

// Output assignments
assign oFndCom  = rFndCom;
// Turn on DP (bit 7, active low) when scanning the 3rd digit (index 2, 100s place)
// We use & 8'h7F (0111_1111) to force bit 7 to 0 (ON) while keeping bits 0-6 (the number) valid.
assign oFndFont = (rFndSel == 2'b10) ? (rFndFont & 8'h7F) : rFndFont;

endmodule