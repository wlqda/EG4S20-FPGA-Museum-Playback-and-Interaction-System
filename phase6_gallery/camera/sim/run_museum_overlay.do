onerror {quit -code 1}
if {![file isdirectory museum_overlay_work]} {vlib museum_overlay_work}
vmap work museum_overlay_work
vlog -sv ../camera/rtl/museum_camera_overlay.v ../camera/sim/tb_museum_camera_overlay.sv
vsim -c work.tb_museum_camera_overlay
onfinish stop
run -all
if {[examine -radix unsigned /tb_museum_camera_overlay/passed] != 1} {quit -code 1}
quit -code 0
