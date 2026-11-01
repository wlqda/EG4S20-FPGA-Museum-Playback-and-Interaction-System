onerror {quit -code 1}
if {![file isdirectory v3_preview_work]} {vlib v3_preview_work}
vmap work v3_preview_work
vlog -sv ../rtl/museum_phase5_render.v ../rtl/museum_floating_clock.v ../visualization/rtl/museum_audio_waveform.v ../sim/tb_v3_previews.v
vsim -c work.tb_v3_previews
onfinish stop
run -all
if {[examine -radix unsigned /tb_v3_previews/passed] != 1} {quit -code 1}
quit -code 0
