onerror {quit -code 1}
if {![file isdirectory full_camera_overlay_work]} {vlib full_camera_overlay_work}
vmap work full_camera_overlay_work
vlog -sv ../rtl/museum_phase5_render.v ../camera/rtl/camera_pose_overlay.v ../camera/sim/tb_camera_pose_overlay.sv ../camera/sim/tb_camera_integrated_panel.sv
foreach params {{} {-gSWIPE=1} {-gSWIPE=1 -gMIRROR=1}} {
 eval vsim -c work.tb_camera_pose_overlay $params
 onfinish stop
 run -all
 if {[examine -radix unsigned /tb_camera_pose_overlay/passed] != 1} {quit -code 1}
 quit -sim
}
vsim -c work.tb_camera_integrated_panel
onfinish stop
run -all
if {[examine -radix unsigned /tb_camera_integrated_panel/passed] != 1} {quit -code 1}
quit -sim
quit -code 0
