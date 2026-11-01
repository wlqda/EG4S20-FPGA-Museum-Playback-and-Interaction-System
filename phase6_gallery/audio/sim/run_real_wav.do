onerror {quit -code 1}
if {![file isdirectory real_wav_work]} {vlib real_wav_work}
vmap work real_wav_work
vlog -sv ../audio/rtl/museum_wav_parser.v ../audio/sim/tb_real_wav.v
vsim -c work.tb_real_wav
onfinish stop
run -all
if {[examine -radix unsigned /tb_real_wav/passed] != 1} {quit -code 1}
quit -code 0