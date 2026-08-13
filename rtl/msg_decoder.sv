`timescale 1ns/1ps

// Pure combinational. Slices one 64-bit message word into typed fields.
// Big-endian byte layout:
//   byte 0 [63:56] type
//   byte 1 [55:48] side (bit 0 = side, so bit 48)
//   bytes 2-3 [47:32] price
//   bytes 4-5 [31:16] qty
//   bytes 6-7 [15:0]  reserved (sequence number in Tier 3)
module msg_decoder
  import md_pkg::*;
(
  input  logic [63:0] msg_in,
  output msg_type_e   msg_type,
  output logic        msg_side,
  output logic [15:0] msg_price,
  output logic [15:0] msg_qty
);

  assign msg_type  = msg_type_e'(msg_in[63:56]);
  assign msg_side  = msg_in[48];
  assign msg_price = msg_in[47:32];
  assign msg_qty   = msg_in[31:16];

endmodule
