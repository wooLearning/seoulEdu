/*
[MODULE_INFO_START]
Name: dht11_controller
Role: DHT11 Temperature & Humidity Sensor Interface
Summary:
  - Implements a single-wire communication protocol for DHT11
  - Generates the start signal (18ms Low, 30us High)
  - Captures 40 bits of data (Humidity Int/Dec, Temp Int/Dec, Checksum)
  - Validates integrity via checksum calculation
  - Outputs parsed Integer Humidity (`oHumInt`) and Temperature (`oTempInt`) upon valid reception
StateDescription:
  - IDLE: Wait for start command
  - START_LOW: Drive line Low for >18ms
  - START_HIGH: Release line, wait 30us
  - WAIT_LOW/HIGH: Wait for sensor response (ACK)
  - LOW_BIT: Wait for 50us low sync slot
  - HIGH_BIT: Measure high pulse width to determine bit value (0: ~26-28us, 1: ~70us)
  - DONE: Verify checksum and update output registers
[MODULE_INFO_END]
*/

`timescale 1ns / 1ps

module dht11_controller #(
  parameter integer START_LOW_MS      = 18,
  parameter integer START_RELEASE_US  = 30,
  parameter integer RESP_TIMEOUT_US   = 200,
  parameter integer BIT_TIMEOUT_US    = 120,
  parameter integer BIT_LOW_US        = 50,
  parameter integer BIT_HIGH_THRESHOLD_US = 40
)(
  input  wire      iClk,
  input  wire      iRst,
  input  wire      iTickUs,
  input  wire      iStart,
  inout  wire      ioData,
  output reg [7:0] oHumInt,
  output reg [7:0] oTempInt,
  output reg       oDataValid
);

  localparam integer START_LOW_US         = START_LOW_MS * 1000;

  // FSM states
  localparam [3:0] IDLE       = 4'd0;
  localparam [3:0] START_LOW  = 4'd1;
  localparam [3:0] START_HIGH = 4'd2;
  localparam [3:0] WAIT_LOW   = 4'd3;
  localparam [3:0] WAIT_HIGH  = 4'd4;
  localparam [3:0] LOW_BIT    = 4'd5;
  localparam [3:0] HIGH_BIT   = 4'd6;
  localparam [3:0] DONE       = 4'd7;

  reg [3:0]  rCurState;      // 현재 FSM 상태 (Current FSM State)
  reg [3:0]  rNxtState;      // 다음 FSM 상태 (Next FSM State)

  reg [31:0] rStepUsCnt;     // 상태 유지 시간 측정용 마이크로초 카운터 (Microsecond counter for state duration)
  reg [31:0] rHighUsCnt;     // 비트 High 구간 길이 측정 카운터 (Counter for measuring bit high pulse width)

  reg [5:0]  rBitIdx;        // 수신 비트 인덱스 (0~39) (Bit index counter)
  reg [39:0] rDataShift;     // 수신 데이터 시프트 레지스터 (40-bit Shift Register for received data)
  reg        rHighSeen;      // High 신호 감지 플래그 (Flag for detecting high signal) data 길이 0,1 구분용
  reg        rRespHighSeen;  // 센서 응답 High 신호 감지 플래그 (Flag for detecting sensor response high signal)

  reg rDataSync1;            // 입력 동기화 1단계 (Input Synchronizer Stage 1)
  reg rDataSync2;            // 입력 동기화 2단계 (Input Synchronizer Stage 2)

  wire wDataIn;              // ioData 입력 버퍼 (Buffered input from ioData)
  wire [7:0] wHumIntField;   // 습도 정수부 필드 (Humidity Integer Field)
  wire [7:0] wHumDecField;   // 습도 소수부 필드 (Humidity Decimal Field)
  wire [7:0] wTempIntField;  // 온도 정수부 필드 (Temperature Integer Field)
  wire [7:0] wTempDecField;  // 온도 소수부 필드 (Temperature Decimal Field)
  wire [7:0] wChecksumField; // 수신 체크섬 필드 (Received Checksum Field)
  wire [7:0] wChecksumCalc;  // 계산된 체크섬 (Calculated Checksum)
  wire       wBitValue;      // 펄스 폭에 따른 비트 판정 값 (Decoded Bit Value based on pulse width)

  assign ioData = (rCurState == START_LOW) ? 1'b0 : 1'bz;
  assign wDataIn = ioData;

  assign wHumIntField   = rDataShift[39:32];
  assign wHumDecField   = rDataShift[31:24];
  assign wTempIntField  = rDataShift[23:16];
  assign wTempDecField  = rDataShift[15:8];
  assign wChecksumField = rDataShift[7:0];
  assign wChecksumCalc  = wHumIntField + wHumDecField + wTempIntField + wTempDecField;

  // DHT11 bit-high threshold:
  // 0 -> ~26-28us high, 1 -> ~70us high
  assign wBitValue = (rHighUsCnt >= BIT_HIGH_THRESHOLD_US);

  // Input synchronizer
  always @(posedge iClk or posedge iRst) begin
    if (iRst) begin
      rDataSync1 <= 1'b1;
      rDataSync2 <= 1'b1;
    end else begin
      rDataSync1 <= wDataIn;
      rDataSync2 <= rDataSync1;
    end
  end

  // Next-state logic
  always @(*) begin
    rNxtState = rCurState;

    case (rCurState)
      IDLE: begin //0
        if (iStart) rNxtState = START_LOW;
        else        rNxtState = IDLE;
      end

      START_LOW: begin //1
        if (rStepUsCnt >= START_LOW_US) rNxtState = START_HIGH;
        else                            rNxtState = START_LOW;
      end

      START_HIGH: begin //2
        if (rStepUsCnt >= START_RELEASE_US) rNxtState = WAIT_LOW;
        else                                rNxtState = START_HIGH;
      end

      WAIT_LOW: begin //3
        if (!rDataSync2)                    rNxtState = WAIT_HIGH;
        else if (rStepUsCnt >= RESP_TIMEOUT_US) rNxtState = IDLE;
        else                                rNxtState = WAIT_LOW;
      end

      WAIT_HIGH: begin //4
        if (!rRespHighSeen) begin
          if (rDataSync2)                      rNxtState = WAIT_HIGH;
          else if (rStepUsCnt >= RESP_TIMEOUT_US) rNxtState = IDLE;
          else                                 rNxtState = WAIT_HIGH;
        end else begin
          if (!rDataSync2)                     rNxtState = LOW_BIT;
          else if (rStepUsCnt >= RESP_TIMEOUT_US) rNxtState = IDLE;
          else                                 rNxtState = WAIT_HIGH;
        end
      end

      LOW_BIT: begin //5
        if (rStepUsCnt >= BIT_LOW_US)       rNxtState = HIGH_BIT;
        else                                rNxtState = LOW_BIT;
      end

      HIGH_BIT: begin //6
        if (rHighSeen && !rDataSync2) begin
          if (rBitIdx >= 39) rNxtState = DONE;
          else               rNxtState = LOW_BIT;
        end else if (rStepUsCnt >= BIT_TIMEOUT_US) begin
          rNxtState = IDLE;
        end else begin
          rNxtState = HIGH_BIT;
        end
      end

      DONE: rNxtState = IDLE;

      default: rNxtState = IDLE;
    endcase
  end

  // State register
  always @(posedge iClk or posedge iRst) begin
    if (iRst) rCurState <= IDLE;
    else      rCurState <= rNxtState;
  end

  // Datapath
  always @(posedge iClk or posedge iRst) begin
    if (iRst) begin
      rStepUsCnt   <= 32'd0;
      rHighUsCnt   <= 32'd0;
      rBitIdx      <= 6'd0;
      rDataShift   <= 40'd0;
      rHighSeen    <= 1'b0;
      rRespHighSeen <= 1'b0;
      oHumInt      <= 8'd0;
      oTempInt     <= 8'd0;
      oDataValid   <= 1'b0;
    end 
    else begin
      // Step counter resets on state transition, otherwise counts in 1us ticks.
      if (rNxtState != rCurState) rStepUsCnt <= 32'd0; 
      else if (iTickUs)           rStepUsCnt <= rStepUsCnt + 1'b1;

      // Enter bit receive phase.
      if ((rCurState == WAIT_HIGH) && (rNxtState == LOW_BIT)) begin
        rBitIdx       <= 6'd0;
        rDataShift    <= 40'd0;
        rRespHighSeen <= 1'b0;
      end

      // In WAIT_HIGH, first observe response-high, then wait for falling edge to first bit-low.
      if ((rCurState == WAIT_LOW) && (rNxtState == WAIT_HIGH)) begin
        rRespHighSeen <= 1'b0;
      end
      if ((rCurState == WAIT_HIGH) && (rNxtState == WAIT_HIGH) && rDataSync2) begin
        rRespHighSeen <= 1'b1;
      end

      // Prepare high-pulse measurement.
      if ((rCurState == LOW_BIT) && (rNxtState == HIGH_BIT)) begin
        rHighUsCnt <= 32'd0;
        rHighSeen  <= 1'b0;
      end

      // Track high pulse width while HIGH_BIT is active.
      if ((rCurState == HIGH_BIT) && (rNxtState == HIGH_BIT)) begin
        if (rDataSync2) rHighSeen <= 1'b1;
        if (iTickUs && rDataSync2) rHighUsCnt <= rHighUsCnt + 1'b1;
      end

      // Capture one bit immediately when high pulse ends.
      if ((rCurState == HIGH_BIT) && ((rNxtState == LOW_BIT) || (rNxtState == DONE))) begin
        rDataShift <= {rDataShift[38:0], wBitValue};
      end

      // Next bit index.
      if ((rCurState == HIGH_BIT) && (rNxtState == LOW_BIT)) begin
        rBitIdx <= rBitIdx + 1'b1;
      end

      // Validate and commit.
      if (rCurState == DONE) begin
        if (wChecksumCalc == wChecksumField) begin
          oHumInt    <= wHumIntField;
          oTempInt   <= wTempIntField;
          oDataValid <= 1'b1;
        end
        else begin  
          oHumInt    <= 0;
          oTempInt   <= 0;
          oDataValid <= 1'b0;
        end
      end
    end
  end

endmodule
