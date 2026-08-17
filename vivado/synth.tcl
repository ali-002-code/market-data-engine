# Reproducible synthesis + implementation for Fmax/resource measurement
# of market_data_top on the Artix-7 XC7A35T.
#   (in Vivado Tcl console)  cd <repo root>; source vivado/synth.tcl

set part xc7a35tcpg236-1
set top  market_data_top

create_project -in_memory -part $part

read_verilog -sv rtl/md_pkg.sv
read_verilog -sv rtl/msg_decoder.sv
read_verilog -sv rtl/stream_framer.sv
read_verilog -sv rtl/book_engine.sv
read_verilog -sv rtl/top_of_book.sv
read_verilog -sv rtl/market_data_top.sv

read_xdc vivado/timing.xdc

synth_design -top $top -part $part
report_utilization -file vivado/out/util_post_synth.rpt

opt_design
place_design
route_design

report_timing_summary -file vivado/out/timing_post_route.rpt
report_utilization    -file vivado/out/util_post_route.rpt

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "==================================================="
puts "WNS (setup) = $wns ns at 6.667 ns constraint (150 MHz)"
puts "Achievable Fmax = [expr {1000.0 / (6.667 - $wns)}] MHz"
puts "==================================================="
report_timing -delay_type max -max_paths 1 -nworst 1
