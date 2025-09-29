# ============================================================================
# MINIMAL Timing Constraints for Debugging
# Use this file to get compilation working first, then add more constraints
# ============================================================================

# ============================================================================
# Essential Clocks Only
# ============================================================================

# Primary system clock
create_clock -name {clk_50mhz} -period 20.000 [get_ports {clk_50mhz}]

# Let Quartus auto-derive all PLL clocks
derive_pll_clocks

# ============================================================================
# Essential False Paths
# ============================================================================

# Reset is asynchronous
set_false_path -from [get_ports {reset_n}]

# LEDs and test points are not critical
set_false_path -to [get_ports {led[*]}]
set_false_path -to [get_ports {test_point_*}]

# ============================================================================
# Derive Clock Uncertainty (let Quartus calculate)
# ============================================================================

derive_clock_uncertainty