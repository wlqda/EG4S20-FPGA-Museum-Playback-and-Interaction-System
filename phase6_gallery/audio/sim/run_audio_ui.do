onerror {quit -code 1}
if {![file isdirectory audio_ui_work]} {vlib audio_ui_work}
vmap work audio_ui_work
vlog ../rtl/museum_phase5_top.v
vlog -sv ../rtl/museum_phase5_ui.v ../rtl/museum_phase5_font.v ../visualization/rtl/museum_audio_waveform.v ../audio/sim/tb_audio_ui.v ../audio/sim/tb_audio_waveform.v
vsim -c work.tb_audio_ui
onfinish stop
run -all
if {[examine -radix unsigned /tb_audio_ui/passed] != 1} {quit -code 1}
quit -sim
vsim -c work.tb_audio_waveform
onfinish stop
run -all
if {[examine -radix unsigned /tb_audio_waveform/passed] != 1} {quit -code 1}
quit -code 0