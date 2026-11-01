onerror {quit -code 1}
if {![file isdirectory switch_work]} {vlib switch_work}
vmap work switch_work
vlog ../rtl/museum_floating_clock.v ../sim/tb_slide_switch.v
vsim -c work.tb_slide_switch
onfinish stop
run -all
if {[examine -radix unsigned /tb_slide_switch/passed] != 1} {quit -code 1}
quit -code 0
