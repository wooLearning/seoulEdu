/*
[TB_INFO_START]
Name: tb_top_smoke
Target: Top
Role: System-Level Smoke Test
Scenario:
  - Integrated simulation of UART, Buttons, and Sensors
  - Tasks: `send_uart_byte` (Commands), `simulate_sr04_echo_cm`
  - Simulates full flow: Mode change -> Sensor Request -> Report Generation
CheckPoint:
  - Monitors UART TX output for correct ASCII reports
  - Verifies interaction between Control Unit and peripherals
  - Ensures no deadlock in FSMs
[TB_INFO_END]
*/

`timescale 1ns / 1ps

module tb_top;
  initial begin
    $dumpfile("tb_top.vcd");
    $dumpvars(0, tb_top);
  end

  localparam integer BAUD_RATE = 9600;
  localparam integer BIT_PERIOD_NS = 1_000_000_000 / BAUD_RATE;
  localparam integer CLK_PER_US = 100; // 100MHz
  localparam integer START_GUARD_CYC = 2_000_000; // 20ms @100MHz
  localparam integer WAIT_GUARD_CYC  = 2_000_000; // 20ms @100MHz

  reg iClk;
  reg iRst;
  reg iRx;

  reg iSw0, iSw1, iSw2, iSw3;
  reg iBtnC, iBtnU, iBtnD, iBtnL, iBtnR;
  reg iSr04Echo;
  reg rDht11DriveLow;
  tri1 ioDht11Data;
  assign ioDht11Data = rDht11DriveLow ? 1'b0 : 1'bz;

  wire oTx;
  wire oSr04Trig;
  wire [3:0] oFndCom;
  wire [7:0] oFndFont;

  Top dut (
    .iClk(iClk),
    .iRst(iRst),
    .iRx(iRx),
    .oTx(oTx),
    .iSw0(iSw0),
    .iSw1(iSw1),
    .iSw2(iSw2),
    .iSw3(iSw3),
    .iBtnC(iBtnC),
    .iBtnU(iBtnU),
    .iBtnD(iBtnD),
    .iBtnL(iBtnL),
    .iBtnR(iBtnR),
    .iSr04Echo(iSr04Echo),
    .oSr04Trig(oSr04Trig),
    .ioDht11Data(ioDht11Data),
    .oFndCom(oFndCom),
    .oFndFont(oFndFont)
  );

  // Speed up DHT11 simulation in top smoke.
  defparam dut.u_dht11_controller.START_LOW_MS = 1;
  defparam dut.u_dht11_controller.START_RELEASE_US = 20;
  defparam dut.u_dht11_controller.RESP_TIMEOUT_US = 250;
  defparam dut.u_dht11_controller.BIT_TIMEOUT_US = 140;

  always #5 iClk = ~iClk;

  task send_uart_byte(input [7:0] data);
    integer i;
    begin
      iRx = 1'b0; // start bit
      #(BIT_PERIOD_NS);

      for (i = 0; i < 8; i = i + 1) begin
        iRx = data[i];
        #(BIT_PERIOD_NS);
      end

      iRx = 1'b1; // stop bit
      #(BIT_PERIOD_NS);
      #(BIT_PERIOD_NS); // inter-byte gap
    end
  endtask

  task press_button_c;
    begin
      @(negedge iClk); iBtnC = 1'b1;
      @(negedge iClk); iBtnC = 1'b0;
    end
  endtask

  task simulate_sr04_echo_cm(input integer distance_cm);
    begin
      wait(oSr04Trig == 1'b1);
      wait(oSr04Trig == 1'b0);
      #5000;
      iSr04Echo = 1'b1;
      #(distance_cm * 58_000); // 58us per cm
      iSr04Echo = 1'b0;
    end
  endtask

  task wait_us(input integer n_us);
    integer i;
    begin
      for (i = 0; i < (n_us * CLK_PER_US); i = i + 1) @(posedge iClk);
    end
  endtask

  task dht_send_bit(input bit_value);
    begin
      rDht11DriveLow = 1'b1;
      wait_us(50);
      rDht11DriveLow = 1'b0;
      if (bit_value) wait_us(70);
      else           wait_us(28);
    end
  endtask

  task dht_send_byte(input [7:0] byte_value);
    integer i;
    begin
      for (i = 7; i >= 0; i = i - 1) begin
        dht_send_bit(byte_value[i]);
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

      guard = 0;
      while ((ioDht11Data !== 1'b0) && (guard < START_GUARD_CYC)) begin
        @(posedge iClk);
        guard = guard + 1;
      end
      if (ioDht11Data !== 1'b0) begin
        $display("top dht model timeout waiting host start low");
        $finish;
      end

      guard = 0;
      while ((ioDht11Data !== 1'b1) && (guard < START_GUARD_CYC)) begin
        @(posedge iClk);
        guard = guard + 1;
      end
      if (ioDht11Data !== 1'b1) begin
        $display("top dht model timeout waiting host release");
        $finish;
      end

      wait_us(30);
      rDht11DriveLow = 1'b1;
      wait_us(80);
      rDht11DriveLow = 1'b0;
      wait_us(80);

      dht_send_byte(hum_i);
      dht_send_byte(hum_d);
      dht_send_byte(temp_i);
      dht_send_byte(temp_d);
      dht_send_byte(checksum);

      rDht11DriveLow = 1'b1;
      wait_us(50);
      rDht11DriveLow = 1'b0;
    end
  endtask

  reg [7:0] rTxCaptured;
  integer dht_wait_timeout;
  initial begin
    // Global watchdog to avoid hang.
    #(150_000_000);
    $display("tb_top_smoke global timeout");
    $finish;
  end

  initial begin
    forever begin
      @(negedge oTx);
      #(BIT_PERIOD_NS/2);
      if (oTx == 1'b0) begin
        #(BIT_PERIOD_NS); rTxCaptured[0] = oTx;
        #(BIT_PERIOD_NS); rTxCaptured[1] = oTx;
        #(BIT_PERIOD_NS); rTxCaptured[2] = oTx;
        #(BIT_PERIOD_NS); rTxCaptured[3] = oTx;
        #(BIT_PERIOD_NS); rTxCaptured[4] = oTx;
        #(BIT_PERIOD_NS); rTxCaptured[5] = oTx;
        #(BIT_PERIOD_NS); rTxCaptured[6] = oTx;
        #(BIT_PERIOD_NS); rTxCaptured[7] = oTx;
        #(BIT_PERIOD_NS); // stop bit
        $display("[tb_top_smoke] TX byte: 0x%h ('%c')", rTxCaptured, rTxCaptured);
      end
    end
  end

  initial begin
    iClk = 1'b0;
    iRst = 1'b1;
    iRx  = 1'b1; // UART idle

    iSw0 = 1'b1; // clock mode
    iSw1 = 1'b1; // hour:min
    iSw2 = 1'b0; // display watch
    iSw3 = 1'b0;

    iBtnC = 1'b0;
    iBtnU = 1'b0;
    iBtnD = 1'b0;
    iBtnL = 1'b0;
    iBtnR = 1'b0;
    iSr04Echo = 1'b0;
    rDht11DriveLow = 1'b0;

    repeat (10) @(posedge iClk);
    iRst = 1'b0;

    // Clock mode and edit by UART (legacy-style serial stimulation)
    send_uart_byte("1"); // clock mode
    send_uart_byte("3"); // hour:min display
    send_uart_byte("c"); // enter edit
    send_uart_byte("u"); // increment
    send_uart_byte("c"); // exit edit

    // Request watch report
    send_uart_byte("w");

    // Switch to stopwatch mode and start/stop with physical + UART mix
    send_uart_byte("0");
    press_button_c();
    repeat (300000) @(posedge iClk);
    send_uart_byte("c");

    // Select SR04 display and simulate one echo transaction.
    // Unified policy: 'c/C' command is sensor start trigger.
    send_uart_byte("5");
    fork
      simulate_sr04_echo_cm(25);
      send_uart_byte("c");
    join
    send_uart_byte("s"); // sr04 report

    // Select DHT11 display source and trigger by C command.
    send_uart_byte("6");
    fork
      begin
        dht11_respond_once(8'd44, 8'd0, 8'd23, 8'd0);
      end
      begin
        send_uart_byte("c");
        press_button_c();
      end
    join
    dht_wait_timeout = 0;
    while ((dut.wDhtDataValid !== 1'b1) && (dht_wait_timeout < WAIT_GUARD_CYC)) begin
      @(posedge iClk);
      dht_wait_timeout = dht_wait_timeout + 1;
    end
    if (dut.wDhtDataValid !== 1'b1) begin
      $display("top dht data_valid timeout");
      $finish;
    end
    if (dut.wDhtHumInt  !== 8'd44) begin
      $display("top dht humidity mismatch: %0d", dut.wDhtHumInt);
      $finish;
    end
    if (dut.wDhtTempInt !== 8'd23) begin
      $display("top dht temperature mismatch: %0d", dut.wDhtTempInt);
      $finish;
    end
    if (dut.wDisplaySelect !== 2'b10) begin
      $display("top display select should stay at dht11");
      $finish;
    end

    // DHT11 report requests over UART.
    send_uart_byte("t");
    send_uart_byte("h");

    $display("tb_top_smoke finished");
    $finish;
  end

endmodule
