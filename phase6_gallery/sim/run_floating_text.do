onerror {quit -code 1}
vlib text_work
vmap work text_work
vlog -sv ../rtl/museum_floating_clock.v ../sim/reference/floating_clock_before_text.v ../sim/tb_floating_text.sv
vsim -c work.tb_text
onfinish stop
run -all
if {[examine -radix unsigned /tb_text/passed] != 1} {quit -code 1}
quit -code 0
