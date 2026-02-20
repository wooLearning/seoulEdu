/*
[MODULE_INFO_START]
Name: uart_tx
Role: UART Transmitter (Parallel to Serial)
Summary:
  - Transmits parallel byte `iData` serially on `oTx`
  - Driven by 16x oversampling tick (`iTick16x`) for bit timing
  - Generates Start Bit (Low), 8 Data Bits (LSB first), and Stop Bit (High)
  - Assert `oBusy` while transmission is in progress
StateDescription:
  - IDLE: Wait for `iValid` strobe
  - START: Drive Tx Low (Start Bit)
  - DATA: Shift out 8 bits of data
  - STOP: Drive Tx High (Stop Bit)
[MODULE_INFO_END]
*/

`timescale 1ns / 1ps

module uart_tx (
  input  wire       iClk,
  input  wire       iRst, // Active High Reset
  input  wire       iTick16x, // 16x Baud Rate Tick
  input  wire [7:0] iData,
  input  wire       iValid,
  output wire       oTx,
  output wire       oBusy
);

  localparam [1:0] IDLE  = 2'b00;
  localparam [1:0] START = 2'b01;
  localparam [1:0] DATA  = 2'b10;
  localparam [1:0] STOP  = 2'b11;

  reg [1:0] rCurState, rNxtState;

  // Datapath Registers
  reg [7:0] rShiftReg; // Shift Register for Data
  reg [2:0] rBitCnt;
  reg [3:0] rTickCnt;
  reg       rTx;

  // 1. State Register Update (Sequential)
  always @(posedge iClk or posedge iRst) begin
    if (iRst)   rCurState <= IDLE;
    else        rCurState <= rNxtState;
  end

  // 2. Next State Logic (Combinational)
  always @(*) begin
    rNxtState = rCurState; // Default: Hold State

    case (rCurState)
      IDLE: begin
        if (iValid) rNxtState = START;
      end

      START: begin
        if (iTick16x && (rTickCnt == 15)) begin
          rNxtState = DATA;
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

  // 3. Datapath & Output Logic (Sequential) - Shift Register Implementation
  always @(posedge iClk or posedge iRst) begin
    if (iRst) begin
      rShiftReg <= 0;
      rBitCnt   <= 0;
      rTickCnt  <= 0;
      rTx       <= 1'b1; // Idle High
    end else begin
      
      // Default Actions
      if (iTick16x) rTickCnt <= rTickCnt + 1;

      case (rCurState)
        IDLE: begin
          rTx <= 1'b1;
          rTickCnt <= 0;
          rBitCnt  <= 0;
          if (iValid) begin
            rShiftReg <= iData; // Load Data into Shift Register
          end
        end

        START: begin
          rTx <= 1'b0; // Start Bit
          if (iTick16x && (rTickCnt == 15)) begin
             rTickCnt <= 0; // Reset for next state
          end
        end

        DATA: begin
          // Output LSB of Shift Register
          rTx <= rShiftReg[0]; 
          
          if (iTick16x && (rTickCnt == 15)) begin
            rTickCnt <= 0;
            // Shift Right: {0, Data[7:1]}
            rShiftReg <= {1'b0, rShiftReg[7:1]};
            
            if (rBitCnt != 7) begin
              rBitCnt <= rBitCnt + 1;
            end
          end
        end

        STOP: begin
          rTx <= 1'b1; // Stop Bit
          if (iTick16x && (rTickCnt == 15)) begin
             rTickCnt <= 0;
          end
        end
      endcase
    end
  end

  assign oTx   = rTx;
  assign oBusy = (rCurState != IDLE);

endmodule



