# Pin assignments for EP4CE6E22C8 Cyclone IV FPGA
# Audio DSP Project - Group 10

# System Clock and Reset
set_location_assignment PIN_23 -to clk_50mhz
set_location_assignment PIN_25 -to reset_n

# I2S Interface Pins (connect to WM8731 CODEC)
set_location_assignment PIN_30 -to i2s_mclk
set_location_assignment PIN_31 -to i2s_bclk
set_location_assignment PIN_32 -to i2s_ws
set_location_assignment PIN_33 -to i2s_din
set_location_assignment PIN_34 -to i2s_dout

# MIDI Interface
set_location_assignment PIN_115 -to midi_rx

# Status LEDs
set_location_assignment PIN_84 -to led[0]
set_location_assignment PIN_85 -to led[1]
set_location_assignment PIN_86 -to led[2]
set_location_assignment PIN_87 -to led[3]

# 7-segment display
set_location_assignment PIN_128 -to seg[6]
set_location_assignment PIN_121 -to seg[5]
set_location_assignment PIN_125 -to seg[4]
set_location_assignment PIN_129 -to seg[3]
set_location_assignment PIN_132 -to seg[2]
set_location_assignment PIN_126 -to seg[1]
set_location_assignment PIN_124 -to seg[0]

# 7-segment digit select
set_location_assignment PIN_133 -to seg_sel[0]
set_location_assignment PIN_135 -to seg_sel[1]
set_location_assignment PIN_136 -to seg_sel[2]
set_location_assignment PIN_137 -to seg_sel[3]

# Test Points for debugging
set_location_assignment PIN_50 -to test_point_1
set_location_assignment PIN_51 -to test_point_2

# I/O Standards - Using 3.3V LVCMOS for all pins
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to clk_50mhz
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to reset_n
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to i2s_mclk
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to i2s_bclk
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to i2s_lrclk
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to i2s_din
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to i2s_dout
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to midi_rx
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to led[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to led[1]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to led[2]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to led[3]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to test_point_1
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to test_point_2
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to seg[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to seg[1]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to seg[2]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to seg[3]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to seg[4]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to seg[5]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to seg[6]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to seg_sel[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to seg_sel[1]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to seg_sel[2]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to seg_sel[3]

# Current Strength Settings for outputs
set_instance_assignment -name CURRENT_STRENGTH_NEW "MINIMUM CURRENT" -to led[0]
set_instance_assignment -name CURRENT_STRENGTH_NEW "MINIMUM CURRENT" -to led[1]
set_instance_assignment -name CURRENT_STRENGTH_NEW "MINIMUM CURRENT" -to led[2]
set_instance_assignment -name CURRENT_STRENGTH_NEW "MINIMUM CURRENT" -to led[3]
set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to i2s_mclk
set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to i2s_bclk
set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to i2s_lrclk
set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to i2s_dout

# Clock pin settings
set_instance_assignment -name GLOBAL_SIGNAL "GLOBAL CLOCK" -to clk_50mhz

puts "Pin assignments completed successfully!"