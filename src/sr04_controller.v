/*
[MODULE_INFO_START]
Name: sr04_controller
Role: HC-SR04 Ultrasonic Distance Sensor Interface
Summary:
  - Controls HC-SR04 ultrasonic sensor for distance measurement
  - Generates 10us Trigger pulse (`oTrig`)
  - Measures the duration of the Echo pulse (`iEcho`) in microseconds
  - Converts measured time to distance (cm) using `Distance = (Time * 340m/s) / 2`
StateDescription:
  - IDLE: Waiting for Start signal
  - START: Generate 10us Trigger pulse
  - WAIT_ECHO: Wait for Echo signal rising edge
  - MEASURE: Count 1us ticks while Echo is High; calculate distance
  - DONE: Validate measurement and update output
[MODULE_INFO_END]
*/

`timescale 1ns / 1ps

module sr04_controller #(
  parameter integer TRIG_US               = 10,
  parameter integer WAIT_ECHO_TIMEOUT_US  = 30_000,//30ms
  parameter integer MEASURE_TIMEOUT_US    = 30_000
) (
  input  wire       iClk,
  input  wire       iRst,
  input  wire       iTickUs,
  input  wire       iEcho,
  input  wire       iStart,
  output reg        oTrig,
  output reg [9:0]  oDistanceCm,
  output reg        oDistanceValid
);

  localparam US_PER_CM       = 58; // us/cm from HC-SR04 datasheet

  // FSM states (reference style): IDLE -> START -> WAIT_ECHO -> MEASURE -> DONE
  localparam [2:0] IDLE      = 3'd0;
  localparam [2:0] START     = 3'd1;
  localparam [2:0] WAIT_ECHO = 3'd2;
  localparam [2:0] MEASURE   = 3'd3;
  localparam [2:0] DONE      = 3'd4;

  reg [2:0]  rCurState;
  reg [2:0]  rNxtState;
  reg [31:0] rTrigCnt;
  reg [31:0] rStepUsCnt;
  reg [31:0] rEchoUsCnt;
  reg [5:0]  rCnt58us;
  reg [9:0]  rDist;

  reg rEchoSync1;
  reg rEchoSync2;

  // Echo synchronizer
  always @(posedge iClk or posedge iRst) begin
    if (iRst) begin
      rEchoSync1 <= 1'b0;
      rEchoSync2 <= 1'b0;
    end else begin
      rEchoSync1 <= iEcho;
      rEchoSync2 <= rEchoSync1;
    end
  end

  always @(*) begin
    rNxtState = rCurState;

    case (rCurState)
      IDLE: begin
        if (iStart) rNxtState = START;
        else        rNxtState = IDLE;
      end

      START: begin
        if (rTrigCnt > TRIG_US ) rNxtState = WAIT_ECHO; //트리거us 10us para선언
        else                           rNxtState = START;
      end

      WAIT_ECHO: begin
        if (rEchoSync2)                             rNxtState = MEASURE;
        else if (rStepUsCnt >= WAIT_ECHO_TIMEOUT_US) rNxtState = IDLE; //30000카운트했는데 
        else                                        rNxtState = WAIT_ECHO;
      end

      MEASURE: begin
        if (!rEchoSync2)                          rNxtState = DONE;
        else if (rStepUsCnt >= MEASURE_TIMEOUT_US) rNxtState = IDLE;
        else                                      rNxtState = MEASURE;
      end

      DONE: rNxtState = IDLE;

      default: rNxtState = IDLE;
    endcase
  end


  always @(posedge iClk or posedge iRst) begin
    if (iRst) rCurState <= IDLE;
    else      rCurState <= rNxtState;
  end

  always @(posedge iClk or posedge iRst) begin
    if (iRst) begin
      rTrigCnt <= 32'd0;
      rStepUsCnt <= 32'd0;
      rEchoUsCnt <= 32'd0;
      rCnt58us <= 6'd0;
      rDist <= 10'd0;
      oTrig          <= 1'b0;
      oDistanceCm    <= 10'd0;
      oDistanceValid <= 1'b0;
    end else begin
      case (rCurState)
        IDLE: begin
          oTrig <= 1'b0;
          rStepUsCnt <= 32'd0;

          if (rNxtState == START) begin
            rTrigCnt <= 32'd0;
            oDistanceValid <= 1'b0;
          end
        end

        START: begin
          oTrig <= 1'b1;
          rStepUsCnt <= 32'd0;

          if (rNxtState == WAIT_ECHO) begin
            oTrig          <= 1'b0;
            rStepUsCnt <= 32'd0;
            rEchoUsCnt <= 32'd0;
            rCnt58us <= 6'd0;
            rDist <= 10'd0;
            rTrigCnt<=1'b0;
          end 
          else if (iTickUs) begin
            rTrigCnt <= rTrigCnt + 1'b1;
          end
        end

        WAIT_ECHO: begin
          oTrig <= 1'b0;
          
          if (rNxtState == MEASURE) begin
            rStepUsCnt <= 32'd0;
            rEchoUsCnt <= 32'd0;
            rCnt58us <= 6'd0;
            rDist <= 10'd0;
          end else if (rNxtState == WAIT_ECHO && iTickUs) begin
            rStepUsCnt <= rStepUsCnt + 1'b1;
          end
        end

        MEASURE: begin
          oTrig <= 1'b0;

          if ((rNxtState == MEASURE) && rEchoSync2 && iTickUs) begin
            rStepUsCnt <= rStepUsCnt + 1'b1;
            rEchoUsCnt <= rEchoUsCnt + 1'b1;

            if (rCnt58us == (US_PER_CM - 1)) begin
              rCnt58us <= 6'd0;
              rDist <= rDist + 1'b1;
            end 
            else begin
              rCnt58us <= rCnt58us + 1'b1;
            end
          end
        end

        DONE: begin
          oTrig <= 1'b0;

          if (rEchoUsCnt > 0) begin
            oDistanceCm    <= rDist;
            oDistanceValid <= 1'b1;
          end
        end

        default: begin
          oTrig <= 1'b0;
        end
      endcase
    end
  end

endmodule
