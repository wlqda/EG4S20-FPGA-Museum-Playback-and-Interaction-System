onerror {quit -code 1}
if {![file isdirectory status_work]} {vlib status_work}
vmap work status_work
vlog ../rtl/museum_phase5_font.v ../visualization/rtl/museum_audio_waveform.v ../sim/reference_waveform_20261027.v ../sim/tb_status_rom.v
vsim -c work.tb_status_rom
onfinish stop
run -all
if {[examine -radix unsigned /tb_status_rom/passed] != 1} {quit -code 1}
quit -code 0
