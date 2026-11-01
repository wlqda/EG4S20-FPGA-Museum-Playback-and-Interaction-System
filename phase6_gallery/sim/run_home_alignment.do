onerror {quit -code 1}
if {![file isdirectory home_alignment_work]} {vlib home_alignment_work}
vmap work home_alignment_work
vlog -sv ../rtl/museum_phase5_render.v ../sim/tb_home_alignment.v
vsim -c work.tb_home_alignment
onfinish stop
run -all
if {[examine -radix unsigned /tb_home_alignment/passed] != 1} {quit -code 1}
quit -code 0
