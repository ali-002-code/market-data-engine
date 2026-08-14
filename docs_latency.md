# Latency (Tier 1, functional simulation)

Per-stage, message-relevant path:

- stream_framer: raises msg_valid on the 8th byte of a message. 1 cycle to register the completed word.
- msg_decoder: combinational, 0 cycles.
- book_engine: registers the book update, raises book_valid. 1 cycle.
- top_of_book: combinational off the registered book state, 0 cycles.

Book-relevant latency, last byte accepted to outputs valid: 1 cycle.

Latency vs throughput:
- Framing latency: 8 bytes must arrive before a message completes (byte-serial input).
- Pipeline throughput: one message can complete every cycle once bytes are flowing.
- These are distinct numbers and should be reported separately.

Note: cycle counts above are from functional simulation. Post-route Fmax
(target ~100 to 150 MHz on XC7A35T) is measured in the Vivado stage, not here.
