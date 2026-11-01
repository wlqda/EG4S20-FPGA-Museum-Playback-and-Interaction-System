onerror {quit -code 1}
if {![file isdirectory panel_work]} {vlib panel_work}
vmap work panel_work
vlog -sv ../rtl/museum_phase5_render.v ../camera/rtl/camera_pose_overlay.v ../camera/sim/tb_camera_integrated_panel.sv
vsim -c work.tb_camera_integrated_panel
onfinish stop
run -all
if {[examine -radix unsigned /tb_camera_integrated_panel/passed] != 1} {quit -code 1}
quit -code 0
