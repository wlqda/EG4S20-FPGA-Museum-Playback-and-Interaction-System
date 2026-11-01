create_clock -name SYS_CLK -period 20 [get_ports {sys_clk}]
create_generated_clock -name SERIAL_CLK -source [get_ports {sys_clk}] -multiply_by 2.5 [get_nets {core/serial_clk}]
create_generated_clock -name PIXEL_CLK -source [get_ports {sys_clk}] -divide_by 2 [get_nets {core/pixel_clk}]
create_generated_clock -name MEMORY_CLK -source [get_ports {sys_clk}] -multiply_by 2 [get_nets {core/mem_clk}]
create_generated_clock -name SDRAM_CLK -source [get_ports {sys_clk}] -edges {1 2 3} -edge_shift {7.25 2.25 -2.75} [get_nets {core/sdram_clk}]
# SDRAM clock/pad flight time exceeds the nearest half-cycle capture window.
# The controller intentionally captures the following cycle (CAPTURE_DELAY=4).
set_multicycle_path 2 -setup -from [get_clocks {SDRAM_CLK}] -to [get_clocks {MEMORY_CLK}]
set_multicycle_path 1 -hold -from [get_clocks {SDRAM_CLK}] -to [get_clocks {MEMORY_CLK}]
