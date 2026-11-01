onerror {quit -code 1}
if {![file isdirectory av_demux_work]} {vlib av_demux_work}
vmap work av_demux_work
vlog -sv ../deps/av/rtl/av_demux.v ../sim/tb_av_demux.v
vsim -c work.tb_av_demux
onfinish stop
run -all
quit -code 0
