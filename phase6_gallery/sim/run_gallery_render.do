onerror {quit -code 1}
if {![file isdirectory gallery_render_work]} {vlib gallery_render_work}
vmap work gallery_render_work
vlog -sv ../rtl/museum_phase5_render.v ../rtl/museum_phase5_font.v ../rtl/museum_gallery_logo.v ../sim/tb_gallery_render.v
vsim -c work.tb_gallery_render
onfinish stop
run -all
if {[examine -radix unsigned /tb_gallery_render/passed] != 1} {quit -code 1}
quit -code 0
