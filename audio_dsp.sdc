# ============================================================================
# AUDIO DSP TIMING CONSTRAINTS
# Improved constraints for reliable I2S operation
# ============================================================================

# ============================================================================
# Primary Clocks
# ============================================================================

# 50MHz system clock
create_clock -name {clk_50mhz} -period 20.000 [get_ports {clk_50mhz}]

# Auto-derive PLL clocks (12.288MHz MCLK)
derive_pll_clocks

# Create virtual clock for I2S BCLK (1.536MHz = 650.521ns period)
# This represents the expected BCLK frequency
create_clock -name {virtual_bclk} -period 650.521

# ============================================================================
# Generated Clocks (Internal)
# ============================================================================

# I2S BCLK generated internally (treat as generated clock)
create_generated_clock -name {i2s_bclk_int} \
    -source [get_pins {u_audio_pll|altpll_component|auto_generated|pll1|clk[0]}] \
    -divide_by 8 \
    [get_registers {i2s_clocks:u_i2s_clocks|bclk_signal}]

# ============================================================================
# Clock Groups and Relationships
# ============================================================================

# Set clock groups to prevent timing analysis between unrelated clock domains
set_clock_groups -asynchronous \
    -group {clk_50mhz} \
    -group {u_audio_pll|altpll_component|auto_generated|pll1|clk[0]} \
    -group {i2s_bclk_int virtual_bclk}

# ============================================================================
# False Paths
# ============================================================================

# Reset is asynchronous
set_false_path -from [get_ports {reset_n}]

# LEDs and test points are not timing critical
set_false_path -to [get_ports {led[*]}]
set_false_path -to [get_ports {test_point_*}]

# I2S outputs are not timing critical (external CODEC will handle setup/hold)
set_false_path -to [get_ports {i2s_mclk}]
set_false_path -to [get_ports {i2s_bclk}] 
set_false_path -to [get_ports {i2s_ws}]
set_false_path -to [get_ports {i2s_dout}]

# I2S input has external timing
set_false_path -from [get_ports {i2s_din}]

# ============================================================================
# Input/Output Delays (Conservative estimates)
# ============================================================================

# I2S input timing (conservative)
set_input_delay -clock virtual_bclk -max 100.0 [get_ports {i2s_din}]
set_input_delay -clock virtual_bclk -min -100.0 [get_ports {i2s_din}]

# ============================================================================
# Clock Uncertainty
# ============================================================================

derive_clock_uncertainty