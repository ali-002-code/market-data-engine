`timescale 1ns/1ps

// Combinational best-bid / best-ask / spread / mid from flattened book state.
// best bid  = highest bid price with qty != 0
// best ask  = lowest  ask price with qty != 0
// This naive parallel scan is the "before" for the Tier 2 optimization
// (pipelined comparator tree is the "after").
module top_of_book
  import md_pkg::*;
#(
  parameter int NUM_LEVELS = 8
)(
  input  logic [NUM_LEVELS*16-1:0] bid_price_flat,
  input  logic [NUM_LEVELS*16-1:0] bid_qty_flat,
  input  logic [NUM_LEVELS*16-1:0] ask_price_flat,
  input  logic [NUM_LEVELS*16-1:0] ask_qty_flat,

  output logic [15:0] best_bid,
  output logic        best_bid_valid,
  output logic [15:0] best_ask,
  output logic        best_ask_valid,
  output logic signed [15:0] spread,
  output logic [16:0] mid_sum,
  output logic        tob_valid
);

  logic [15:0] bp [NUM_LEVELS];
  logic [15:0] bq [NUM_LEVELS];
  logic [15:0] ap [NUM_LEVELS];
  logic [15:0] aq [NUM_LEVELS];

  always_comb begin
    for (int i = 0; i < NUM_LEVELS; i++) begin
      bp[i] = bid_price_flat[i*16 +: 16];
      bq[i] = bid_qty_flat[i*16 +: 16];
      ap[i] = ask_price_flat[i*16 +: 16];
      aq[i] = ask_qty_flat[i*16 +: 16];
    end
  end

  always_comb begin
    best_bid       = 16'h0;
    best_bid_valid = 1'b0;
    for (int i = 0; i < NUM_LEVELS; i++)
      if (bq[i] != 16'h0) begin
        if (!best_bid_valid || bp[i] > best_bid) best_bid = bp[i];
        best_bid_valid = 1'b1;
      end

    best_ask       = 16'h0;
    best_ask_valid = 1'b0;
    for (int i = 0; i < NUM_LEVELS; i++)
      if (aq[i] != 16'h0) begin
        if (!best_ask_valid || ap[i] < best_ask) best_ask = ap[i];
        best_ask_valid = 1'b1;
      end
  end

  assign tob_valid = best_bid_valid && best_ask_valid;
  assign spread    = tob_valid ? ($signed(best_ask) - $signed(best_bid)) : 16'sh0;
  assign mid_sum   = tob_valid ? ({1'b0, best_bid} + {1'b0, best_ask}) : 17'h0;

endmodule
