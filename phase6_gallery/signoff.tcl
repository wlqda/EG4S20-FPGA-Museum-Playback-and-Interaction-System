# Run in a fresh TD process, independently of physical optimization.
if {[catch {
cd [file dirname [info script]]
set phase6_signoff_output [file normalize build]
if {[info exists env(PHASE6_SIGNOFF_DIR)]} {set phase6_signoff_output [file normalize $env(PHASE6_SIGNOFF_DIR)]}
set phase6_signoff_db "$phase6_signoff_output/museum_phase6_gallery_pr.db"
set phase6_status_path "$phase6_signoff_output/final.ts"
set phase6_detail_path "$phase6_signoff_output/final.timing"
set phase6_exceptions_path "$phase6_signoff_output/final.exceptions"
set phase6_area_path "$phase6_signoff_output/final.area"
set phase6_verified_db "$phase6_signoff_output/museum_phase6_gallery_signoff.db"
set phase6_bit_path "$phase6_signoff_output/museum_phase6_gallery.bit"
import_device eagle_s20.db -package EG4S20BG256
puts "SIGNOFF DATABASE: $phase6_signoff_db"
import_db $phase6_signoff_db
clear_sdc
read_sdc constraints/phase5.sdc
update_timing -mode final
report_timing_status -file $phase6_status_path
report_timing_summary -file $phase6_detail_path
report_timing_exception -file $phase6_exceptions_path
report_area -io_info -file $phase6_area_path
report_route_status -drc
set phase6_fd [open $phase6_detail_path r]
set phase6_detail [read $phase6_fd]
close $phase6_fd
foreach {name mhz} {MEMORY_CLK 100 PIXEL_CLK 25 SERIAL_CLK 125 SYS_CLK 50 SDRAM_CLK 100} {
 set pattern [format {clk[0-9]+:\s+%d[.]000\s+[1-9][0-9]*\s+%s(\s|$)} $mhz $name]
 if {![regexp $pattern $phase6_detail]} {error "Missing or wrong signoff clock: $name"}
}
if {![regexp {STA coverage\s+:\s+([0-9.]+)%} $phase6_detail unused phase6_coverage] || $phase6_coverage<99.0} {error "Insufficient STA coverage"}
set phase6_fd [open $phase6_status_path r]
set phase6_status [read $phase6_fd]
close $phase6_fd
foreach label {SWNS HWNS} {
 set pattern [format {%s:\s*([+-]?[0-9.]+)ns} $label]
 if {![regexp $pattern $phase6_status unused value] || $value<0 || [string match {-*} $value]} {error "Timing closure failed: $phase6_status"}
}
export_db $phase6_verified_db
bitgen -bit $phase6_bit_path
puts "PASS ORIGINAL-SDC SIGNOFF: five clocks, coverage $phase6_coverage, $phase6_status"
} err]} {puts stderr "SIGNOFF FAILED: $err";exit 1}
exit 0
