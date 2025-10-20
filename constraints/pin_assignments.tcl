# Pin assignments for EP4CE6E22C8 Cyclone IV FPGA
# Audio DSP Project - Group 10
# Simple I2S Pass-Through System

# System Clock and Reset
set_location_assignment PIN_23 -to clk_50mhz
set_location_assignment PIN_25 -to reset_n

# I2S Interface Pins (connect to WM8731 CODEC)
set_location_assignment PIN_30 -to i2s_mclk
set_location_assignment PIN_31 -to i2s_bclk
set_location_assignment PIN_32 -to i2s_ws
set_location_assignment PIN_33 -to i2s_din
set_location_assignment PIN_34 -to i2s_dout

set_location_assignment PIN_115 -to midi_in

# Status LEDs
set_location_assignment PIN_84 -to led[0]
set_location_assignment PIN_85 -to led[1]
set_location_assignment PIN_86 -to led[2]
set_location_assignment PIN_87 -to led[3]

# Test Points for debugging
set_location_assignment PIN_50 -to test_point_1
set_location_assignment PIN_51 -to test_point_2

# I/O Standards - Using 3.3V LVCMOS for all pins
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to clk_50mhz
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to reset_n
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to i2s_mclk
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to i2s_bclk
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to i2s_ws
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to i2s_din
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to i2s_dout
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to led[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to led[1]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to led[2]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to led[3]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to test_point_1
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to test_point_2

# Current Strength Settings for outputs
set_instance_assignment -name CURRENT_STRENGTH_NEW "MINIMUM CURRENT" -to led[0]
set_instance_assignment -name CURRENT_STRENGTH_NEW "MINIMUM CURRENT" -to led[1]
set_instance_assignment -name CURRENT_STRENGTH_NEW "MINIMUM CURRENT" -to led[2]
set_instance_assignment -name CURRENT_STRENGTH_NEW "MINIMUM CURRENT" -to led[3]
set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to i2s_mclk
set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to i2s_bclk
set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to i2s_ws
set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to i2s_dout

# Clock pin settings
set_instance_assignment -name GLOBAL_SIGNAL "GLOBAL CLOCK" -to clk_50mhz

puts "Pin assignments completed successfully!"
puts "Simple I2S Pass-Through System with i2s_ws naming"