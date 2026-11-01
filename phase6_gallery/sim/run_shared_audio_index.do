onerror {quit -code 1}
if {![file isdirectory shared_audio_work]} {vlib shared_audio_work}
vmap work shared_audio_work
vlog -sv ../rtl/museum_phase5_fat_index.v ../deps/core/phase2_museum_sd_sector.v ../deps/core/museum_sd_service.v ../sim/museum_sd_model.v ../sim/tb_gallery_fat.v ../audio/rtl/*.v ../audio/sim/tb_narration.v
vsim -c work.tb_gallery_fat -gCACHE_AUDIO=1
onfinish stop
run -all
if {[examine -radix unsigned /tb_gallery_fat/passed] != 1} {quit -code 1}
quit -sim
foreach slot {-1 0 1 2 3} {
 vsim -c -onfinish stop work.tb_narration -gCACHED=1 -gMBR_SLOT=$slot
 run -all
 if {[examine -radix unsigned /tb_narration/passed] != 1} {quit -code 1}
 quit -sim
}
puts "PASS shared index: one BMP/WAV directory scan; cached narration in superfloppy and all four MBR slots"
quit -code 0
