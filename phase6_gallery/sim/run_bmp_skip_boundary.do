onerror {quit -code 1}
if {![file isdirectory bmp_boundary_work]} {vlib bmp_boundary_work}
vmap work bmp_boundary_work
vlog -sv ../deps/core/phase2_museum_bmp_parser.v ../sim/tb_bmp_skip_boundary.sv
vsim -c work.tb_bmp_skip_boundary
onfinish stop
run -all
if {[examine -radix unsigned /tb_bmp_skip_boundary/passed] != 1} {quit -code 1}
quit -code 0
