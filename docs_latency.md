# Latency and Throughput

All cycle counts below are from functional simulation (Verilator). They are
exact and deterministic: the same message always takes the same number of
cycles. Post-route Fmax (which turns cycles into nanoseconds) is measured
separately in Vivado on the XC7A35T and recorded in the synthesis notes.

## Per-stage latency

| Stage          | Type            | Cycles | Notes                                             |
|----------------|-----------------|--------|---------------------------------------------------|
| stream_framer  | sequential      | 1      | registers the completed 64-bit word on byte 8     |
| msg_decoder    | combinational   | 0      | pure field slicing, no register                   |
| book_engine    | sequential      | 1      | registers the updated book + book_valid           |
| top_of_book    | combinational   | 0      | parallel scan off the registered book state       |

## Two distinct numbers

Message-complete to output (book-relevant latency): **1 cycle**
  From the cycle the 8th byte is accepted (msg_valid) to the cycle the book
  outputs are valid (out_valid). The decoder and top_of_book add no cycles
  because they are combinational; only the book_engine register sits between.

First byte to output (end-to-end, includes framing): **9 cycles**
  8 cycles to serially accept the 8 bytes of a message (byte-serial input),
  then 1 cycle for the book update. This is dominated by the input being one
  byte wide, not by book processing.

## Latency vs throughput

- Latency (message-complete to out_valid): 1 cycle, fixed.
- Framing latency: 8 cycles per message, because the wire format is 8 bytes
  and the input is one byte per cycle. This is an interface choice, not a
  book-engine cost. A 64-bit-wide input would collapse it to 1 cycle.
- Throughput: one message can complete every 8 cycles at the byte-serial
  input (bounded by framing), or one per cycle if fed 64-bit words. The book
  engine itself accepts a message every cycle; the byte-serial front end is
  the throughput bottleneck, by design, for a realistic octet-stream input.

## What changes after synthesis

Cycle counts do not change; they are set by the RTL structure. What Vivado
adds is the clock period: Fmax (post-route) converts these cycle counts into
real time. Target on XC7A35T is roughly 100 to 150 MHz; the measured value
will be recorded and used to state latency in nanoseconds.
