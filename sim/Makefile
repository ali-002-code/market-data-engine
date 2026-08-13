SIM ?= verilator
TOPLEVEL_LANG ?= verilog

VERILOG_SOURCES += $(PWD)/../rtl/md_pkg.sv
VERILOG_SOURCES += $(PWD)/../rtl/msg_decoder.sv

TOPLEVEL = msg_decoder
MODULE = test_msg_decoder

include $(shell cocotb-config --makefiles)/Makefile.sim
