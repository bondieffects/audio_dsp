# Updated Timing Constraints for Audio DSP Project

# Create base clock constraint for 50MHz system clock
create_clock -name clk_50mhz -period 20.000 [get_ports clk_50mhz]

# Derive PLL clocks automatically from PLL IP
derive_pll_clocks -create_base_clocks

# Set clock uncertainty for all clock domains
derive_clock_uncertainty

# Set asynchronous paths to false, so they are ignored during analysis
set_false_path -from [get_ports reset_n] -to [all_registers]
set_false_path -from [get_ports midi_rx] -to [all_registers]
set_false_path -to [get_ports {test_point_1 test_point_2}]
set_false_path -to [get_ports {led[0] led[1] led[2] led[3]}]

# Clock domain crossing paths - relax timing between different clock domains
set_false_path -from [get_clocks clk_50mhz] -to [get_clocks {*audio_pll*}]
set_false_path -from [get_clocks {*audio_pll*}] -to [get_clocks clk_50mhz]

# Relax I2S interface timing - these are external interfaces
set_false_path -to [get_ports {i2s_mclk i2s_bclk i2s_lrclk i2s_dout}]
set_false_path -from [get_ports i2s_din]

# Set multicycle paths for slow MIDI interface
set_multicycle_path -setup -from [get_ports midi_rx] 2
set_multicycle_path -hold -from [get_ports midi_rx] 1