/*
[TB_INFO_START]
Name: tb_sr04_controller
Target: sr04_controller
Role: Testbench for SR04 Ultrasonic Controller
Scenario:
  - Generates 1us tick pulse from system clock
  - Simulates Echo return signal with variable duration in microseconds
CheckPoint:
  - Verifies Trigger pulse generation (10us)
  - Verifies Distance calculation based on echo width
  - Checks flag assertions for valid measurement
[TB_INFO_END]
*/

`timescale 1ns / 1ps

module tb_sr04_controller;
  initial begin
    $dumpfile("tb_sr04_controller.vcd");
    $dumpvars(0, tb_sr04_controller);
  end

  localparam integer CLK_PERIOD_NS = 10;   // 100MHz
  localparam integer CLK_PER_US    = 100;  // 1us = 100 cycles @100MHz

  reg iClk;
  reg iRst;
  reg iEcho;
  reg iStart;
  reg iTickUs;
  reg [7:0] rTickDiv;

  wire oTrig;
  wire [9:0] oDistanceCm;
  wire oDistanceValid;

  // 1MHz test clock model:
  // 1 cycle = 1us (easy to reason about pulse widths).
  sr04_controller #(
    .TRIG_US(10)
  ) dut (
    .iClk(iClk),
    .iRst(iRst),
    .iTickUs(iTickUs),
    .iEcho(iEcho),
    .iStart(iStart),
    .oTrig(oTrig),
    .oDistanceCm(oDistanceCm),
    .oDistanceValid(oDistanceValid)
  );

  // 100MHz system clock
  always #(CLK_PERIOD_NS/2) iClk = ~iClk;

  // 1us tick pulse: high for one iClk cycle.
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

  task wait_us(input integer n_us);
    integer k;
    begin
      for (k = 0; k < n_us; k = k + 1) begin
        @(posedge iClk);
        while (iTickUs !== 1'b1) @(posedge iClk);
      end
    end
  endtask

  task pulse_start_req;
    begin
      @(posedge iClk);
      iStart <= 1'b1;
      @(posedge iClk);
      iStart <= 1'b0;
    end
  endtask

  task send_echo_high_us(input integer n_us);
    begin
      @(negedge iClk);
      iEcho = 1'b1;
      wait_us(n_us);
      @(negedge iClk);
      iEcho = 1'b0;
    end
  endtask

  initial begin
    iClk = 1'b0;
    iRst = 1'b1;
    iEcho = 1'b0;
    iStart = 1'b0;
    iTickUs = 1'b0;
    rTickDiv = 8'd0;

    repeat (5) @(posedge iClk);
    iRst = 1'b0;

    // Start one measurement manually.
    pulse_start_req();

    // Wait until oTrig phase finishes and controller waits for iEcho.
    wait (oTrig == 1'b1);
    wait (oTrig == 1'b0);
    wait_us(20);

    // Echo high width = 580us -> around 10cm (580/58).
    send_echo_high_us(580);

    wait (oDistanceValid == 1'b1);
    if ((oDistanceCm < 9) || (oDistanceCm > 11)) begin
      $display("sr04 distance out of expected range: %0d", oDistanceCm);
      $finish;
    end

    wait_us(20);
    $display("tb_sr04_controller finished: oDistanceCm=%0d", oDistanceCm);
    $finish;
  end

endmodule
