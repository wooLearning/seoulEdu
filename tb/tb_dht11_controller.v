/*
[TB_INFO_START]
Name: tb_dht11_controller
Target: dht11_controller
Role: Testbench for validating dht11_controller
Scenario:
  - Generates 1us tick pulse from 10MHz system clock
  - Models DHT11 single-wire response sequence (ACK + 40-bit payload)
  - Verifies one normal frame (hum=55, temp=24)
CheckPoint:
  - Verify oDataValid assertion
  - Verify oHumInt/oTempInt match expected values
  - Use explicit timeout to avoid infinite wait
[TB_INFO_END]
*/

`timescale 1ns / 1ps

module tb_dht11_controller;
  localparam integer CLK_PERIOD_NS  = 100;    // 10MHz
  localparam integer CLK_PER_US     = 10;     // 1us = 10 cycles @10MHz
  localparam integer START_GUARD_US = 25_000; // 25ms guard
  localparam integer WAIT_VALID_MAX = 1_000_000;

  reg iClk;
  reg iRst;
  reg iStart;
  reg iTickUs;
  reg rSensorDriveLow;
  reg [7:0] rTickDiv;

  tri1 ioData;
  assign ioData = rSensorDriveLow ? 1'b0 : 1'bz;

  wire [7:0] oHumInt;
  wire [7:0] oTempInt;
  wire       oDataValid;

  integer rWaitCnt;

  // 10MHz system clock
  always #(CLK_PERIOD_NS/2) iClk = ~iClk;

  // 1us tick pulse: high for one iClk cycle
  always @(posedge iClk or posedge iRst) begin
    if (iRst) begin
      rTickDiv <= 8'd0;
      iTickUs  <= 1'b0;
    end else begin
      if (rTickDiv == CLK_PER_US - 1) begin
        rTickDiv <= 8'd0;
        iTickUs  <= 1'b1;
      end else begin
        rTickDiv <= rTickDiv + 1'b1;
        iTickUs  <= 1'b0;
      end
    end
  end

  dht11_controller #(
    .START_LOW_MS(1),
    .START_RELEASE_US(20),
    .RESP_TIMEOUT_US(200),
    .BIT_TIMEOUT_US(120)
  ) dut (
    .iClk(iClk),
    .iRst(iRst),
    .iTickUs(iTickUs),
    .iStart(iStart),
    .ioData(ioData),
    .oHumInt(oHumInt),
    .oTempInt(oTempInt),
    .oDataValid(oDataValid)
  );

  task wait_us(input integer n_us);
    integer i;
    begin
      for (i = 0; i < n_us; i = i + 1) begin
        @(posedge iClk);
        while (iTickUs !== 1'b1) @(posedge iClk);
      end
    end
  endtask

  task dht_send_bit(input bit_value);
    begin
      rSensorDriveLow = 1'b1;
      wait_us(50);
      rSensorDriveLow = 1'b0;
      if (bit_value) wait_us(70);
      else           wait_us(28);
    end
  endtask

  task dht_send_byte(input [7:0] byte_value);
    integer j;
    begin
      for (j = 7; j >= 0; j = j - 1) begin
        dht_send_bit(byte_value[j]);
      end
    end
  endtask

  task dht11_respond_once(
    input [7:0] hum_i,
    input [7:0] hum_d,
    input [7:0] temp_i,
    input [7:0] temp_d
  );
    reg [7:0] checksum;
    integer guard;
    begin
      checksum = hum_i + hum_d + temp_i + temp_d;

      // Wait host start low
      guard = 0;
      while ((ioData !== 1'b0) && (guard < START_GUARD_US)) begin
        wait_us(1);
        guard = guard + 1;
      end
      if (ioData !== 1'b0) begin
        $display("dht model timeout waiting host start low");
        $finish;
      end

      // Wait host release
      guard = 0;
      while ((ioData !== 1'b1) && (guard < START_GUARD_US)) begin
        wait_us(1);
        guard = guard + 1;
      end
      if (ioData !== 1'b1) begin
        $display("dht model timeout waiting host release");
        $finish;
      end

      // Sensor ACK: 80us low + 80us high
      wait_us(30);
      rSensorDriveLow = 1'b1;
      wait_us(80);
      rSensorDriveLow = 1'b0;
      wait_us(80);

      // 40-bit payload
      dht_send_byte(hum_i);
      dht_send_byte(hum_d);
      dht_send_byte(temp_i);
      dht_send_byte(temp_d);
      dht_send_byte(checksum);

      // End bit-low then release
      rSensorDriveLow = 1'b1;
      wait_us(50);
      rSensorDriveLow = 1'b0;
    end
  endtask

  initial begin
    iClk           = 1'b0;
    iRst           = 1'b1;
    iStart         = 1'b0;
    iTickUs        = 1'b0;
    rTickDiv       = 8'd0;
    rSensorDriveLow = 1'b0;
    rWaitCnt       = 0;

    repeat (10) @(posedge iClk);
    iRst = 1'b0;

    fork
      begin
        dht11_respond_once(8'd55, 8'd0, 8'd24, 8'd0);
      end
      begin
        @(posedge iClk);
        iStart <= 1'b1;
        @(posedge iClk);
        iStart <= 1'b0;
      end
    join

    // Wait oDataValid with explicit timeout
    rWaitCnt = 0;
    while ((oDataValid !== 1'b1) && (rWaitCnt < WAIT_VALID_MAX)) begin
      @(posedge iClk);
      rWaitCnt = rWaitCnt + 1;
    end
    if (oDataValid !== 1'b1) begin
      $display("dht11 oDataValid timeout");
      $finish;
    end

    if (oHumInt !== 8'd55) begin
      $display("dht11 humidity mismatch: %0d", oHumInt);
      $finish;
    end
    if (oTempInt !== 8'd24) begin
      $display("dht11 temperature mismatch: %0d", oTempInt);
      $finish;
    end

    $display("tb_dht11_controller finished: hum=%0d temp=%0d oDataValid=%0d",
      oHumInt, oTempInt, oDataValid);
    $finish;
  end

endmodule
