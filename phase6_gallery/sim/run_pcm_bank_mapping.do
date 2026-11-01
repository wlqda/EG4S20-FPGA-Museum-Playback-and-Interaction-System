onerror {quit -code 1}
if {![file isdirectory pcm_mapping_work]} {vlib pcm_mapping_work}
vmap work pcm_mapping_work
vlog -sv ../deps/core/museum_phase1_audio.v ../sim/tb_pcm_bank_mapping.v
vsim -c work.tb_pcm_bank_mapping
onfinish stop
run -all
if {[examine -radix unsigned /tb_pcm_bank_mapping/passed] != 1} {quit -code 1}
quit -code 0
