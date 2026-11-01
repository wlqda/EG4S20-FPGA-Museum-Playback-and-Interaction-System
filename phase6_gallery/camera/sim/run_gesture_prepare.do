onerror {quit -code 1}
if {![file isdirectory prepare_work]} {vlib prepare_work}
vmap work prepare_work
vlog -sv ../camera/rtl/camera_config_controller.v ../camera/rtl/camera_config_rom.v ../camera/rtl/camera_sccb_master.v ../camera/rtl/camera_dvp_capture.v ../camera/rtl/camera_dvp_auto_monitor.v ../camera/rtl/camera_source_stream.v ../camera/rtl/camera_hand_candidate.v ../camera/rtl/camera_palm_regions.v ../camera/rtl/camera_candidate_track.v ../camera/rtl/camera_foreground_overlay.v ../camera/rtl/camera_foreground_debug.v ../camera/rtl/camera_swipe_tracker.v ../camera/rtl/camera_nav_adapter.v ../camera/rtl/camera_pose_overlay.v ../camera/rtl/museum_camera_overlay.v ../camera/rtl/camera_telemetry_uart.v ../camera/rtl/camera_gesture_engine.v ../camera/sim/tb_gesture_prepare.sv ../camera/sim/tb_engine_preparation.sv
vsim -c work.tb_gesture_prepare
onfinish stop
run -all
if {[examine -radix unsigned /tb_gesture_prepare/passed] != 1} {quit -code 1}
quit -sim
vsim -c work.tb_engine_preparation
onfinish stop
run -all
if {[examine -radix unsigned /tb_engine_preparation/passed] != 1} {quit -code 1}
quit -code 0
