onerror {quit -code 1}
if {![file isdirectory full_switches_work]} {vlib full_switches_work}
vmap work full_switches_work
vlog -sv ../rtl/museum_floating_clock.v ../camera/rtl/museum_camera_key_modes.v ../camera/rtl/camera_nav_adapter.v ../camera/rtl/museum_phase6_unified_top.v ../camera/sim/tb_full_switches.sv
vsim -c work.tb_full_switches
onfinish stop
run -all
if {[examine -radix unsigned /tb_full_switches/passed] != 1} {quit -code 1}
quit -code 0
