`timescale 1ns / 1ps

module tb_tx_fifo_top;

  localparam integer P_CLK_FREQ_HZ = 100_000_000;
  localparam integer P_BAUD_RATE   = 9_600;
  localparam integer P_TICK16X_DIV = P_CLK_FREQ_HZ / (P_BAUD_RATE * 16);

  reg        iClk;
  reg        iRst;
  reg        iTick16x;
  reg        iPushValid;
  reg [7:0]  iPushData;
  reg        iPopValid;

  wire       oTx;
  wire       oBusy;
  wire       oFull;
  wire [7:0] oPopData;
  wire       oEmpty;

  integer i;
  integer rTickDivCnt;
  integer rPushCnt;
  integer rPopCnt;

  tx_fifo_top dut (
    .iClk(iClk),
    .iRst(iRst),
    .iTick16x(iTick16x),
    .iPushValid(iPushValid),
    .iPushData(iPushData),
    .iPopValid(iPopValid),
    .oTx(oTx),
    .oBusy(oBusy),
    .oFull(oFull),
    .oPopData(oPopData),
    .oEmpty(oEmpty)
  );

  // 100MHz system clock
  initial iClk = 1'b0;
  always #5 iClk = ~iClk;

  // 16x tick for 9600 baud (1-cycle pulse)
  always @(posedge iClk or posedge iRst) begin
    if (iRst) begin
      rTickDivCnt <= 0;
      iTick16x    <= 1'b0;
    end else begin
      if (rTickDivCnt == (P_TICK16X_DIV - 1)) begin
        rTickDivCnt <= 0;
        iTick16x    <= 1'b1;
      end else begin
        rTickDivCnt <= rTickDivCnt + 1;
        iTick16x    <= 1'b0;
      end
    end
  end

  task push_byte;
    input [7:0] data;
    begin
      @(posedge iClk);
      iPushData  <= data;
      iPushValid <= 1'b1;
      @(posedge iClk);
      iPushValid <= 1'b0;
      iPushData  <= 8'h00;
    end
  endtask

  initial begin
    iRst       = 1'b1;
    iTick16x   = 1'b0;
    iPushValid = 1'b0;
    iPushData  = 8'h00;
    iPopValid  = 1'b0;
    rPushCnt   = 0;
    rPopCnt    = 0;

    repeat (5) @(posedge iClk);
    iRst = 1'b0;
    repeat (2) @(posedge iClk);

    // Push until FIFO full
    i = 0;
    while (!oFull) begin
      push_byte(i[7:0]);
      i = i + 1;
      rPushCnt = rPushCnt + 1;
    end
    $display("FIFO full asserted, push_count=%0d, time=%0t", rPushCnt, $time);

    // Pop until FIFO empty (one pop per TX frame so oTx waveform is easy to see)
    while (!oEmpty) begin
      wait (oBusy == 1'b0);
      @(posedge iClk);
      iPopValid = 1'b1;
      @(posedge iClk);
      iPopValid = 1'b0;
      rPopCnt = rPopCnt + 1;
      wait (oBusy == 1'b1);
      wait (oBusy == 1'b0);
    end

    $display("FIFO empty asserted, pop_count=%0d, time=%0t", rPopCnt, $time);
    $finish;
  end

endmodule

