onerror {quit -code 1}
if {![file isdirectory idle_policy_work]} {vlib idle_policy_work}
vmap work idle_policy_work
vlog -sv ../rtl/museum_phase5_ui.v ../sim/tb_idle_policy.v
vsim -c work.tb_idle_policy
onfinish stop
run -all
if {[examine -radix unsigned /tb_idle_policy/passed] != 1} {quit -code 1}
quit -code 0
