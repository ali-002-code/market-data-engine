`timescale 1ns/1ps

// Pipelined L2 order book core (2-stage) with forwarding.
// Unsorted levels, parallel price match. Accepts one message per cycle.
//
// Stage 1 (comb from msg + forwarding): resolve target level, compute the
//   new quantity, and whether/where to write. Registered into s2_* regs.
// Stage 2 (registered write): apply the stage-1 decision to the book array.
//
// Latency: msg_valid -> book_valid is now 2 cycles (was 1). out_valid follows.
//
// Forwarding: message N+1 (stage 1) may target the same level message N
// (stage 2) is about to write but has not yet committed. Two cases:
//   - modify-in-flight: N updates an existing level; N+1 must read N's new
//     qty as its starting point (read-modify-write correctness).
//   - allocate-in-flight: N allocates a NEW price at a free slot; N+1 to the
//     same price must see that allocation (match it, not double-allocate).
// We forward by reconstructing an "effective" view of the book that overlays
// the pending stage-2 write onto the registered array, then do match / free
// search / arithmetic against that effective view.
//
// Semantics unchanged from the single-cycle version:
//   level present iff qty != 0; ADD saturating add / allocate; CANCEL,TRADE
//   subtract clamped at 0; MODIFY replace (0 frees). Unmatched CANCEL/TRADE/
//   MODIFY are no-ops. New ADD with no free slot is dropped.
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

  // Committed book state (written by stage 2). index 0=bid, 1=ask.
  logic [15:0] price [2][NUM_LEVELS];
  logic [15:0] qty   [2][NUM_LEVELS];

  // Stage-2 pending write registers (the decision made in stage 1).
  logic            s2_we;      // write enable
  logic            s2_side;
  logic [IDXW-1:0] s2_idx;     // level to write
  logic [15:0]     s2_price;   // price to write (for allocations)
  logic [15:0]     s2_qty;     // qty to write (0 frees the level)
  logic            s2_valid;   // a message was in stage 1 last cycle

  // ---- Effective (forwarded) view of the book for stage 1 ----
  // Overlay the pending stage-2 write onto the committed array so stage 1
  // sees the not-yet-committed result of the previous message.
  logic [15:0] eff_price [2][NUM_LEVELS];
  logic [15:0] eff_qty   [2][NUM_LEVELS];

  always_comb begin
    for (int s = 0; s < 2; s++)
      for (int i = 0; i < NUM_LEVELS; i++) begin
        eff_price[s][i] = price[s][i];
        eff_qty[s][i]   = qty[s][i];
      end
    if (s2_we) begin
      eff_price[s2_side][s2_idx] = s2_price;
      eff_qty[s2_side][s2_idx]   = s2_qty;
    end
  end

  // ---- Stage 1: resolve target, compute new qty, decide the write ----
  logic            n_we;
  logic            n_side;
  logic [IDXW-1:0] n_idx;
  logic [15:0]     n_price;
  logic [15:0]     n_qty;

  always_comb begin
    logic            matched, hasfree;
    logic [IDXW-1:0] midx, fidx;
    logic [16:0]     add_sum;
    logic [15:0]     cur, res;

    n_we    = 1'b0;
    n_side  = msg_side;
    n_idx   = '0;
    n_price = msg_price;
    n_qty   = 16'h0;

    matched = 1'b0; hasfree = 1'b0; midx = '0; fidx = '0;

    // Match and free-slot search against the EFFECTIVE (forwarded) view.
    for (int i = NUM_LEVELS-1; i >= 0; i--)
      if (eff_qty[msg_side][i] != 16'h0 && eff_price[msg_side][i] == msg_price) begin
        matched = 1'b1; midx = i[IDXW-1:0];
      end
    for (int i = NUM_LEVELS-1; i >= 0; i--)
      if (eff_qty[msg_side][i] == 16'h0) begin
        hasfree = 1'b1; fidx = i[IDXW-1:0];
      end

    cur     = matched ? eff_qty[msg_side][midx] : 16'h0;
    add_sum = {1'b0, cur} + {1'b0, msg_qty};

    unique case (msg_type)
      MSG_ADD:    res = add_sum[16] ? 16'hFFFF : add_sum[15:0];
      MSG_CANCEL: res = (cur > msg_qty) ? (cur - msg_qty) : 16'h0;
      MSG_TRADE:  res = (cur > msg_qty) ? (cur - msg_qty) : 16'h0;
      MSG_MODIFY: res = msg_qty;
      default:    res = cur;
    endcase

    if (msg_valid) begin
      if (matched) begin
        n_we    = 1'b1;
        n_idx   = midx;
        n_price = msg_price;
        n_qty   = res;               // res==0 frees the level in stage 2
      end else if (msg_type == MSG_ADD && msg_qty != 16'h0 && hasfree) begin
        n_we    = 1'b1;
        n_idx   = fidx;
        n_price = msg_price;
        n_qty   = msg_qty;
      end
      // else: no-op (unmatched cancel/trade/modify, or book full)
    end
  end

  // ---- Registers: stage-2 pending write, commit, and book_valid ----
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
      // Stage 2: commit the write decided last cycle.
      if (s2_we) begin
        price[s2_side][s2_idx] <= s2_price;
        qty[s2_side][s2_idx]   <= s2_qty;
      end

      // Latch stage-1 decision into stage-2 regs.
      s2_we    <= n_we;
      s2_side  <= n_side;
      s2_idx   <= n_idx;
      s2_price <= n_price;
      s2_qty   <= n_qty;

      // book_valid marks the cycle the book reflects a completed message:
      // one cycle after the message was in stage 1.
      s2_valid   <= msg_valid;
      book_valid <= s2_valid;
    end
  end

  // Flatten committed state.
  always_comb begin
    for (int i = 0; i < NUM_LEVELS; i++) begin
      bid_price_flat[i*16 +: 16] = price[0][i];
      bid_qty_flat[i*16 +: 16]   = qty[0][i];
      ask_price_flat[i*16 +: 16] = price[1][i];
      ask_qty_flat[i*16 +: 16]   = qty[1][i];
    end
  end

endmodule
