/*
[MODULE_INFO_START]
Name: ex
Role: Example Module
Summary:
  - Minimal AND gate logic example
  - Demonstrates module structure and header conventions
[MODULE_INFO_END]
*/
`timescale 1ns/1ps
module ex (
    input  wire i_a,
    input  wire i_b,
    output wire o_y
);
assign o_y = i_a & i_b;
endmodule
