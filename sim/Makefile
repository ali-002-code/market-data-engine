SIM ?= verilator
TOPLEVEL_LANG ?= verilog

# Which module to test: make MOD=stream_framer   (defaults to msg_decoder)
MOD ?= msg_decoder

VERILOG_SOURCES += $(PWD)/../rtl/md_pkg.sv
VERILOG_SOURCES += $(PWD)/../rtl/$(MOD).sv

TOPLEVEL = $(MOD)
MODULE = test_$(MOD)

include $(shell cocotb-config --makefiles)/Makefile.sim
