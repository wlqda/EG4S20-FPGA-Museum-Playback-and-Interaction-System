onerror {quit -code 1}
if {![file isdirectory extraction_work]} {vlib extraction_work}
vmap work extraction_work
vlog -sv ../camera/rtl/camera_hand_candidate.v ../camera/rtl/camera_palm_regions.v ../camera/rtl/camera_candidate_track.v ../camera/rtl/camera_foreground_overlay.v ../camera/rtl/camera_foreground_debug.v ../camera/sim/tb_filter_extraction.sv
vsim -c work.tb_filter_extraction
onfinish stop
run -all
if {[examine -radix unsigned /tb_filter_extraction/passed] != 1} {quit -code 1}
quit -code 0
