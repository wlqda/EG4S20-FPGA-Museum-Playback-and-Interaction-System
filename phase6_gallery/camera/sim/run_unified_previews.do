onerror {quit -code 1}
if {![file isdirectory unified_preview_work]} {vlib unified_preview_work}
vmap work unified_preview_work
vlog -sv ../rtl/museum_phase5_render.v ../rtl/museum_floating_clock.v ../visualization/rtl/museum_audio_waveform.v ../camera/rtl/museum_camera_overlay.v gesture_unified/preview/tb_unified_previews.sv
vsim -c work.tb_unified_previews
onfinish stop
run -all
if {[examine -radix unsigned /tb_unified_previews/passed] != 1} {quit -code 1}
quit -code 0
