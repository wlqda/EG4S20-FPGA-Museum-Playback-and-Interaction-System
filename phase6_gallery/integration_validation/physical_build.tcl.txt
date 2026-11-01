# Physical implementation only. Final signoff runs in a fresh TD process.
if {[catch {
cd [file dirname [info script]]
import_device eagle_s20.db -package EG4S20BG256
open_project -single_run museum_phase6_gallery.al
set_param rtl infer_fsm one_hot
set_param rtl min_ripple_len 18
set_param gate map_mode balance_explore
set_param gate mapper_lut_delay 2200
set_param gate merge_tiny_lut on
elaborate -top museum_phase6_top
read_adc constraints/phase5.adc
read_sdc constraints/phase5.sdc
optimize_rtl
report_area -file build/rtl.area
optimize_gate
legalize_phy_inst
export_db build/museum_phase6_gallery_gate.db
report_area -file build/gate.area
set original [open constraints/phase5.sdc r]
set text [read $original]
close $original
set margin [open build/optimization.sdc w]
puts -nonewline $margin $text
puts $margin {set_clock_uncertainty -setup 0.400 [get_clocks {SYS_CLK SERIAL_CLK PIXEL_CLK MEMORY_CLK SDRAM_CLK}]}
puts $margin {set_clock_uncertainty -hold 0.020 [get_clocks {SYS_CLK SERIAL_CLK PIXEL_CLK MEMORY_CLK SDRAM_CLK}]}
close $margin
clear_sdc
read_sdc build/optimization.sdc
update_timing
# TD 6.2 official TimingUltra physical strategy (no timing exceptions).
set_param place effort high
set_param place opt_timing high
set_param place logic_level_opt on
set_param place aggressive_opt 21
set_param place aggr_neighbor_dist 5
set_param place enhanced_beeline_opt 3
set_param place timing_driven_mode on
set_param place shifter_opt on
set_param place crit_path_opt on
set_param place post_place_opt high
set_param place hfn_opt_effort high
set_param place split_data_from_clock on
set_param route post_route_opt high
set_param route postrt_opt_extra_round 4
set_param place seed 43
set_param place fix_hold on
set_param route hold_fix_iteration 20
place
route
update_timing -mode final
report_timing_status -file build/routing_margin.ts
export_db build/museum_phase6_gallery_pr.db
puts "PASS PHYSICAL IMPLEMENTATION"
} err]} {puts stderr "BUILD FAILED: $err";exit 1}
exit 0
