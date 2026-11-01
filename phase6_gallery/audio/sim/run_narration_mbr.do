onerror {quit -code 1}
if {![file isdirectory narration_mbr_work]} {vlib narration_mbr_work}
vmap work narration_mbr_work
vlog -sv ../deps/core/phase2_museum_sd_sector.v ../deps/core/museum_sd_service.v ../audio/rtl/*.v ../audio/sim/tb_narration.v
foreach slot {0 1 2 3} {
 vsim -c -gMBR_SLOT=$slot work.tb_narration
 onfinish stop
 run -all
 if {[examine -radix unsigned /tb_narration/passed] != 1} {quit -code 1}
 quit -sim
}
puts "PASS narration MBR: all four partition slots with 16 audio scenarios each"
quit -code 0
