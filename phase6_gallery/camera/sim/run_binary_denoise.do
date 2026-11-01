onerror {quit -code 1}
if {![file isdirectory binary_work]} {vlib binary_work}
vmap work binary_work
vlog -sv ../camera/rtl/camera_foreground_debug.v ../camera/sim/tb_binary_denoise.sv
vsim -c work.tb_binary_denoise
onfinish stop
run -all
if {[examine -radix unsigned /tb_binary_denoise/passed] != 1} {quit -code 1}
quit -code 0
