/*
[MODULE_INFO_START]
Name: stopwatch_mem
Role: Stopwatch Lap Memory (RAM)
Summary:
  - 30-depth x 28-bit register array for storing lap times
  - Stores {Hour, Min, Sec, Centisic} packed in 28 bits
  - Supports single-cycle write and asynchronous read
  - Used by `stopwatch` module for record keeping
[MODULE_INFO_END]
*/

`timescale 1ns / 1ps

module stopwatch_mem (
  input  wire        iClk,
  input  wire        iWE,      // Write Enable
  input  wire [4:0]  iAddr,    // Address (0~29) - 5 bits enough for 30
  input  wire [27:0] iWData,   // {Hour, Min, Sec, Centi}
  output wire [27:0] oRData
);

  // 30-depth Register memory
  reg [27:0] rMem [0:29];

  integer i;
  initial begin
    for (i = 0; i < 30; i = i + 1) rMem[i] = 28'd0;
  end
  
  // Write Logic
  always @(posedge iClk) begin
    if (iWE) begin
      // Safety: Only write if address is within range
      if (iAddr < 30) begin
        rMem[iAddr] <= iWData;
      end
    end
  end

  // Read Logic (Asynchronous or Synchronous?)
  // Generally BRAM is synchronous read. Register array can be async.
  // To match previous BRAM timing (usually 1 cycle delay), we can make it sync.
  // BUT: stopwatch logic might expect specific timing. 
  // Let's make it Asynchronous read for simplicity unless timing fails.
  // If user said "register", usually async read is implied or simple sync.
  // Let's stick to Async read for easiest logic.
  
  assign oRData = (iAddr < 30) ? rMem[iAddr] : 28'd0;

endmodule



