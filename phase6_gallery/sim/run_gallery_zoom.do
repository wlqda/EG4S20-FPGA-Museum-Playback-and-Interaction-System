onerror {quit -code 1}
if {![file isdirectory gallery_zoom_work]} {vlib gallery_zoom_work}
vmap work gallery_zoom_work
vlog -sv ../rtl/museum_image_memory.v ../rtl/museum_phase2_image_display.v ../deps/av/rtl/error_overlay.v ../deps/av/rtl/av_status_overlay.v ../sim/tb_gallery_zoom.v
vsim -c work.tb_gallery_zoom
onfinish stop
run -all
if {[examine -radix unsigned /tb_gallery_zoom/passed] != 1} {quit -code 1}
quit -code 0
