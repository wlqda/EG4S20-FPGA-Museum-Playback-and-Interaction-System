onerror {quit -code 1}
if {![file isdirectory narration_work]} {vlib narration_work}
vmap work narration_work
vlog -sv ../deps/core/phase2_museum_sd_sector.v ../deps/core/museum_sd_service.v ../audio/rtl/*.v ../audio/sim/tb_narration.v
vsim -c work.tb_narration
onfinish stop
run -all
if {[examine -radix unsigned /tb_narration/passed] != 1} {quit -code 1}
quit -code 0