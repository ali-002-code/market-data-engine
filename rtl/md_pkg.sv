// Shared parameters, message-type enum, and decoded-message struct.
// Everything imports this so widths never drift across modules.
package md_pkg;

  parameter int PRICE_W = 16;
  parameter int QTY_W   = 16;
  parameter int MSG_W   = 64;

  typedef enum logic [7:0] {
    MSG_ADD    = 8'd0,
    MSG_CANCEL = 8'd1,
    MSG_MODIFY = 8'd2,
    MSG_TRADE  = 8'd3
  } msg_type_e;

  typedef struct packed {
    msg_type_e          mtype;
    logic               side;   // 0 = bid, 1 = ask
    logic [PRICE_W-1:0] price;
    logic [QTY_W-1:0]   qty;
  } decoded_msg_t;

endpackage
