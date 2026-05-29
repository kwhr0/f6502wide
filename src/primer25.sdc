create_clock -name I_clk -period 20 [get_ports {I_clk}] -add
create_generated_clock -name clk -source [get_ports {I_clk}] -master_clock I_clk -multiply_by 55 -divide_by 50 [get_nets {clk}]
create_generated_clock -name c_clk -source [get_ports {I_clk}] -master_clock I_clk -multiply_by 70 -divide_by 50 [get_nets {c_clk}]
set_clock_groups -asynchronous
	-group [get_clocks {clk}] 
	-group [get_clocks {c_clk}] 
	-group [get_clocks {I_clk}]
