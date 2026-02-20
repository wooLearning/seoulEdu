/*
[MODULE_INFO_START]
Name: gen_clk
Role: System Clock Divider & Tick Generator
Summary:
  - Derives lower frequency clock enables/ticks from the main system clock (100MHz)
  - Generates 100Hz tick for Stopwatch/Clock timekeeping
  - Generates 1kHz tick for FND display scanning
  - Generates 1us tick for Sensor timing (SR04, DHT11) and delays
  - Uses parameterized counters for flexibility
[MODULE_INFO_END]
*/

`timescale 1ns / 1ps

module gen_clk #(
  parameter CNT_100HZ_MAX = 1_000_000,
  parameter CNT_1KHZ_MAX  = 100_000,
  parameter CNT_1US_MAX   = 100
) (
  input  iClk,
  input  iRst,
  output reg oClk100hz,
  output reg oClk1khz,
  output reg oTick1us
);

  // 100Hz generation (100MHz / 1,000,000)
  // parameter CNT_100HZ_MAX = 1_000_000; // Moved to header
  reg [31:0] rCnt100hz;

  always @(posedge iClk or posedge iRst) begin
    if (iRst) begin
      rCnt100hz <= 0;
      oClk100hz <= 0;
    end
    else begin
      if (rCnt100hz >= CNT_100HZ_MAX - 1) begin
        rCnt100hz <= 0;
        oClk100hz <= 1'b1;
      end
      else begin
        rCnt100hz <= rCnt100hz + 1;
        oClk100hz <= 1'b0;
      end
    end
  end

  // 1kHz generation (100MHz / 100,000)
  // parameter CNT_1KHZ_MAX = 100_000; // Moved to header
  reg [31:0] rCnt1khz;

  always @(posedge iClk or posedge iRst) begin
    if (iRst) begin
      rCnt1khz <= 0;
      oClk1khz <= 0;
    end
    else begin
      if (rCnt1khz >= CNT_1KHZ_MAX - 1) begin
        rCnt1khz <= 0;
        oClk1khz <= 1'b1;
      end
      else begin
        rCnt1khz <= rCnt1khz + 1;
        oClk1khz <= 1'b0;
      end
    end
  end

  // 1us tick generation (100MHz / 100)
  reg [31:0] rCnt1us;

  always @(posedge iClk or posedge iRst) begin
    if (iRst) begin
      rCnt1us <= 0;
      oTick1us <= 0;
    end
    else begin
      if (rCnt1us >= CNT_1US_MAX - 1) begin
        rCnt1us <= 0;
        oTick1us <= 1'b1;
      end
      else begin
        rCnt1us <= rCnt1us + 1;
        oTick1us <= 1'b0;
      end
    end
  end

endmodule



