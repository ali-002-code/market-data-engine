import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

ADD, CANCEL, MODIFY, TRADE = 0, 1, 2, 3
BID, ASK = 0, 1


def msg_bytes(mtype, side, price, qty, reserved=0):
    word = (
        (mtype & 0xFF) << 56
        | (side & 0xFF) << 48
        | (price & 0xFFFF) << 32
        | (qty & 0xFFFF) << 16
        | (reserved & 0xFFFF)
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


async def send_message(dut, mtype, side, price, qty):
    # Returns out_valid pulse count over this message + its settle window.
    # Driver and checker share one coroutine, so there is no race.
    pulses = 0
    for i, b in enumerate(msg_bytes(mtype, side, price, qty)):
        dut.s_data.value = b
        dut.s_valid.value = 1
        dut.s_last.value = 1 if i == 7 else 0
        await RisingEdge(dut.clk)
        if dut.out_valid.value == 1:
            pulses += 1
    dut.s_valid.value = 0
    dut.s_last.value = 0
    for _ in range(2):
        await RisingEdge(dut.clk)
        if dut.out_valid.value == 1:
            pulses += 1
    return pulses


@cocotb.test()
async def test_end_to_end_book(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    await send_message(dut, ADD, BID, 100, 10)
    await send_message(dut, ADD, BID, 101, 5)
    await send_message(dut, ADD, ASK, 105, 8)
    await send_message(dut, ADD, ASK, 104, 3)

    assert dut.best_bid_valid.value == 1
    assert dut.best_ask_valid.value == 1
    assert dut.best_bid.value == 101, f"best_bid={int(dut.best_bid.value)}"
    assert dut.best_ask.value == 104, f"best_ask={int(dut.best_ask.value)}"
    assert dut.spread.value == 3
    assert dut.mid_sum.value == 205
    assert dut.tob_valid.value == 1


@cocotb.test()
async def test_cancel_moves_best(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    await send_message(dut, ADD, BID, 100, 10)
    await send_message(dut, ADD, BID, 101, 5)
    assert dut.best_bid.value == 101
    await send_message(dut, CANCEL, BID, 101, 5)
    assert dut.best_bid.value == 100, f"best_bid={int(dut.best_bid.value)}"


@cocotb.test()
async def test_out_valid_pulses(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    p1 = await send_message(dut, ADD, BID, 100, 10)
    p2 = await send_message(dut, ADD, ASK, 105, 8)
    assert p1 == 1, f"message 1: expected exactly 1 pulse, got {p1}"
    assert p2 == 1, f"message 2: expected exactly 1 pulse, got {p2}"
