# Low-Latency FPGA Market Data Engine

A fully pipelined SystemVerilog engine that ingests binary exchange messages
and maintains an L2 order book in hardware, exposing best bid, best ask,
spread, and mid. Streaming and deterministic: fixed cycle latency from
message-in to book-out.

Target: Xilinx Artix-7 XC7A35T (Vivado). Verification: Verilator + cocotb.

## Layout
- rtl/  SystemVerilog RTL
- sim/  cocotb testbenches and Makefile
- ref/  Python reference model (Tier 2)

## Run the tests
    cd sim && make
