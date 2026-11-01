onerror {quit -code 1}
if {![file isdirectory unified_work]} {vlib unified_work}
vmap work unified_work
vlog -sv ../deps/gui/museum_keys.v ../rtl/museum_phase5_ui.v ../camera/rtl/camera_nav_adapter.v ../camera/rtl/museum_camera_key_modes.v ../camera/sim/tb_museum_unified.sv
vsim -c work.tb_museum_unified
onfinish stop
run -all
if {[examine -radix unsigned /tb_museum_unified/passed] != 1} {quit -code 1}
quit -code 0
