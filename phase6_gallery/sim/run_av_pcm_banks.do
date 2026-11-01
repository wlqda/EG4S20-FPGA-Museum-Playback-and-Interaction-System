onerror {quit -code 1}
if {![file isdirectory av_pcm_work]} {vlib av_pcm_work}
vmap work av_pcm_work
vlog -sv ../deps/core/museum_phase1_audio.v ../sim/tb_av_pcm_banks.v
vsim -c work.tb_av_pcm_banks
onfinish stop
run -all
if {[examine -radix unsigned /tb_av_pcm_banks/passed] != 1} {quit -code 1}
quit -code 0
