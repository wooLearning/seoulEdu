/*
[MODULE_INFO_START]
Name: uart_rx
Role: UART Receiver (Serial to Parallel)
Summary:
  - Receives asynchronous serial data on `iRx`
  - Uses 16x oversampling tick (`iTick16x`) for noise immunity and synchronization
  - Implements a state machine to detect Start Bit, shift in 8 Data Bits, and check Stop Bit
  - Outputs parallel byte `oData` and `oValid` strobe upon successful reception
StateDescription:
  - IDLE: Monitor Rx line for Start Bit (falling edge)
  - START: Verify Start Bit stability (center sampling)
  - DATA: Shift in 8 bits of data (LSB first)
  - STOP: Verify Stop Bit (high) and assert Valid signal
[MODULE_INFO_END]
*/

`timescale 1ns / 1ps

module uart_rx (
  input  wire       iClk,
  input  wire       iRst, // Active High Reset
  input  wire       iTick16x, // 16x Baud Rate Tick
  input  wire       iRx,
  output wire [7:0] oData,
  output wire       oValid
);

  localparam [1:0] IDLE  = 2'b00;
  localparam [1:0] START = 2'b01;
  localparam [1:0] DATA  = 2'b10;
  localparam [1:0] STOP  = 2'b11;

  reg [1:0] rCurState, rNxtState;

  // Datapath Registers
  reg [7:0] rData;
  reg [2:0] rBitCnt;
  reg [3:0] rTickCnt;
  reg       rValid;

  // Synchronizers
  reg  rRxSync1, rRxSync2;
  wire wRxSynced;

  // Input Synchronization
  always @(posedge iClk or posedge iRst) begin
    if (iRst) begin
      rRxSync1 <= 1'b1;
      rRxSync2 <= 1'b1;
    end else begin
      rRxSync1 <= iRx;
      rRxSync2 <= rRxSync1;
    end
  end

  // 1. State Register Update
  always @(posedge iClk or posedge iRst) begin
    if (iRst)   rCurState <= IDLE;
    else        rCurState <= rNxtState;
  end

  // 2. Next State Logic
  always @(*) begin
    rNxtState = rCurState; // Default

    case (rCurState)
      IDLE: begin
        // Falling edge detection logic could be added, but checking level on idle is simplest
        if (wRxSynced == 1'b0) begin 
          rNxtState = START;
        end
      end

      START: begin
        if (iTick16x) begin
          if (rTickCnt == 7) begin
            if (wRxSynced == 1'b0) rNxtState = DATA;
            else                   rNxtState = IDLE; // Glitch
          end
        end
      end

      DATA: begin
        if (iTick16x && (rTickCnt == 15)) begin
          if (rBitCnt == 7) rNxtState = STOP;
        end
      end

      STOP: begin
        if (iTick16x && (rTickCnt == 15)) begin
          rNxtState = IDLE;
        end
      end

      default: rNxtState = IDLE;
    endcase
  end

  // 3. Datapath Logic (Sequential)
  always @(posedge iClk or posedge iRst) begin
    if (iRst) begin
      rData    <= 0;
      rBitCnt  <= 0;
      rTickCnt <= 0;
      rValid   <= 1'b0;
    end 
    else begin
      
      // Default: Valid pulse lasts only 1 cycle (when set)
      rValid <= 1'b0; 

      case (rCurState)
        IDLE: begin
          rTickCnt <= 0;
          rBitCnt  <= 0;
        end

        START: begin
          if (iTick16x) begin
            if (rTickCnt == 7) begin
              rTickCnt <= 0; // Reset for DATA state
            end else begin
              rTickCnt <= rTickCnt + 1;
            end
          end
        end

        DATA: begin
          if (iTick16x) begin
            if (rTickCnt == 15) begin
              rTickCnt <= 0;
              rData    <= {wRxSynced, rData[7:1]}; // Shift LSB first
              
              if (rBitCnt != 7) begin
                rBitCnt <= rBitCnt + 1;
              end
            end else begin
              rTickCnt <= rTickCnt + 1;
            end
          end
        end

        STOP: begin
          if (iTick16x) begin
            if (rTickCnt == 15) begin
              rTickCnt <= 0;
              if (wRxSynced == 1'b1) begin
                rValid <= 1'b1; // Output Valid Pulse
              end
            end else begin
              rTickCnt <= rTickCnt + 1;
            end
          end
        end
      endcase
    end
  end

  assign oData     = rData;
  assign oValid    = rValid;
  assign wRxSynced = rRxSync2;
  assign wRxOk     = ~rRxSync1 && rRxSync2;

endmodule



