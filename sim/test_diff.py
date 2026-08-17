"""Randomized differential test: RTL vs reference model, per-message compare.

Generates biased-random message streams so collisions, cancels of existing
levels, refills, and book-full all occur frequently. After every message the
RTL top-of-book is compared against the reference model. Target: 0 mismatches.

Run count is set by the NUM_MSGS env var (default 2000 for a quick run).
For the headline number: NUM_MSGS=100000 make -f Makefile.diff
"""
import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "ref"))
from book_model import BookModel, ADD, CANCEL, MODIFY, TRADE, BID, ASK

NUM_LEVELS = 8
NUM_MSGS = int(os.environ.get("NUM_MSGS", "2000"))
SEED = int(os.environ.get("SEED", "1"))

# Small price pool so collisions and book-full happen often.
PRICE_POOL = [100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111]
TYPE_WEIGHTS = [(ADD, 50), (CANCEL, 25), (MODIFY, 15), (TRADE, 10)]


def weighted_type(rng):
    r = rng.randint(1, sum(w for _, w in TYPE_WEIGHTS))
    upto = 0
    for t, w in TYPE_WEIGHTS:
        upto += w
        if r <= upto:
            return t
    return ADD


def gen_message(rng):
    return (
        weighted_type(rng),
        rng.choice([BID, ASK]),
        rng.choice(PRICE_POOL),
        rng.randint(0, 300),
    )


def msg_bytes(mtype, side, price, qty):
    word = (
        (mtype & 0xFF) << 56
        | (side & 0xFF) << 48
        | (price & 0xFFFF) << 32
        | (qty & 0xFFFF) << 16
    )
    return [(word >> (8 * (7 - i))) & 0xFF for i in range(8)]


async def reset(dut):
    dut.rst_n.value = 0
    dut.s_valid.value = 0
    dut.s_data.value = 0
    dut.s_last.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def drive_message(dut, msg):
    mtype, side, price, qty = msg
    for i, b in enumerate(msg_bytes(mtype, side, price, qty)):
        dut.s_data.value = b
        dut.s_valid.value = 1
        dut.s_last.value = 1 if i == 7 else 0
        await RisingEdge(dut.clk)
    dut.s_valid.value = 0
    dut.s_last.value = 0
    # book_engine registers the update one cycle after msg completes;
    # one extra edge lets the registered state settle to the outputs.
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


def rtl_tob(dut):
    bb = int(dut.best_bid.value) if dut.best_bid_valid.value == 1 else None
    ba = int(dut.best_ask.value) if dut.best_ask_valid.value == 1 else None
    both = dut.tob_valid.value == 1
    return {
        "best_bid": bb,
        "best_ask": ba,
        "spread": dut.spread.value.signed_integer if both else None,
        "mid_sum": int(dut.mid_sum.value) if both else None,
    }


@cocotb.test()
async def test_differential(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    rng = random.Random(SEED)
    model = BookModel(NUM_LEVELS)
    history = []

    for idx in range(NUM_MSGS):
        msg = gen_message(rng)
        history.append(msg)
        if len(history) > 8:
            history.pop(0)

        model.apply(*msg)
        await drive_message(dut, msg)

        exp = model.top_of_book()
        got = rtl_tob(dut)

        if exp != got:
            lines = [f"MISMATCH at message {idx}", f"  message: {msg}", "  recent history:"]
            for h in history:
                lines.append(f"    {h}")
            lines.append(f"  expected: {exp}")
            lines.append(f"  got:      {got}")
            raise AssertionError("\n".join(lines))

    dut._log.info(f"differential OK: {NUM_MSGS} messages, seed {SEED}, 0 mismatches")
