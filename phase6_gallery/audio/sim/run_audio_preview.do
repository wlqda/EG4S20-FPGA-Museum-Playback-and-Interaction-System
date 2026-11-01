onerror {quit -code 1}
if {![file isdirectory audio_preview_work]} {vlib audio_preview_work}
vmap work audio_preview_work
vlog -sv ../rtl/museum_phase5_font.v ../rtl/museum_floating_clock.v ../visualization/rtl/museum_audio_waveform.v ../audio/sim/tb_audio_preview.v
vsim -c work.tb_audio_preview
onfinish stop
run -all
if {[examine -radix unsigned /tb_audio_preview/passed] != 1} {quit -code 1}
quit -code 0