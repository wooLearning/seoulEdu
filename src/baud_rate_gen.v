/*
[MODULE_INFO_START]
Name: baud_rate_gen
Role: baud_rate_gen 모듈을 구현한 RTL 블록
Summary:
  - UART에 필요한 Tick을 생성한다.
  - BaudRate 파라미터로 받아서 16배수 tick을 생성하게 된다. 
[MODULE_INFO_END]
*/

`timescale 1ns / 1ps

module baud_rate_gen #(
  parameter CLK_FREQ = 100_000_000,
  parameter BAUD_RATE = 9600
)(
  input  wire iClk,
  input  wire iRst,
  output wire oTick16x
);

  localparam CNT_MAX = CLK_FREQ / (BAUD_RATE * 16);

  // Ensure bit width is at least 1
  localparam CNT_WIDTH = ($clog2(CNT_MAX) > 0) ? $clog2(CNT_MAX) : 1;
  reg [CNT_WIDTH-1:0] rCnt;
  reg rTick16x;

  always @(posedge iClk or posedge iRst) begin
    if (iRst) begin
      rCnt <= 0;
      rTick16x <= 0;
    end else begin
      // 16x Tick Generation
      if (rCnt >= (CNT_MAX - 1)) begin
        rCnt <= 0;
        rTick16x <= 1;
      end else begin
        rCnt <= rCnt + 1;
        rTick16x <= 0;
      end
    end
  end

  assign oTick16x = rTick16x;

endmodule
