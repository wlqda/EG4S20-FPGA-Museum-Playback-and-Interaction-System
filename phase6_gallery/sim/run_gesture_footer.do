onerror {quit -code 1}
if {![file isdirectory footer_work]} {vlib footer_work}
vmap work footer_work
vlog -sv ../rtl/museum_phase5_render.v ../sim/tb_gesture_footer.sv
vsim -c work.tb_gesture_footer
onfinish stop
run -all
if {[examine -radix unsigned /tb_gesture_footer/passed] != 1} {quit -code 1}
quit -code 0
