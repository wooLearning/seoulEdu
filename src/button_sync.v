/*
[MODULE_INFO_START]
Name: button_sync
Role: button_sync 모듈을 구현한 RTL 블록
Summary:
  - button과 FPGA는 CDC 환경이므로 sync를 위한 블록이다. 
  - button의 edge detect를 위한 모듈이다. 
[MODULE_INFO_END]
*/

`timescale 1ns / 1ps

module button_sync #(
  parameter P_BUTTON_WIDTH = 5
) (
  input wire                      iClk,
  input wire                      iRst,
  input wire [P_BUTTON_WIDTH-1:0] iButtonRaw,
  output wire [P_BUTTON_WIDTH-1:0] oButtonEdge
);

  // 2-stage synchronizer + edge detection
  reg [P_BUTTON_WIDTH-1:0] rSync1;
  reg [P_BUTTON_WIDTH-1:0] rSync2;
  reg [P_BUTTON_WIDTH-1:0] rPrev;

  always @(posedge iClk or posedge iRst) begin
    if (iRst) begin
      rSync1 <= {P_BUTTON_WIDTH{1'b0}};
      rSync2 <= {P_BUTTON_WIDTH{1'b0}};
      rPrev  <= {P_BUTTON_WIDTH{1'b0}};
    end else begin
      rSync1 <= iButtonRaw;
      rSync2 <= rSync1;
      rPrev  <= rSync2;
    end
  end

  // Rising edge detection (bitwise operation)
  assign oButtonEdge = rSync2 & ~rPrev;

endmodule



