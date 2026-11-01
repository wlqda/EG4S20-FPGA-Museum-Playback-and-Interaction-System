onerror {quit -code 1}
if {![file isdirectory prepare_stream_work]} {vlib prepare_stream_work}
vmap work prepare_stream_work
vlog -sv ../camera/rtl/camera_source_stream.v ../camera/sim/tb_prepare_stream.sv
vsim -c work.tb_prepare_stream
onfinish stop
run -all
if {[examine -radix unsigned /tb_prepare_stream/passed] != 1} {quit -code 1}
quit -code 0
