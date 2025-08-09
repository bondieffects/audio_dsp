# Pin assignments for EP4CE6E22C8N Cyclone IV FPGA
# Audio DSP Project - Group 10
# Run this from Quartus GUI using Tools -> Tcl Scripts

# System Clock and Reset
set_location_assignment PIN_23 -to clk_50mhz
set_location_assignment PIN_88 -to reset_n

# I2S Interface Pins (connect to WM8731 CODEC)
set_location_assignment PIN_30 -to i2s_bclk
set_location_assignment PIN_31 -to i2s_lrclk
set_location_assignment PIN_32 -to i2s_din
set_location_assignment PIN_33 -to i2s_dout

# MIDI Interface (from Arduino)
set_location_assignment PIN_89 -to midi_rx

# Status LEDs
set_location_assignment PIN_84 -to led[0]
set_location_assignment PIN_85 -to led[1]
set_location_assignment PIN_86 -to led[2]
set_location_assignment PIN_87 -to led[3]

# Test Points for debugging (changed to output-capable pins)
set_location_assignment PIN_133 -to test_point_1
set_location_assignment PIN_135 -to test_point_2

# I/O Standards
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to clk_50mhz
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to reset_n
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to i2s_bclk
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to i2s_lrclk
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to i2s_din
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to i2s_dout
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to midi_rx
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to led[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to led[1]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to led[2]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to led[3]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to test_point_1
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to test_point_2

puts "Pin assignments completed successfully!"