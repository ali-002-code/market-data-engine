`timescale 1ns/1ps

// Pipelined L2 order book core (2-stage) with NARROW-BYPASS forwarding.
// Unsorted levels, parallel price match. Accepts one message per cycle.
//
// v3 optimization vs the full-overlay forwarding:
//   The match / free-slot search runs on the COMMITTED book directly (no
//   overlay mux in front of the search). Forwarding is handled as a small
//   correction AFTER the search, so the long comparison chain no longer sits
//   downstream of the pending-write mux. This shortens the stage-1 path.
//
// Stage 1 (comb): search committed book, then apply a narrow bypass to
//   correct for the not-yet-committed stage-2 write. Register the decision.
// Stage 2 (registered): commit the decision to the book array.
//
// Latency: msg_valid -> book_valid = 2 cycles. out_valid follows.
//
// Bypass cases (message N+1 in stage 1 vs message N pending in stage 2):
//   Both on same side, and s2 is writing (s2_we):
//   (a) modify-in-flight: s2 writes an EXISTING price == my price. The
//       committed search may still match that slot (price unchanged) but its
//       qty is stale, or s2 may be freeing it. We take s2_qty as the current
//       value for that level.
//   (b) allocate-in-flight: s2 writes a NEW price == my price at s2_idx that
//       the committed book does not yet show. The committed search misses it
//       and could pick a free slot (double-allocate). We override to target
//       s2_idx and treat cur = s2_qty.
//   Net rule: if s2_we and s2_side==msg_side and s2_price==msg_price and
//   s2_qty!=0, then FORCE match at s2_idx with cur=s2_qty. This single rule
//   covers both (a) and (b). If s2 is freeing that price (s2_qty==0), the
//   committed search result stands (the level is going away).
//
// Semantics unchanged: level present iff qty!=0; ADD saturating add /
//   allocate; CANCEL,TRADE subtract clamped at 0; MODIFY replace (0 frees).
module book_engine
  import md_pkg::*;
#(
  parameter int NUM_LEVELS = 8
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic        msg_valid,
  input  msg_type_e   msg_type,
  input  logic        msg_side,
  input  logic [15:0] msg_price,
  input  logic [15:0] msg_qty,

  output logic [NUM_LEVELS*16-1:0] bid_price_flat,
  output logic [NUM_LEVELS*16-1:0] bid_qty_flat,
  output logic [NUM_LEVELS*16-1:0] ask_price_flat,
  output logic [NUM_LEVELS*16-1:0] ask_qty_flat,
  output logic        book_valid
);

  localparam int IDXW = (NUM_LEVELS > 1) ? $clog2(NUM_LEVELS) : 1;

  logic [15:0] price [2][NUM_LEVELS];
  logic [15:0] qty   [2][NUM_LEVELS];

  logic            s2_we;
  logic            s2_side;
  logic [IDXW-1:0] s2_idx;
  logic [15:0]     s2_price;
  logic [15:0]     s2_qty;
  logic            s2_valid;

  // ---- Stage 1 ----
  logic            n_we;
  logic            n_side;
  logic [IDXW-1:0] n_idx;
  logic [15:0]     n_price;
  logic [15:0]     n_qty;

  always_comb begin
    logic            matched, hasfree;
    logic [IDXW-1:0] midx, fidx;
    logic            bypass_hit;   // s2 pending write collides with my price
    logic [15:0]     cur;
    logic [IDXW-1:0] tgt;          // resolved target index
    logic            have_tgt;     // do we have a level to update
    logic [16:0]     add_sum;
    logic [15:0]     res;

    n_we    = 1'b0;
    n_side  = msg_side;
    n_idx   = '0;
    n_price = msg_price;
    n_qty   = 16'h0;

    // Search the COMMITTED book (no overlay in front).
    matched = 1'b0; hasfree = 1'b0; midx = '0; fidx = '0;
    for (int i = NUM_LEVELS-1; i >= 0; i--)
      if (qty[msg_side][i] != 16'h0 && price[msg_side][i] == msg_price) begin
        matched = 1'b1; midx = i[IDXW-1:0];
      end
    // Free-slot search on the committed book. Exclude the slot stage 2 is
    // about to fill on this side (s2 allocating there), so a new ADD does not
    // double-target it and clobber the pending write next cycle.
    for (int i = NUM_LEVELS-1; i >= 0; i--)
      if (qty[msg_side][i] == 16'h0
          && !(s2_we && (s2_side == msg_side) && (s2_qty != 16'h0)
               && (s2_idx == i[IDXW-1:0]))) begin
        hasfree = 1'b1; fidx = i[IDXW-1:0];
      end

    // Narrow bypass: does the pending stage-2 write cover my price?
    bypass_hit = s2_we && (s2_side == msg_side)
                 && (s2_price == msg_price) && (s2_qty != 16'h0);

    // Resolve target and current quantity.
    if (bypass_hit) begin
      have_tgt = 1'b1;
      tgt      = s2_idx;
      cur      = s2_qty;          // forwarded live value
    end else if (matched) begin
      have_tgt = 1'b1;
      tgt      = midx;
      cur      = qty[msg_side][midx];
    end else begin
      have_tgt = 1'b0;
      tgt      = fidx;
      cur      = 16'h0;
    end

    add_sum = {1'b0, cur} + {1'b0, msg_qty};
    unique case (msg_type)
      MSG_ADD:    res = add_sum[16] ? 16'hFFFF : add_sum[15:0];
      MSG_CANCEL: res = (cur > msg_qty) ? (cur - msg_qty) : 16'h0;
      MSG_TRADE:  res = (cur > msg_qty) ? (cur - msg_qty) : 16'h0;
      MSG_MODIFY: res = msg_qty;
      default:    res = cur;
    endcase

    if (msg_valid) begin
      if (have_tgt) begin
        n_we    = 1'b1;
        n_idx   = tgt;
        n_price = msg_price;
        n_qty   = res;                    // res==0 frees the level in stage 2
      end else if (msg_type == MSG_ADD && msg_qty != 16'h0 && hasfree) begin
        n_we    = 1'b1;
        n_idx   = fidx;
        n_price = msg_price;
        n_qty   = msg_qty;
      end
      // else: no-op
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int s = 0; s < 2; s++)
        for (int i = 0; i < NUM_LEVELS; i++) begin
          price[s][i] <= 16'h0;
          qty[s][i]   <= 16'h0;
        end
      s2_we    <= 1'b0;
      s2_side  <= 1'b0;
      s2_idx   <= '0;
      s2_price <= 16'h0;
      s2_qty   <= 16'h0;
      s2_valid <= 1'b0;
      book_valid <= 1'b0;
    end else begin
      if (s2_we) begin
        price[s2_side][s2_idx] <= s2_price;
        qty[s2_side][s2_idx]   <= s2_qty;
      end
      s2_we    <= n_we;
      s2_side  <= n_side;
      s2_idx   <= n_idx;
      s2_price <= n_price;
      s2_qty   <= n_qty;
      s2_valid   <= msg_valid;
      book_valid <= s2_valid;
    end
  end

  always_comb begin
    for (int i = 0; i < NUM_LEVELS; i++) begin
      bid_price_flat[i*16 +: 16] = price[0][i];
      bid_qty_flat[i*16 +: 16]   = qty[0][i];
      ask_price_flat[i*16 +: 16] = price[1][i];
      ask_qty_flat[i*16 +: 16]   = qty[1][i];
    end
  end

endmodule
