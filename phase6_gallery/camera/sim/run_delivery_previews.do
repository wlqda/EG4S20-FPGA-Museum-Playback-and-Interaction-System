onerror {quit -code 1}
if {![file isdirectory delivery_preview_work]} {vlib delivery_preview_work}
vmap work delivery_preview_work
vlog -sv ../rtl/museum_phase5_render.v ../rtl/museum_floating_clock.v ../visualization/rtl/museum_audio_waveform.v ../camera/rtl/camera_pose_overlay.v gesture_full/delivery_preview/tb_delivery_previews.sv
vsim -c work.tb_delivery_previews
onfinish stop
run -all
if {[examine -radix unsigned /tb_delivery_previews/passed] != 1} {quit -code 1}
quit -code 0
