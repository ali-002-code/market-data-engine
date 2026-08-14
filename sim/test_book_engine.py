import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

NUM_LEVELS = 8

ADD, CANCEL, MODIFY, TRADE = 0, 1, 2, 3
BID, ASK = 0, 1


async def reset(dut):
    dut.rst_n.value = 0
    dut.msg_valid.value = 0
    dut.msg_type.value = 0
    dut.msg_side.value = 0
    dut.msg_price.value = 0
    dut.msg_qty.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def send(dut, mtype, side, price, qty):
    dut.msg_type.value = mtype
    dut.msg_side.value = side
    dut.msg_price.value = price
    dut.msg_qty.value = qty
    dut.msg_valid.value = 1
    await RisingEdge(dut.clk)
    dut.msg_valid.value = 0
    await RisingEdge(dut.clk)


def _flat(dut, side, kind):
    if side == BID:
        return int(dut.bid_price_flat.value) if kind == "p" else int(dut.bid_qty_flat.value)
    return int(dut.ask_price_flat.value) if kind == "p" else int(dut.ask_qty_flat.value)


def find_qty(dut, side, price):
    prices = _flat(dut, side, "p")
    qtys = _flat(dut, side, "q")
    for i in range(NUM_LEVELS):
        q = (qtys >> (i * 16)) & 0xFFFF
        p = (prices >> (i * 16)) & 0xFFFF
        if q != 0 and p == price:
            return q
    return 0


def count_levels(dut, side):
    qtys = _flat(dut, side, "q")
    return sum(1 for i in range(NUM_LEVELS) if ((qtys >> (i * 16)) & 0xFFFF) != 0)


@cocotb.test()
async def test_add_two_levels(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)
    await send(dut, ADD, BID, 100, 10)
    await send(dut, ADD, BID, 101, 20)
    assert find_qty(dut, BID, 100) == 10
    assert find_qty(dut, BID, 101) == 20
    assert count_levels(dut, BID) == 2


@cocotb.test()
async def test_same_price_accumulates(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)
    await send(dut, ADD, BID, 100, 10)
    await send(dut, ADD, BID, 100, 5)
    assert find_qty(dut, BID, 100) == 15
    assert count_levels(dut, BID) == 1


@cocotb.test()
async def test_cancel_partial_then_zero(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)
    await send(dut, ADD, BID, 100, 10)
    await send(dut, CANCEL, BID, 100, 4)
    assert find_qty(dut, BID, 100) == 6
    await send(dut, CANCEL, BID, 100, 6)
    assert count_levels(dut, BID) == 0


@cocotb.test()
async def test_cancel_nonexistent_noop(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)
    await send(dut, CANCEL, BID, 500, 5)
    assert count_levels(dut, BID) == 0


@cocotb.test()
async def test_modify_replaces_and_frees(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)
    await send(dut, ADD, ASK, 200, 10)
    await send(dut, MODIFY, ASK, 200, 3)
    assert find_qty(dut, ASK, 200) == 3
    await send(dut, MODIFY, ASK, 200, 0)
    assert count_levels(dut, ASK) == 0


@cocotb.test()
async def test_trade_reduces(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)
    await send(dut, ADD, ASK, 200, 10)
    await send(dut, TRADE, ASK, 200, 4)
    assert find_qty(dut, ASK, 200) == 6


@cocotb.test()
async def test_saturating_add(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)
    await send(dut, ADD, BID, 100, 0xFFF0)
    await send(dut, ADD, BID, 100, 0x0020)
    assert find_qty(dut, BID, 100) == 0xFFFF


@cocotb.test()
async def test_cancel_clamps_no_underflow(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)
    await send(dut, ADD, BID, 100, 5)
    await send(dut, CANCEL, BID, 100, 100)
    assert count_levels(dut, BID) == 0


@cocotb.test()
async def test_book_full_drops(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)
    for k in range(NUM_LEVELS):
        await send(dut, ADD, BID, 300 + k, 5)
    assert count_levels(dut, BID) == NUM_LEVELS
    await send(dut, ADD, BID, 999, 5)
    assert count_levels(dut, BID) == NUM_LEVELS
    assert find_qty(dut, BID, 999) == 0
