`timescale 1ns/1ps

// Top-level datapath. Wires the four Tier 1 modules in a line:
//   bytes -> stream_framer -> msg_decoder -> book_engine -> top_of_book -> outputs
//
// Latency (book-relevant): last byte accepted -> out_valid = 1 cycle
//   framer raises msg_valid on the 8th byte (combinational decoder adds 0),
//   book_engine registers the update and raises book_valid 1 cycle later,
//   top_of_book is combinational off the registered book state (adds 0).
// out_valid is book_valid: it pulses once per completed message.
module market_data_top
  import md_pkg::*;
#(
  parameter int NUM_LEVELS = 8
)(
  input  logic        clk,
  input  logic        rst_n,

  // byte-stream input
  input  logic [7:0]  s_data,
  input  logic        s_valid,
  output logic        s_ready,
  input  logic        s_last,

  // top-of-book outputs
  output logic [15:0] best_bid,
  output logic        best_bid_valid,
  output logic [15:0] best_ask,
  output logic        best_ask_valid,
  output logic [15:0] spread,
  output logic [16:0] mid_sum,
  output logic        tob_valid,
  output logic        out_valid   // pulses 1 cycle per completed message
);

  // framer -> decoder
  logic [63:0] msg_word;
  logic        msg_word_valid;

  // decoder -> book_engine
  msg_type_e   d_type;
  logic        d_side;
  logic [15:0] d_price;
  logic [15:0] d_qty;

  // book_engine -> top_of_book
  logic [NUM_LEVELS*16-1:0] bid_price_flat, bid_qty_flat;
  logic [NUM_LEVELS*16-1:0] ask_price_flat, ask_qty_flat;
  logic                     book_valid;

  stream_framer u_framer (
    .clk       (clk),
    .rst_n     (rst_n),
    .s_data    (s_data),
    .s_valid   (s_valid),
    .s_ready   (s_ready),
    .s_last    (s_last),
    .msg_out   (msg_word),
    .msg_valid (msg_word_valid)
  );

  msg_decoder u_decoder (
    .msg_in    (msg_word),
    .msg_type  (d_type),
    .msg_side  (d_side),
    .msg_price (d_price),
    .msg_qty   (d_qty)
  );

  book_engine #(.NUM_LEVELS(NUM_LEVELS)) u_book (
    .clk            (clk),
    .rst_n          (rst_n),
    .msg_valid      (msg_word_valid),
    .msg_type       (d_type),
    .msg_side       (d_side),
    .msg_price      (d_price),
    .msg_qty        (d_qty),
    .bid_price_flat (bid_price_flat),
    .bid_qty_flat   (bid_qty_flat),
    .ask_price_flat (ask_price_flat),
    .ask_qty_flat   (ask_qty_flat),
    .book_valid     (book_valid)
  );

  top_of_book #(.NUM_LEVELS(NUM_LEVELS)) u_tob (
    .bid_price_flat (bid_price_flat),
    .bid_qty_flat   (bid_qty_flat),
    .ask_price_flat (ask_price_flat),
    .ask_qty_flat   (ask_qty_flat),
    .best_bid       (best_bid),
    .best_bid_valid (best_bid_valid),
    .best_ask       (best_ask),
    .best_ask_valid (best_ask_valid),
    .spread         (spread),
    .mid_sum        (mid_sum),
    .tob_valid      (tob_valid)
  );

  assign out_valid = book_valid;

endmodule
