/*
[MODULE_INFO_START]
Name: Fifo
Role: First-In First-Out Data Buffer
Summary:
  - Parameterized FIFO for UART data buffering (RX and TX).
  - Implements circular buffer with Read/Write pointers.
  - Provides Full/Empty status flags.
  - Used to decouple UART timing from the main control loop.
StateDescription:
  - IDLE: No operation.
  - PUSH_ONLY: Only write occurring.
  - POP_ONLY: Only read occurring.
  - PUSH_POP: Simultaneous read and write.
[MODULE_INFO_END]
*/

`timescale 1ns / 1ps

module Fifo #(
  parameter integer P_DATA_WIDTH = 8,
  parameter integer P_FIFO_DEPTH = 16
)(
  input  wire                    iClk,
  input  wire                    iRst,

  // Write Interface
  input  wire                    iPush,
  input  wire [P_DATA_WIDTH-1:0] iPushData,
  output wire                    oFull,

  // Read Interface
  input  wire                    iPop,
  output wire [P_DATA_WIDTH-1:0] oPopData,
  output wire                    oEmpty
);

  localparam integer LP_ADDR_WIDTH = (P_FIFO_DEPTH <= 2) ? 1 : $clog2(P_FIFO_DEPTH);
  localparam integer LP_CNT_WIDTH  = $clog2(P_FIFO_DEPTH + 1);

  localparam [1:0] IDLE     = 2'd0;
  localparam [1:0] PUSH_ONLY = 2'd1;
  localparam [1:0] POP_ONLY  = 2'd2;
  localparam [1:0] PUSH_POP  = 2'd3;

  reg [1:0] rCurState;
  reg [1:0] rNxtState;

  reg [P_DATA_WIDTH-1:0] rMem [0:P_FIFO_DEPTH-1];
  reg [LP_ADDR_WIDTH-1:0] rWrPtr;
  reg [LP_ADDR_WIDTH-1:0] rRdPtr;
  reg [LP_CNT_WIDTH-1:0]  rCount;

  wire wPushReq;
  wire wPopReq;

  function [LP_ADDR_WIDTH-1:0] f_inc_ptr;
    input [LP_ADDR_WIDTH-1:0] ptr;
    begin
      if (ptr == (P_FIFO_DEPTH - 1)) f_inc_ptr = {LP_ADDR_WIDTH{1'b0}};
      else                           f_inc_ptr = ptr + 1'b1;
    end
  endfunction

  assign oEmpty   = (rCount == {LP_CNT_WIDTH{1'b0}});
  assign oFull    = (rCount == P_FIFO_DEPTH[LP_CNT_WIDTH-1:0]);
  assign wPushReq = iPush && !oFull;
  assign wPopReq  = iPop && !oEmpty;

  // Read data is current read pointer location.
  assign oPopData = rMem[rRdPtr];

  always @(*) begin
    rNxtState = IDLE;

    case (rCurState)
      IDLE, PUSH_ONLY, POP_ONLY, PUSH_POP: begin
        case ({wPushReq, wPopReq})
          2'b10: rNxtState = PUSH_ONLY;
          2'b01: rNxtState = POP_ONLY;
          2'b11: rNxtState = PUSH_POP;
          default: rNxtState = IDLE;
        endcase
      end

      default: rNxtState = IDLE;
    endcase
  end

  always @(posedge iClk or posedge iRst) begin
    if (iRst) begin
      rCurState <= IDLE;
      rWrPtr    <= {LP_ADDR_WIDTH{1'b0}};
      rRdPtr    <= {LP_ADDR_WIDTH{1'b0}};
      rCount    <= {LP_CNT_WIDTH{1'b0}};
    end else begin
      rCurState <= rNxtState;

      case (rNxtState)
        PUSH_ONLY: begin
          rMem[rWrPtr] <= iPushData;
          rWrPtr       <= f_inc_ptr(rWrPtr);
          rCount       <= rCount + 1'b1;
        end

        POP_ONLY: begin
          rRdPtr <= f_inc_ptr(rRdPtr);
          rCount <= rCount - 1'b1;
        end

        PUSH_POP: begin
          rMem[rWrPtr] <= iPushData;
          rWrPtr       <= f_inc_ptr(rWrPtr);
          rRdPtr       <= f_inc_ptr(rRdPtr);
        end

        default: begin
          // IDLE
        end
      endcase
    end
  end

endmodule
