onerror {quit -code 1}
if {![file isdirectory gallery_fat_work]} {vlib gallery_fat_work}
vmap work gallery_fat_work
vlog -sv ../rtl/museum_phase5_fat_index.v ../deps/core/phase2_museum_sd_sector.v ../sim/museum_sd_model.v ../sim/tb_gallery_fat.v
vsim -c work.tb_gallery_fat
onfinish stop
run -all
if {[examine -radix unsigned /tb_gallery_fat/passed] != 1} {quit -code 1}
quit -code 0
