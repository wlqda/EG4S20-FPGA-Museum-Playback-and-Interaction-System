onerror {quit -code 1}
if {![file isdirectory pipeline_work]} {vlib pipeline_work}
vmap work pipeline_work
vlog ../rtl/museum_phase5_render.v ../rtl/museum_phase5_font.v ../rtl/museum_gallery_logo.v ../sim/reference_render_20261027.v ../sim/tb_render_pipeline.v
vsim -c work.tb_render_pipeline
onfinish stop
run -all
if {[examine -radix unsigned /tb_render_pipeline/passed] != 1} {quit -code 1}
quit -code 0
