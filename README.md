# Low-Latency FPGA Market Data Engine

A fully pipelined SystemVerilog engine that ingests a stream of binary exchange
messages and maintains an L2 order book in hardware, exposing best bid, best
ask, spread, and mid. It is streaming (processes bytes as they arrive, not
store-then-process) and deterministic (fixed, stateable cycle latency from
message-in to book-out). Built as an HFT-oriented portfolio project targeting
FPGA roles, with verification and honest post-route measurement as the core
deliverables.

Target: Xilinx Artix-7 XC7A35T (xc7a35tcpg236-1), Vivado 2025.2.
Verification: Verilator 5.050 + cocotb 1.9.2.

## Results (all measured, nothing estimated)

| Metric                         | Value                                              |
|--------------------------------|----------------------------------------------------|
| Post-route Fmax (best version) | 87.5 MHz on XC7A35T (WNS -4.768 ns @ 150 MHz req)  |
| Resource usage                 | ~1081 LUT (5%), 614 FF (1.5%), 0 BRAM, 0 DSP       |
| Book latency                   | 1 cycle (v1) / 2 cycles (pipelined v3)             |
| Verification                   | 100k+ randomized messages x multiple seeds, 0 mismatches |
| Directed tests                 | 24 across all modules, all passing                 |

BRAM = 0 is deliberate: the book lives entirely in registers so every price
level can be compared in parallel in a single cycle. See the optimization notes
for why that choice matters and what it costs.

## Architecture

Byte stream in, top-of-book out, five modules in a line:

    bytes --> stream_framer --> msg_decoder --> book_engine --> top_of_book --> outputs
              (8 bytes into      (slice into     (L2 book in     (best bid/ask/
               one 64-bit msg)    typed fields)   registers)      spread/mid)

- stream_framer: valid/ready/last byte handshake, assembles 8 bytes (big-endian) into one message word.
- msg_decoder: combinational field slicing (type, side, price, qty).
- book_engine: L2 book in registers, unsorted parallel price match; ADD/CANCEL/MODIFY/TRADE with saturating add and clamped subtract.
- top_of_book: parallel scan for best bid/ask; signed spread (represents crossed books); un-halved mid to preserve the half-tick.
- market_data_top: wires the datapath; one out_valid pulse per completed message.

Message wire format: fixed 8 bytes, big-endian. Byte 0 type, byte 1 side,
bytes 2-3 price, bytes 4-5 quantity, bytes 6-7 reserved (sequence number for
future gap detection).

## Highlights

### Verification: differential testing against a reference model
A dict-based Python reference model (`ref/book_model.py`), written the obvious
way to be correct by inspection, serves as an oracle. A randomized harness
drives the same biased-random message stream through both the RTL and the
reference and compares best bid/ask/spread/mid after every message. 100k+
messages across multiple seeds, zero mismatches. The harness earned its keep:
it caught a crossed-book specification gap (spread wrapping to 0xFFFF vs -1) at
message 6, which was resolved by making spread a signed value. Full writeup:
[docs/verification.md](docs/verification.md).

### Optimization: pipelining the book engine (measured before/after)
Three measured versions of the book engine, all post-route on the real device:
v1 single-cycle combinational (86.3 MHz), v2 two-stage pipeline with
full-overlay forwarding (82.3 MHz, a regression), v3 two-stage pipeline with
narrow-bypass forwarding (87.5 MHz). The v2 regression was diagnosed from the
post-route timing report (the forwarding overlay moved onto the critical path)
and fixed in v3. All three are routing-dominated (~68-74% wire delay), which is
the real performance ceiling for a design this size on this device. Full
writeup with the timing analysis: [docs/optimization.md](docs/optimization.md).

### Latency vs throughput
Book-relevant latency is 1 cycle (v1) or 2 cycles (v3) from completed message
to valid output. End-to-end from first byte is dominated by the 8-cycle
byte-serial framing, not book processing. These are distinct numbers and are
reported separately: [docs/latency.md](docs/latency.md).

## Repository layout

    rtl/    SystemVerilog RTL (md_pkg, stream_framer, msg_decoder,
            book_engine, top_of_book, market_data_top)
    sim/    cocotb testbenches and Makefiles
    ref/    Python reference model and its self-checks
    vivado/ synthesis script (synth.tcl) and timing constraint (timing.xdc)
    docs/   latency, verification, and optimization writeups

## Running the tests

Simulation (from `sim/`, with a Python venv that has cocotb, and Verilator on PATH):

    make MOD=msg_decoder      # per-module directed tests (default target)
    make MOD=stream_framer
    make MOD=book_engine
    make MOD=top_of_book
    make -f Makefile.top      # top-level integration tests
    make -f Makefile.diff     # differential test (2000 msgs)
    NUM_MSGS=100000 SEED=1 make -f Makefile.diff   # full differential run

Reference model self-check:

    cd ref && python test_book_model.py

Synthesis (Vivado, from repo root):

    vivado -mode batch -source vivado/synth.tcl

Prints post-route WNS and computed Fmax, and writes reports to vivado/out/.

## Scope

Tier 1 (datapath) and Tier 2 (reference model, differential testing, latency
table, real synthesis with one optimization) are complete. Deferred by design:
sequence-gap detection, Ethernet/IP/UDP ingest, timestamps and multi-feed.
