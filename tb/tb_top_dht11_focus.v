/*
[TB_INFO_START]
Name: tb_top_dht11_focus
Target: Top
Role: Top의 DHT11 경로 집중 검증 테스트벤치
Scenario:
  - DHT11 표시 선택 상태에서 물리 버튼 C로 측정 시작
  - DHT11 단선 프로토콜 응답 모델로 2회 연속 측정 데이터 주입
  - 첫 번째/두 번째 측정값이 각각 올바르게 반영되는지 확인
CheckPoint:
  - display select가 DHT11(2'b10)으로 유지되는지 확인
  - wDhtDataValid asserted 여부 및 Hum/Temp 값 검증
  - 연속 측정 시 값 갱신 동작 확인
[TB_INFO_END]
*/

`timescale 1ns / 1ps

module tb_top_dht11_focus;
  localparam integer CLK_PER_US      = 100;        // 100MHz
  localparam integer START_GUARD_CYC = 2_000_000;  // 20ms @100MHz
  localparam integer WAIT_GUARD_CYC  = 2_000_000;  // 20ms @100MHz

  reg iClk;
  reg iRst;
  reg iRx;

  reg iSw0, iSw1, iSw2, iSw3;
  reg iBtnC, iBtnU, iBtnD, iBtnL, iBtnR;
  reg iSr04Echo;

  reg  rDht11DriveLow;
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

  initial begin
    $dumpfile("tb_top_dht11_focus.vcd");
    $dumpvars(0, tb_top_dht11_focus);
  end

  // Simulation speed-up parameters (DUT 내부 DHT11 FSM)
  defparam dut.u_dht11_controller.START_LOW_MS     = 1;
  defparam dut.u_dht11_controller.START_RELEASE_US = 20;
  defparam dut.u_dht11_controller.RESP_TIMEOUT_US  = 250;
  defparam dut.u_dht11_controller.BIT_TIMEOUT_US   = 140;

  always #5 iClk = ~iClk;

  task wait_us(input integer n_us);
    integer i;
    begin
      for (i = 0; i < (n_us * CLK_PER_US); i = i + 1) @(posedge iClk);
    end
  endtask

  task press_button_c;
    begin
      // Raw button 입력 모델: 비동기 경계에서 눌림/해제
      @(negedge iClk); iBtnC = 1'b1;
      repeat (3) @(posedge iClk);
      @(negedge iClk); iBtnC = 1'b0;
    end
  endtask

  task wait_dht_idle;
    integer guard;
    begin
      guard = 0;
      while ((dut.u_dht11_controller.rCurState !== 4'd0) && (guard < WAIT_GUARD_CYC)) begin
        @(posedge iClk);
        guard = guard + 1;
      end
      if (dut.u_dht11_controller.rCurState !== 4'd0) begin
        $fatal(1, "timeout waiting dht idle");
      end
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

      // Host START_LOW -> START_HIGH 전이를 기다림
      guard = 0;
      while ((ioDht11Data !== 1'b0) && (guard < START_GUARD_CYC)) begin
        @(posedge iClk);
        guard = guard + 1;
      end
      if (ioDht11Data !== 1'b0) $fatal(1, "dht model timeout waiting host start low");

      guard = 0;
      while ((ioDht11Data !== 1'b1) && (guard < START_GUARD_CYC)) begin
        @(posedge iClk);
        guard = guard + 1;
      end
      if (ioDht11Data !== 1'b1) $fatal(1, "dht model timeout waiting host release");

      // Sensor ACK: 80us low + 80us high
      wait_us(30);
      rDht11DriveLow = 1'b1;
      wait_us(80);
      rDht11DriveLow = 1'b0;
      wait_us(80);

      // 40-bit payload + checksum
      dht_send_byte(hum_i);
      dht_send_byte(hum_d);
      dht_send_byte(temp_i);
      dht_send_byte(temp_d);
      dht_send_byte(checksum);

      // 마지막 비트 종료용 low
      rDht11DriveLow = 1'b1;
      wait_us(50);
      rDht11DriveLow = 1'b0;
    end
  endtask

  initial begin
    // Global watchdog
    #(60_000_000);
    $fatal(1, "tb_top_dht11_focus global timeout");
  end

  integer wait_timeout;
  reg [7:0] prev_hum;
  reg [7:0] prev_temp;

  initial begin
    iClk = 1'b0;
    iRst = 1'b1;
    iRx  = 1'b1;

    // DHT11 표시 선택: sw2=1(sensor), sw3=1(dht11)
    iSw0 = 1'b0;
    iSw1 = 1'b0;
    iSw2 = 1'b1;
    iSw3 = 1'b1;

    iBtnC = 1'b0;
    iBtnU = 1'b0;
    iBtnD = 1'b0;
    iBtnL = 1'b0;
    iBtnR = 1'b0;
    iSr04Echo = 1'b0;
    rDht11DriveLow = 1'b0;

    repeat (10) @(posedge iClk);
    iRst = 1'b0;

    if (dut.wDisplaySelect !== 2'b10) $fatal(1, "display source should be dht11 (2'b10)");
    wait_dht_idle();

    // Case 1
    fork
      dht11_respond_once(8'd44, 8'd0, 8'd23, 8'd0);
      press_button_c();
    join

    wait_timeout = 0;
    while ((dut.wDhtDataValid !== 1'b1) && (wait_timeout < WAIT_GUARD_CYC)) begin
      @(posedge iClk);
      wait_timeout = wait_timeout + 1;
    end
    if (dut.wDhtDataValid !== 1'b1) $fatal(1, "case1 data_valid timeout");
    if (dut.wDhtHumInt  !== 8'd44)  $fatal(1, "case1 humidity mismatch: %0d", dut.wDhtHumInt);
    if (dut.wDhtTempInt !== 8'd23)  $fatal(1, "case1 temperature mismatch: %0d", dut.wDhtTempInt);

    prev_hum  = dut.wDhtHumInt;
    prev_temp = dut.wDhtTempInt;
    wait_dht_idle();
    repeat (5) @(posedge iClk);

    // Case 2
    fork
      dht11_respond_once(8'd51, 8'd0, 8'd26, 8'd0);
      press_button_c();
    join

    wait_timeout = 0;
    while (((dut.wDhtHumInt == prev_hum) && (dut.wDhtTempInt == prev_temp)) && (wait_timeout < WAIT_GUARD_CYC)) begin
      @(posedge iClk);
      wait_timeout = wait_timeout + 1;
    end
    if ((dut.wDhtHumInt == prev_hum) && (dut.wDhtTempInt == prev_temp)) $fatal(1, "case2 value update timeout");
    if (dut.wDhtHumInt  !== 8'd51) $fatal(1, "case2 humidity mismatch: %0d", dut.wDhtHumInt);
    if (dut.wDhtTempInt !== 8'd26) $fatal(1, "case2 temperature mismatch: %0d", dut.wDhtTempInt);

    $display("tb_top_dht11_focus finished: hum=%0d temp=%0d", dut.wDhtHumInt, dut.wDhtTempInt);
    $finish;
  end

endmodule
