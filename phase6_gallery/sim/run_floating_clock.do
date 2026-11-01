onerror {quit -code 1}
if {![file isdirectory clock_work]} {vlib clock_work}
vmap work clock_work
vlog ../rtl/museum_floating_clock.v ../sim/tb_floating_clock.v
vsim -c work.tb_floating_clock
onfinish stop
run -all
if {[examine -radix unsigned /tb_floating_clock/passed] != 1} {quit -code 1}
quit -code 0
