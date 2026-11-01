onerror {quit -code 1}
if {![file isdirectory full_preview_work]} {vlib full_preview_work}
vmap work full_preview_work
vlog -sv ../rtl/museum_phase5_render.v ../rtl/museum_floating_clock.v ../visualization/rtl/museum_audio_waveform.v ../camera/rtl/camera_pose_overlay.v ../camera/rtl/museum_camera_overlay.v gesture_full/preview/tb_full_previews.sv
vsim -c work.tb_full_previews
onfinish stop
run -all
if {[examine -radix unsigned /tb_full_previews/passed] != 1} {quit -code 1}
quit -code 0
