onerror {quit -code 1}
if {![file isdirectory gallery_work]} {vlib gallery_work}
vmap work gallery_work
vlog -sv ../rtl/museum_phase5_ui.v ../sim/tb_gallery_ui.v
vsim -c work.tb_gallery_ui
onfinish stop
run -all
if {[examine -radix unsigned /tb_gallery_ui/passed] != 1} {quit -code 1}
quit -code 0
