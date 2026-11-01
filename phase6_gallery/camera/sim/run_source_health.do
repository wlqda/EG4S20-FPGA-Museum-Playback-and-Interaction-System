onerror {quit -code 1}
if {![file isdirectory source_health_work]} {vlib source_health_work}
vmap work source_health_work
vlog -sv ../camera/rtl/camera_source_stream.v ../camera/sim/tb_camera_source_stream.sv
foreach test {tb_camera_source_stream tb_camera_source_budget} {
 vsim -c work.$test
 onfinish stop
 run -all
 if {[examine -radix unsigned /$test/passed] != 1} {quit -code 1}
 quit -sim
}
quit -code 0
