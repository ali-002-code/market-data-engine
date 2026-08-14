import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


async def reset(dut):
    dut.rst_n.value = 0
    dut.s_valid.value = 0
    dut.s_data.value = 0
    dut.s_last.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def send_byte(dut, value, last=0):
    dut.s_data.value = value
    dut.s_valid.value = 1
    dut.s_last.value = last
    await RisingEdge(dut.clk)
    dut.s_valid.value = 0
    dut.s_last.value = 0


@cocotb.test()
async def test_single_message(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    payload = [0x00, 0x00, 0x12, 0x34, 0x00, 0x64, 0x00, 0x00]
    seen = []

    async def watch():
        while True:
            await RisingEdge(dut.clk)
            if dut.msg_valid.value == 1:
                seen.append(int(dut.msg_out.value))

    cocotb.start_soon(watch())

    for i, b in enumerate(payload):
        await send_byte(dut, b, last=(i == 7))

    for _ in range(3):
        await RisingEdge(dut.clk)

    assert len(seen) == 1, f"expected 1 message, got {len(seen)}"
    assert seen[0] == 0x0000123400640000, f"got {seen[0]:016x}"


@cocotb.test()
async def test_two_back_to_back(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    stream = list(range(1, 17))  # 16 bytes = 2 messages
    seen = []

    async def watch():
        while True:
            await RisingEdge(dut.clk)
            if dut.msg_valid.value == 1:
                seen.append(int(dut.msg_out.value))

    cocotb.start_soon(watch())

    for b in stream:
        await send_byte(dut, b)

    for _ in range(3):
        await RisingEdge(dut.clk)

    assert len(seen) == 2, f"expected 2 messages, got {len(seen)}"
    assert seen[0] == 0x0102030405060708, f"got {seen[0]:016x}"
    assert seen[1] == 0x090A0B0C0D0E0F10, f"got {seen[1]:016x}"


@cocotb.test()
async def test_gap_in_valid(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    payload = [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x11, 0x22]
    seen = []

    async def watch():
        while True:
            await RisingEdge(dut.clk)
            if dut.msg_valid.value == 1:
                seen.append(int(dut.msg_out.value))

    cocotb.start_soon(watch())

    # Send 4 bytes, stall 3 cycles with valid low, then send the rest.
    for b in payload[:4]:
        await send_byte(dut, b)
    for _ in range(3):
        await RisingEdge(dut.clk)  # valid stays low, no bytes accepted
    for b in payload[4:]:
        await send_byte(dut, b)

    for _ in range(3):
        await RisingEdge(dut.clk)

    assert len(seen) == 1, f"expected 1 message despite the gap, got {len(seen)}"
    assert seen[0] == 0xAABBCCDDEEFF1122, f"got {seen[0]:016x}"
