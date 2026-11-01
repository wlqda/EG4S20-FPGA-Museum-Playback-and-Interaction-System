onerror {quit -code 1}
if {![file isdirectory camera_core_work]} {vlib camera_core_work}
vmap work camera_core_work
# Archived tracker bench has an embedded old-UI model. Current UI is verified
# separately by run_unified.do; this reference never enters synthesis.
vlog -sv ../camera/sim/reference_archived_ui.v
vlog -sv ../camera/rtl/camera_swipe_tracker.v ../camera/rtl/camera_pose_events.v ../camera/rtl/camera_pose_classifier.v ../camera/rtl/camera_nav_adapter.v ../camera/sim/tb_camera_swipe_tracker.sv ../camera/sim/tb_camera_pose_classifier.sv
vlog -sv ../camera/rtl/camera_source_stream.v ../camera/rtl/camera_preview_buffer.v ../camera/rtl/camera_candidate_track.v ../camera/rtl/camera_palm_regions.v ../camera/rtl/camera_hand_candidate.v ../camera/rtl/camera_foreground_debug.v ../camera/rtl/camera_foreground_overlay.v ../camera/sim/tb_camera_source_stream.sv ../camera/sim/tb_camera_skin_regions.sv ../camera/rtl/camera_gesture_engine.v
vlog -sv ../camera/rtl/camera_telemetry_uart.v ../camera/sim/tb_camera_telemetry.sv
vlog -sv ../deps/av/rtl/fat32_extents.v ../deps/core/museum_phase1_mount.v ../camera/sim/tb_camera_gesture_fat.sv
vlog -sv ../camera/sim/tb_vertical_roi.sv
foreach test {tb_vertical_roi tb_camera_identity_selection tb_camera_swipe_tracker tb_camera_pose_classifier tb_camera_telemetry tb_camera_gesture_mount} {
 vsim -c work.$test
 onfinish stop
 run -all
 if {[examine -radix unsigned /$test/passed] != 1} {quit -code 1}
 quit -sim
}
vsim -c -gEDGE=1 work.tb_camera_pose_classifier
onfinish stop
run -all
if {[examine -radix unsigned /tb_camera_pose_classifier/passed] != 1} {quit -code 1}
quit -sim
vsim -c -gMODE=4 work.tb_camera_gesture_mount
onfinish stop
run -all
if {[examine -radix unsigned /tb_camera_gesture_mount/passed] != 1} {quit -code 1}
quit -sim
foreach mode {0 1 2 3} {
 vsim -c -gMODE=$mode work.tb_camera_gesture_extents
 onfinish stop
 run -all
 if {[examine -radix unsigned /tb_camera_gesture_extents/passed] != 1} {quit -code 1}
 quit -sim
}
vsim -c -gMAX_AREA=2400 -gMAX_ASPECT=4 -gFEATURES=1 work.tb_camera_skin_regions
onfinish stop
run -all
if {[examine -radix unsigned /tb_camera_skin_regions/passed] != 1} {quit -code 1}
quit -sim
vsim -c -gRECONSTRUCT=1 -gLOW_CONTRAST=1 -gPOSE=1 work.tb_camera_source_pipeline
onfinish stop
run -all
if {[examine -radix unsigned /tb_camera_source_pipeline/passed] != 1} {quit -code 1}
quit -sim
quit -code 0
