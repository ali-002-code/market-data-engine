`timescale 1ns/1ps

// Stateful L2 order book core. Unsorted levels, parallel price match.
// One decoded message per cycle; book state is registered, so there is
// exactly 1 cycle of latency from an accepted message to the updated book.
//
// Semantics (mirror these exactly in the reference model):
//   A level is "present" iff its qty != 0. Freeing a level = setting qty 0.
//   ADD    : matched -> saturating add (clamp 0xFFFF); unmatched -> allocate
//            a free slot if qty>0 and space exists, else drop (book full).
//   CANCEL : matched -> subtract, clamp at 0 (frees level at 0); unmatched -> no-op.
//   TRADE  : same effect as CANCEL at L2 scope; unmatched -> no-op.
//   MODIFY : matched -> replace qty (qty 0 frees the level); unmatched -> no-op.
module book_engine
  import md_pkg::*;
#(
  parameter int NUM_LEVELS = 8
)(
  input  logic        clk,
  input  logic        rst_n,

  // decoded message input
  input  logic        msg_valid,
  input  msg_type_e   msg_type,
  input  logic        msg_side,   // 0 = bid, 1 = ask
  input  logic [15:0] msg_price,
  input  logic [15:0] msg_qty,

  // flattened book state outputs (level i occupies bits [i*16 +: 16])
  output logic [NUM_LEVELS*16-1:0] bid_price_flat,
  output logic [NUM_LEVELS*16-1:0] bid_qty_flat,
  output logic [NUM_LEVELS*16-1:0] ask_price_flat,
  output logic [NUM_LEVELS*16-1:0] ask_qty_flat,
  output logic        book_valid   // high 1 cycle after each accepted message
);

  localparam int IDXW = (NUM_LEVELS > 1) ? $clog2(NUM_LEVELS) : 1;

  // State: index 0 = bid side, index 1 = ask side.
  logic [15:0] price [2][NUM_LEVELS];
  logic [15:0] qty   [2][NUM_LEVELS];

  // Next-state
  logic [15:0] n_price [2][NUM_LEVELS];
  logic [15:0] n_qty   [2][NUM_LEVELS];

  always_comb begin
    logic            matched, hasfree;
    logic [IDXW-1:0] midx, fidx;
    logic [16:0]     add_sum;
    logic [15:0]     res;

    // default: hold all levels
    for (int s = 0; s < 2; s++)
      for (int i = 0; i < NUM_LEVELS; i++) begin
        n_price[s][i] = price[s][i];
        n_qty[s][i]   = qty[s][i];
      end

    matched = 1'b0; hasfree = 1'b0;
    midx = '0; fidx = '0; res = 16'h0;

    if (msg_valid) begin
      // Parallel match on the incoming side (lowest index wins; prices are unique).
      for (int i = NUM_LEVELS-1; i >= 0; i--)
        if (qty[msg_side][i] != 16'h0 && price[msg_side][i] == msg_price) begin
          matched = 1'b1;
          midx    = i[IDXW-1:0];
        end

      // First free slot on the incoming side.
      for (int i = NUM_LEVELS-1; i >= 0; i--)
        if (qty[msg_side][i] == 16'h0) begin
          hasfree = 1'b1;
          fidx    = i[IDXW-1:0];
        end

      add_sum = {1'b0, qty[msg_side][midx]} + {1'b0, msg_qty};

      unique case (msg_type)
        MSG_ADD:    res = add_sum[16] ? 16'hFFFF : add_sum[15:0];
        MSG_CANCEL: res = (qty[msg_side][midx] > msg_qty) ? (qty[msg_side][midx] - msg_qty) : 16'h0;
        MSG_TRADE:  res = (qty[msg_side][midx] > msg_qty) ? (qty[msg_side][midx] - msg_qty) : 16'h0;
        MSG_MODIFY: res = msg_qty;
        default:    res = qty[msg_side][midx];
      endcase

      if (matched) begin
        n_qty[msg_side][midx] = res;  // price unchanged; res==0 leaves an empty slot
      end else if (msg_type == MSG_ADD && msg_qty != 16'h0 && hasfree) begin
        n_price[msg_side][fidx] = msg_price;
        n_qty[msg_side][fidx]   = msg_qty;
      end
      // CANCEL / TRADE / MODIFY with no match: no-op
    end
  end

  // Register state
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int s = 0; s < 2; s++)
        for (int i = 0; i < NUM_LEVELS; i++) begin
          price[s][i] <= 16'h0;
          qty[s][i]   <= 16'h0;
        end
      book_valid <= 1'b0;
    end else begin
      for (int s = 0; s < 2; s++)
        for (int i = 0; i < NUM_LEVELS; i++) begin
          price[s][i] <= n_price[s][i];
          qty[s][i]   <= n_qty[s][i];
        end
      book_valid <= msg_valid;
    end
  end

  // Flatten to outputs
  always_comb begin
    for (int i = 0; i < NUM_LEVELS; i++) begin
      bid_price_flat[i*16 +: 16] = price[0][i];
      bid_qty_flat[i*16 +: 16]   = qty[0][i];
      ask_price_flat[i*16 +: 16] = price[1][i];
      ask_qty_flat[i*16 +: 16]   = qty[1][i];
    end
  end

endmodule
