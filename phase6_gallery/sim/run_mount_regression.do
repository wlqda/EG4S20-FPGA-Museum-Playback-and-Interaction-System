onerror {quit -code 1}
if {![file isdirectory mount_work]} {vlib mount_work}
vmap work mount_work
vlog -sv ../deps/core/museum_phase1_mount.v ../deps/av/rtl/fat32_extents.v ../deps/core/museum_phase1_sdio_host.v ../deps/core/museum_phase1_sd_reader.v ../deps/core/museum_phase1_sdcmd.v ../sim/mount_fixtures/sd_fake_hs.v ../sim/tb_mount_regression.v
foreach params {{} {-gSUPERFLOPPY=1} {-gACTIVE_FAT=1} {-gBROKEN=1} {-gNATIVE=1} {-gMOUNT_ONLY=1} {-gMOUNT_ONLY=1 -gNATIVE=1}} {
 eval vsim -c -onfinish stop work.tb_mount_regression $params
 run -all
 if {[examine -radix unsigned /tb_mount_regression/passed] != 1} {quit -code 1}
 quit -sim
}
puts "PASS mount regression: MBR, superfloppy, active FAT, broken chain, native SD pins"
quit -code 0
