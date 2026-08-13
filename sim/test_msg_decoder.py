import cocotb
from cocotb.triggers import Timer


def make_msg(mtype, side, price, qty, reserved=0):
    return (
        (mtype & 0xFF) << 56
        | (side & 0xFF) << 48
        | (price & 0xFFFF) << 32
        | (qty & 0xFFFF) << 16
        | (reserved & 0xFFFF)
    )


@cocotb.test()
async def test_add_decode(dut):
    dut.msg_in.value = make_msg(0, 0, 0x1234, 0x0064)
    await Timer(1, units="ns")
    assert dut.msg_type.value == 0
    assert dut.msg_side.value == 0
    assert dut.msg_price.value == 0x1234
    assert dut.msg_qty.value == 0x0064


@cocotb.test()
async def test_all_types(dut):
    for mtype in range(4):
        dut.msg_in.value = make_msg(mtype, 1, 0xABCD, 0x0010)
        await Timer(1, units="ns")
        assert dut.msg_type.value == mtype
        assert dut.msg_side.value == 1
        assert dut.msg_price.value == 0xABCD
        assert dut.msg_qty.value == 0x0010
