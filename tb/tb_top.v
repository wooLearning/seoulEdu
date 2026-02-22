/*
[TB_INFO_START]
Name: tb_top
Target: Top
Role: System-Level Scenario Test (Case 1~6)
Scenario:
  - Case1: Physical C button -> stopwatch run/stop check
  - Case2: Physical U/D/L/R/C -> clock edit flow check
  - Case3: UART toggle command policy check (0/3/5/6/x)
  - Case4: UART watch report token check ("WATCH")
  - Case5: SR04 select/start/report path check
  - Case6: DHT11 select/start/report path check
CheckPoint:
  - Verify display/mode select policy from control path
  - Verify sensor data valid/value and UART report token output
  - Use explicit FAIL prints with $finish for auto-judgement
[TB_INFO_END]
*/

`timescale 1ns / 1ps


module tb_top;
  initial begin
    $dumpfile("tb_top.vcd");
    $dumpvars(0, tb_top);
  end

  localparam integer BAUD_RATE      = 9600;
  localparam integer BIT_PERIOD_NS  = 1_000_000_000 / BAUD_RATE;
  localparam integer CLK_PER_US     = 100; // 100MHz
  localparam integer START_GUARD_CYC = 2_000_000; // 20ms @100MHz

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

  // Speed up DHT11 in top-level simulation.
  defparam dut.u_dht11_controller.START_LOW_MS = 1;
  defparam dut.u_dht11_controller.START_RELEASE_US = 20;
  defparam dut.u_dht11_controller.RESP_TIMEOUT_US = 250;
  defparam dut.u_dht11_controller.BIT_TIMEOUT_US = 140;

  always #5 iClk = ~iClk;

  integer i;
  integer rTxCount;
  reg [7:0] rTxCaptured;
  reg [7:0] rTxLastByte;
  reg [7:0] rTxLog [0:1023];
  event evTxByte;

  integer rPrevMin;
  integer rExpectedMin;
  integer rPrevSec;
  integer rExpectedSec;
  // UART RX stimulus helper (8N1): start(0) + 8 data bits (LSB first) + stop(1).
  // Adds one extra bit-period as inter-byte gap.
  task send_uart_byte(input [7:0] data);
    integer k;
    begin
      iRx = 1'b0;
      #(BIT_PERIOD_NS);
      for (k = 0; k < 8; k = k + 1) begin
        iRx = data[k];
        #(BIT_PERIOD_NS);
      end
      iRx = 1'b1;
      #(BIT_PERIOD_NS);
      #(BIT_PERIOD_NS);
    end
  endtask

  // Physical button pulse helper for C button.
  // 3-cycle high keeps pulse stable through synchronizer stages.
  task press_button_c;
    begin
      @(negedge iClk); iBtnC = 1'b1;
      repeat (3) @(posedge iClk);
      @(negedge iClk); iBtnC = 1'b0;
    end
  endtask

  // Physical button pulse helper for U button.
  task press_button_u;
    begin
      @(negedge iClk); iBtnU = 1'b1;
      repeat (3) @(posedge iClk);
      @(negedge iClk); iBtnU = 1'b0;
    end
  endtask

  // Physical button pulse helper for D button.
  task press_button_d;
    begin
      @(negedge iClk); iBtnD = 1'b1;
      repeat (3) @(posedge iClk);
      @(negedge iClk); iBtnD = 1'b0;
    end
  endtask

  // Physical button pulse helper for L button.
  task press_button_l;
    begin
      @(negedge iClk); iBtnL = 1'b1;
      repeat (3) @(posedge iClk);
      @(negedge iClk); iBtnL = 1'b0;
    end
  endtask

  // Physical button pulse helper for R button.
  task press_button_r;
    begin
      @(negedge iClk); iBtnR = 1'b1;
      repeat (3) @(posedge iClk);
      @(negedge iClk); iBtnR = 1'b0;
    end
  endtask

  // SR04 echo model:
  // waits for DUT trig pulse, then drives echo high for distance_cm * 58us.
  task simulate_sr04_echo_cm(input integer distance_cm);
    begin
      wait(oSr04Trig == 1'b1);
      wait(oSr04Trig == 1'b0);
      #5000;
      iSr04Echo = 1'b1;
      #(distance_cm * 58_000);
      iSr04Echo = 1'b0;
    end
  endtask

  // Time helper in microsecond unit (based on 100MHz clock).
  task wait_us(input integer n_us);
    integer k;
    begin
      for (k = 0; k < (n_us * CLK_PER_US); k = k + 1) @(posedge iClk);
    end
  endtask

  // DHT11 bit model: 50us low + (28us/70us) high for 0/1.
  task dht_send_bit(input bit_value);
    begin
      rDht11DriveLow = 1'b1;
      wait_us(50);
      rDht11DriveLow = 1'b0;
      if (bit_value) wait_us(70);
      else           wait_us(28);
    end
  endtask

  // DHT11 byte model: send MSB first.
  task dht_send_byte(input [7:0] byte_value);
    integer k;
    begin
      for (k = 7; k >= 0; k = k - 1) begin
        dht_send_bit(byte_value[k]);
      end
    end
  endtask

  // DHT11 frame model (single transaction):
  // wait host start sequence, send ACK, send 40-bit payload + checksum.
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
        $display("FAIL: dht model timeout waiting host start low");
        $finish;
      end

      guard = 0;
      while ((ioDht11Data !== 1'b1) && (guard < START_GUARD_CYC)) begin
        @(posedge iClk);
        guard = guard + 1;
      end
      if (ioDht11Data !== 1'b1) begin
        $display("FAIL: dht model timeout waiting host release");
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

  // UART TX monitor helper:
  // waits until a sliding window on TX bytes matches token c0..c5 (by len).
  task wait_tx_token;
    input [7:0] c0;
    input [7:0] c1;
    input [7:0] c2;
    input [7:0] c3;
    input [7:0] c4;
    input [7:0] c5;
    input integer len;
    reg [7:0] s0, s1, s2, s3, s4, s5;
    reg found;
    begin
      s0 = 8'd0; s1 = 8'd0; s2 = 8'd0; s3 = 8'd0; s4 = 8'd0; s5 = 8'd0;
      found = 1'b0;
      while (!found) begin
        @(evTxByte);
        s0 = s1;
        s1 = s2;
        s2 = s3;
        s3 = s4;
        s4 = s5;
        s5 = rTxLastByte;

        if (len == 1) begin
          found = (s5 == c0);
        end 
        else if (len == 2) begin
          found = (s4 == c0) && (s5 == c1);
        end 
        else if (len == 3) begin
          found = (s3 == c0) && (s4 == c1) && (s5 == c2);
        end 
        else if (len == 4) begin
          found = (s2 == c0) && (s3 == c1) && (s4 == c2) && (s5 == c3);
        end 
        else if (len == 5) begin
          found = (s1 == c0) && (s2 == c1) && (s3 == c2) && (s4 == c3) && (s5 == c4);
        end 
        else begin
          found = (s0 == c0) && (s1 == c1) && (s2 == c2) && (s3 == c3) && (s4 == c4) && (s5 == c5);
        end
      end
    end
  endtask

  // -----------------------------------------------------------------------
  // Case1: physical stopwatch run/stop
  // -----------------------------------------------------------------------
  task run_case1;
    begin
      $display("CASE1 start: physical C -> stopwatch run/stop");
      iSw0 = 1'b0;
      iSw1 = 1'b0;
      iSw2 = 1'b0;
      iSw3 = 1'b0;
      repeat (20) @(posedge iClk);

      if (dut.wDisplaySelect !== 2'b00) begin
        $display("FAIL CASE1: display select should be watch, got %b", dut.wDisplaySelect);
        $finish;
      end

      press_button_c();
      repeat (20) @(posedge iClk);
      if (dut.u_watch_top.u_stopwatch.rCurState !== 2'd1) begin
        $display("FAIL CASE1: stopwatch state should be RUN(1), got %0d", dut.u_watch_top.u_stopwatch.rCurState);
        $finish;
      end

      // Keep RUN for a short window, then verify STOP transition only.
      repeat (1_200_000) @(posedge iClk);

      press_button_c();
      repeat (20) @(posedge iClk);
      if (dut.u_watch_top.u_stopwatch.rCurState !== 2'd2) begin
        $display("FAIL CASE1: stopwatch state should be STOP(2), got %0d", dut.u_watch_top.u_stopwatch.rCurState);
        $finish;
      end
      $display("CASE1 pass");
    end
  endtask

  // -----------------------------------------------------------------------
  // Case2: physical clock edit (C/L/U/R/D/C)
  // -----------------------------------------------------------------------
  task run_case2;
    begin
      $display("CASE2 start: physical clock edit flow");
      iSw0 = 1'b1;
      iSw1 = 1'b1;
      iSw2 = 1'b0;
      iSw3 = 1'b0;
      repeat (20) @(posedge iClk);

      press_button_c();
      repeat (20) @(posedge iClk);
      if (dut.u_watch_top.u_clock_core.oEditState !== 2'd1) begin
        $display("FAIL CASE2: edit state should be EDIT_SEC(1), got %0d", dut.u_watch_top.u_clock_core.oEditState);
        $finish;
      end

      press_button_l();
      repeat (20) @(posedge iClk);
      if (dut.u_watch_top.u_clock_core.oEditState !== 2'd2) begin
        $display("FAIL CASE2: edit state should be EDIT_MIN(2), got %0d", dut.u_watch_top.u_clock_core.oEditState);
        $finish;
      end

      rPrevMin = dut.u_watch_top.u_clock_core.oMin;
      press_button_u();
      repeat (20) @(posedge iClk);
      if (rPrevMin == 59) rExpectedMin = 0;
      else                rExpectedMin = rPrevMin + 1;
      if (dut.u_watch_top.u_clock_core.oMin !== rExpectedMin[6:0]) begin
        $display("FAIL CASE2: minute edit mismatch exp=%0d got=%0d", rExpectedMin, dut.u_watch_top.u_clock_core.oMin);
        $finish;
      end

      press_button_r();
      repeat (20) @(posedge iClk);
      if (dut.u_watch_top.u_clock_core.oEditState !== 2'd1) begin
        $display("FAIL CASE2: edit state should return to EDIT_SEC(1), got %0d", dut.u_watch_top.u_clock_core.oEditState);
        $finish;
      end

      rPrevSec = dut.u_watch_top.u_clock_core.oSec;
      press_button_d();
      repeat (20) @(posedge iClk);
      if (rPrevSec == 0) rExpectedSec = 59;
      else               rExpectedSec = rPrevSec - 1;
      if (dut.u_watch_top.u_clock_core.oSec !== rExpectedSec[6:0]) begin
        $display("FAIL CASE2: second edit mismatch exp=%0d got=%0d", rExpectedSec, dut.u_watch_top.u_clock_core.oSec);
        $finish;
      end

      press_button_c();
      repeat (20) @(posedge iClk);
      if (dut.u_watch_top.u_clock_core.oEditState !== 2'd0) begin
        $display("FAIL CASE2: should exit edit and return RUN(0), got %0d", dut.u_watch_top.u_clock_core.oEditState);
        $finish;
      end
      $display("CASE2 pass");
    end
  endtask

  // -----------------------------------------------------------------------
  // Case3: UART toggle policy
  // -----------------------------------------------------------------------
  task run_case3;
    begin
      $display("CASE3 start: uart toggle policy");
      iSw0 = 1'b1;
      iSw1 = 1'b1;
      iSw2 = 1'b0;
      iSw3 = 1'b0;
      repeat (20) @(posedge iClk);

      send_uart_byte("x");
      repeat (20) @(posedge iClk);
      if ((dut.wWatchMode !== 1'b1) || (dut.wWatchDisplay !== 1'b1) || (dut.wDisplaySelect !== 2'b00)) begin
        $display("FAIL CASE3: clear toggle baseline mismatch");
        $finish;
      end

      send_uart_byte("5");
      repeat (20) @(posedge iClk);
      if (dut.wDisplaySelect !== 2'b01) begin
        $display("FAIL CASE3: display should be SR04 after '5', got %b", dut.wDisplaySelect);
        $finish;
      end

      send_uart_byte("6");
      repeat (20) @(posedge iClk);
      if (dut.wDisplaySelect !== 2'b10) begin
        $display("FAIL CASE3: display should be DHT11 after '6', got %b", dut.wDisplaySelect);
        $finish;
      end

      send_uart_byte("6");
      repeat (20) @(posedge iClk);
      if (dut.wDisplaySelect !== 2'b01) begin
        $display("FAIL CASE3: display should return SR04 after second '6', got %b", dut.wDisplaySelect);
        $finish;
      end

      send_uart_byte("0");
      repeat (20) @(posedge iClk);
      if (dut.wWatchMode !== 1'b0) begin
        $display("FAIL CASE3: watch mode should toggle to stopwatch(0), got %b", dut.wWatchMode);
        $finish;
      end

      send_uart_byte("3");
      repeat (20) @(posedge iClk);
      if (dut.wWatchDisplay !== 1'b0) begin
        $display("FAIL CASE3: watch display should toggle to sec:cs(0), got %b", dut.wWatchDisplay);
        $finish;
      end

      send_uart_byte("x");
      repeat (20) @(posedge iClk);
      if ((dut.wWatchMode !== 1'b1) || (dut.wWatchDisplay !== 1'b1) || (dut.wDisplaySelect !== 2'b00)) begin
        $display("FAIL CASE3: clear toggle restore mismatch");
        $finish;
      end
      $display("CASE3 pass");
    end
  endtask

  // -----------------------------------------------------------------------
  // Case4: UART watch report
  // -----------------------------------------------------------------------
  task run_case4;
    begin
      $display("CASE4 start: watch report token");
      send_uart_byte("w");
      wait_tx_token("W", "A", "T", "C", "H", 8'd0, 5);
      $display("CASE4 pass");
    end
  endtask

  // -----------------------------------------------------------------------
  // Case5: SR04 select/start/report
  // -----------------------------------------------------------------------
  task run_case5;
    begin
      $display("CASE5 start: sr04 path");
      send_uart_byte("5");
      repeat (20) @(posedge iClk);
      if (dut.wDisplaySelect !== 2'b01) begin
        $display("FAIL CASE5: display should be SR04 before start, got %b", dut.wDisplaySelect);
        $finish;
      end

      fork
        simulate_sr04_echo_cm(25);
        send_uart_byte("c");
      join

      wait(dut.wSr04DistanceValid == 1'b1);
      if ((dut.wSr04DistanceCm < 10'd24) || (dut.wSr04DistanceCm > 10'd26)) begin
        $display("FAIL CASE5: sr04 distance out of range, got %0d", dut.wSr04DistanceCm);
        $finish;
      end

      send_uart_byte("s");
      wait_tx_token("S", "R", "0", "4", " ", 8'd0, 5);
      $display("CASE5 pass");
    end
  endtask

  // -----------------------------------------------------------------------
  // Case6: DHT11 select/start/report
  // -----------------------------------------------------------------------
  task run_case6;
    begin
      $display("CASE6 start: dht11 path");
      send_uart_byte("6");
      repeat (20) @(posedge iClk);
      if (dut.wDisplaySelect !== 2'b10) begin
        $display("FAIL CASE6: display should be DHT11 before start, got %b", dut.wDisplaySelect);
        $finish;
      end

      fork
        begin
          dht11_respond_once(8'd44, 8'd0, 8'd23, 8'd0);
        end
        begin
          send_uart_byte("c");
        end 
      join

      wait(dut.wDhtDataValid == 1'b1);
      if (dut.wDhtHumInt !== 8'd44) begin
        $display("FAIL CASE6: humidity mismatch, got %0d", dut.wDhtHumInt);
        $finish;
      end
      if (dut.wDhtTempInt !== 8'd23) begin
        $display("FAIL CASE6: temperature mismatch, got %0d", dut.wDhtTempInt);
        $finish;
      end

      send_uart_byte("t");
      wait_tx_token("T", "E", "M", "P", " ", 8'd0, 5);

      send_uart_byte("h");
      wait_tx_token("H", "U", "M", " ", 8'd0, 8'd0, 4);
      $display("CASE6 pass");
    end
  endtask

  initial begin
    // Global watchdog
    #(150_000_000);
    $display("FAIL: tb_top global timeout");
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
        #(BIT_PERIOD_NS);

        rTxLastByte = rTxCaptured;
        if (rTxCount < 1024) rTxLog[rTxCount] = rTxCaptured;
        rTxCount = rTxCount + 1;
        -> evTxByte;

        $display("[tb_top] TX byte[%0d]: 0x%02h (%c)", rTxCount - 1, rTxCaptured, rTxCaptured);
      end
    end
  end
  
  `define CASE6
  initial begin
    iClk = 1'b0;
    iRst = 1'b1;
    iRx  = 1'b1;

    iSw0 = 1'b1;
    iSw1 = 1'b1;
    iSw2 = 1'b0;
    iSw3 = 1'b0;

    iBtnC = 1'b0;
    iBtnU = 1'b0;
    iBtnD = 1'b0;
    iBtnL = 1'b0;
    iBtnR = 1'b0;
    iSr04Echo = 1'b0;
    rDht11DriveLow = 1'b0;

    rTxCount = 0;
    rTxLastByte = 8'd0;
    for (i = 0; i < 1024; i = i + 1) begin
      rTxLog[i] = 8'd0;
    end

    repeat (10) @(posedge iClk);
    iRst = 1'b0;
    repeat (20) @(posedge iClk);
    // -----------------------------------------------------------------------
    // Case Selection (`ifdef)
    // Build define example: -DCASE1 ... -DCASE6
    // If no case macro is defined, run all cases in order.
    // -----------------------------------------------------------------------
    `ifdef CASE1
        run_case1();
    `elsif CASE2
        run_case2();
    `elsif CASE3
        run_case3();
    `elsif CASE4
        run_case4();
    `elsif CASE5
        run_case5();
    `elsif CASE6
        send_uart_byte("5");//if case6 run alone
        run_case6();
    `else
        run_case1();
        run_case2();
        run_case3();
        run_case4();
        run_case5();
        run_case6();
    `endif

    //$display("tb_top finished: tx_count=%0d", rTxCount);
    $finish;
  end

endmodule
