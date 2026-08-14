import cocotb
from cocotb.triggers import Timer

NUM_LEVELS = 8


def pack(levels):
    prices = 0
    qtys = 0
    for i, (p, q) in enumerate(levels):
        prices |= (p & 0xFFFF) << (i * 16)
        qtys |= (q & 0xFFFF) << (i * 16)
    while len(levels) < NUM_LEVELS:
        levels.append((0, 0))
    return prices, qtys


async def apply(dut, bids, asks):
    bp, bq = pack(list(bids))
    ap, aq = pack(list(asks))
    dut.bid_price_flat.value = bp
    dut.bid_qty_flat.value = bq
    dut.ask_price_flat.value = ap
    dut.ask_qty_flat.value = aq
    await Timer(1, units="ns")


@cocotb.test()
async def test_basic_tob(dut):
    await apply(dut, [(100, 5), (101, 5), (99, 5)], [(105, 5), (104, 5), (106, 5)])
    assert dut.best_bid_valid.value == 1
    assert dut.best_ask_valid.value == 1
    assert dut.best_bid.value == 101
    assert dut.best_ask.value == 104
    assert dut.spread.value == 3
    assert dut.mid_sum.value == 205
    assert dut.tob_valid.value == 1


@cocotb.test()
async def test_empty_bid_side(dut):
    await apply(dut, [], [(105, 5)])
    assert dut.best_bid_valid.value == 0
    assert dut.best_ask_valid.value == 1
    assert dut.tob_valid.value == 0


@cocotb.test()
async def test_empty_book(dut):
    await apply(dut, [], [])
    assert dut.best_bid_valid.value == 0
    assert dut.best_ask_valid.value == 0
    assert dut.tob_valid.value == 0


@cocotb.test()
async def test_single_level_each(dut):
    await apply(dut, [(50, 9)], [(60, 7)])
    assert dut.best_bid.value == 50
    assert dut.best_ask.value == 60
    assert dut.spread.value == 10
    assert dut.mid_sum.value == 110


@cocotb.test()
async def test_ignores_zero_qty(dut):
    await apply(dut, [(100, 5), (200, 0)], [(300, 5)])
    assert dut.best_bid.value == 100
