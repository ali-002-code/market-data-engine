`timescale 1ns/1ps

// Collects 8 incoming bytes (big-endian) into one 64-bit message word.
// Input side:  s_data / s_valid / s_ready / s_last  (byte stream)
// Output side: msg_out / msg_valid                   (one pulse per full message)
//
// A byte is accepted only when s_valid && s_ready are both high on a clock edge.
// msg_valid pulses for exactly one cycle when the 8th byte of a message lands.
module stream_framer
  import md_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,

  // byte-stream input
  input  logic [7:0]  s_data,
  input  logic        s_valid,
  output logic        s_ready,
  input  logic        s_last,

  // message-word output
  output logic [63:0] msg_out,
  output logic        msg_valid
);

  // Byte index within the current message: 0..7
  logic [2:0] byte_idx;
  logic [63:0] shift_reg;

  // We can always accept a byte in this simple design (no internal stall).
  assign s_ready = 1'b1;

  wire accept = s_valid && s_ready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      byte_idx  <= 3'd0;
      shift_reg <= 64'd0;
      msg_out   <= 64'd0;
      msg_valid <= 1'b0;
    end else begin
      msg_valid <= 1'b0;  // default: only high the cycle a message completes

      if (accept) begin
        // Shift the new byte into the low end; byte 0 ends up in the MSB
        // after 8 shifts, giving big-endian order.
        shift_reg <= {shift_reg[55:0], s_data};

        if (byte_idx == 3'd7) begin
          msg_out   <= {shift_reg[55:0], s_data};
          msg_valid <= 1'b1;
          byte_idx  <= 3'd0;
        end else begin
          byte_idx <= byte_idx + 3'd1;
        end
      end
    end
  end

endmodule
