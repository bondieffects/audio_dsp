# Timing Constraints for Audio DSP Project
# Save this as timing_constraints.sdc
# Add to project: Project -> Add/Remove Files in Project

# Create base clock constraint for 50MHz system clock
create_clock -name clk_50mhz -period 20.000 [get_ports clk_50mhz]

# Derive PLL clocks automatically from PLL IP
derive_pll_clocks -create_base_clocks

# Set false paths for asynchronous reset
set_false_path -from [get_ports reset_n] -to [all_registers]

# MIDI serial data is asynchronous, set false path
set_false_path -from [get_ports midi_rx] -to [all_registers]

# I2S clock domain constraints (will be derived from PLL)
# The audio_pll will generate 12.288MHz which gets divided down to:
# - 3.072MHz for BCLK
# - 48kHz for LRCLK

# Set output delay constraints for I2S signals (relative to BCLK)
set_output_delay -clock [get_clocks {*audio_pll*}] -max 5.0 [get_ports {i2s_bclk i2s_lrclk i2s_dout}]
set_output_delay -clock [get_clocks {*audio_pll*}] -min -5.0 [get_ports {i2s_bclk i2s_lrclk i2s_dout}]

# Set input delay constraints for I2S input data
set_input_delay -clock [get_clocks {*audio_pll*}] -max 5.0 [get_ports i2s_din]
set_input_delay -clock [get_clocks {*audio_pll*}] -min -5.0 [get_ports i2s_din]