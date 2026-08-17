# Timing constraint for Fmax measurement of market_data_top on XC7A35T.
#
# We constrain the clock period, run implementation, then read WNS from the
# timing report. True achievable Fmax = 1 / (period - WNS).
#
# Starting constraint: 150 MHz = 6.667 ns.

create_clock -period 6.667 -name sys_clk [get_ports clk]
