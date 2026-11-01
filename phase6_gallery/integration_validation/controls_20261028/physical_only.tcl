if {[catch {
cd [file normalize [file join [file dirname [info script]] ../..]]
import_device eagle_s20.db -package EG4S20BG256
import_db build/gesture_full/museum_phase6_gallery_gate.db
set original [open camera/constraints/unified.sdc r]
set text [read $original]
close $original
set margin [open build/gesture_full/optimization.sdc w]
puts -nonewline $margin $text
puts $margin {set_clock_uncertainty -setup 0.400 [get_clocks {SYS_CLK SERIAL_CLK PIXEL_CLK MEMORY_CLK SDRAM_CLK CAMERA_CLK DVP_CLK CAPTURE_CLK}]}
puts $margin {set_clock_uncertainty -hold 0.020 [get_clocks {SYS_CLK SERIAL_CLK PIXEL_CLK MEMORY_CLK SDRAM_CLK CAMERA_CLK DVP_CLK CAPTURE_CLK}]}
close $margin
clear_sdc
read_sdc build/gesture_full/optimization.sdc
update_timing
# TD 6.2 official TimingUltra physical strategy (no timing exceptions).
set_param place macro_performance dsp_ram_crit_path
set_param route effort routability
set_param route timing greedy
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
set_param place seed 44
set_param place fix_hold on
set_param route hold_fix_iteration 20
place
route
fix_hold
update_timing -mode final
report_timing_status -file build/gesture_full/routing_margin.ts
export_db build/gesture_full/museum_phase6_gallery_pr.db
puts "PASS PHYSICAL IMPLEMENTATION"
} err]} {puts stderr "BUILD FAILED: $err";exit 1}
exit 0
