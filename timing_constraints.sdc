# Timing Constraints for Audio DSP Project

# Create base clock constraint for 50MHz system clock
create_clock -name clk_50mhz -period 20.000 [get_ports clk_50mhz]

# Derive PLL clocks automatically from PLL IP
derive_pll_clocks -create_base_clocks

# Set asynchronous paths to false, so they are ignored during analysis
set_false_path -from [get_ports reset_n] -to [all_registers]
set_false_path -from [get_ports midi_rx] -to [all_registers]
set_false_path -to [get_ports {test_point_1 test_point_2}]
set_false_path -to [get_ports {led[0] led[1] led[2] led[3]}]

# I2S clock domain constraints
# audio_pll generates 12.288MHz which gets divided to:
# - 12.288MHz for MCLK
# - 3.072MHz for BCLK
# - 48kHz for LRCLK

# I2S clocks must be constrained to within +/-5ns delay
set_output_delay -clock [get_clocks {*audio_pll*}] -max 5.0 [get_ports {i2s_mclk i2s_bclk i2s_lrclk i2s_dout}]
set_output_delay -clock [get_clocks {*audio_pll*}] -min -5.0 [get_ports {i2s_mclk i2s_bclk i2s_lrclk i2s_dout}]
set_input_delay -clock [get_clocks {*audio_pll*}] -max 5.0 [get_ports i2s_din]
set_input_delay -clock [get_clocks {*audio_pll*}] -min -5.0 [get_ports i2s_din]