onerror {quit -code 1}
if {![file isdirectory image_pipeline_work]} {vlib image_pipeline_work}
vmap work image_pipeline_work
vlog -sv ../rtl/museum_image_memory.v ../sim/tb_image_read_pipeline.v
vsim -c work.tb_image_read_pipeline
onfinish stop
run -all
if {[examine -radix unsigned /tb_image_read_pipeline/passed] != 1} {quit -code 1}
quit -code 0
