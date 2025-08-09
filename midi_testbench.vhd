-- MIDI Interface Testbench
-- Tests MIDI UART receiver and parser functionality
-- Author: Group 10

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity midi_testbench is
end entity midi_testbench;

architecture testbench of midi_testbench is
    
    -- Test parameters
    constant CLK_PERIOD : time := 20 ns;  -- 50MHz clock
    constant MIDI_BIT_PERIOD : time := 32 us;  -- 31.25 kHz MIDI baud rate
    
    -- Component under test
    component midi_uart_rx is
        port (
            clk         : in  std_logic;
            reset_n     : in  std_logic;
            midi_rx     : in  std_logic;
            data_out    : out std_logic_vector(7 downto 0);
            data_valid  : out std_logic;
            error       : out std_logic
        );
    end component;
    
    component midi_parser is
        port (
            clk              : in  std_logic;
            reset_n          : in  std_logic;
            midi_data        : in  std_logic_vector(7 downto 0);
            midi_valid       : in  std_logic;
            bitcrush_depth   : out std_logic_vector(3 downto 0);
            sample_decimate  : out std_logic_vector(3 downto 0);
            master_volume    : out std_logic_vector(7 downto 0);
            param_updated    : out std_logic;
            midi_channel     : out std_logic_vector(3 downto 0)
        );
    end component;
    
    -- Test signals
    signal clk         : std_logic := '0';
    signal reset_n     : std_logic := '0';
    signal midi_rx     : std_logic := '1';
    signal midi_data   : std_logic_vector(7 downto 0);
    signal midi_valid  : std_logic;
    signal midi_error  : std_logic;
    
    -- Parser outputs
    signal bitcrush_depth  : std_logic_vector(3 downto 0);
    signal sample_decimate : std_logic_vector(3 downto 0);
    signal master_volume   : std_logic_vector(7 downto 0);
    signal param_updated   : std_logic;
    signal midi_channel    : std_logic_vector(3 downto 0);
    
    -- Test control
    signal test_done : boolean := false;
    
begin
    
    -- Clock generation
    clk <= not clk after CLK_PERIOD/2 when not test_done;
    
    -- Instantiate UART receiver
    u_uart_rx : midi_uart_rx
        port map (
            clk        => clk,
            reset_n    => reset_n,
            midi_rx    => midi_rx,
            data_out   => midi_data,
            data_valid => midi_valid,
            error      => midi_error
        );
    
    -- Instantiate MIDI parser
    u_parser : midi_parser
        port map (
            clk             => clk,
            reset_n         => reset_n,
            midi_data       => midi_data,
            midi_valid      => midi_valid,
            bitcrush_depth  => bitcrush_depth,
            sample_decimate => sample_decimate,
            master_volume   => master_volume,
            param_updated   => param_updated,
            midi_channel    => midi_channel
        );
    
    -- Test stimulus
    test_process : process
        
        -- Procedure to send a MIDI byte
        procedure send_midi_byte(byte_val : std_logic_vector(7 downto 0)) is
        begin
            -- Start bit
            midi_rx <= '0';
            wait for MIDI_BIT_PERIOD;
            
            -- Data bits (LSB first)
            for i in 0 to 7 loop
                midi_rx <= byte_val(i);
                wait for MIDI_BIT_PERIOD;
            end loop;
            
            -- Stop bit
            midi_rx <= '1';
            wait for MIDI_BIT_PERIOD;
            
            -- Inter-byte gap
            wait for MIDI_BIT_PERIOD;
        end procedure;
        
        -- Procedure to send Program Change message
        procedure send_program_change(channel : integer; program : integer) is
        begin
            report "Sending Program Change: Channel " & integer'image(channel) & 
                   ", Program " & integer'image(program);
            send_midi_byte(std_logic_vector(to_unsigned(16#C0# + channel, 8)));
            send_midi_byte(std_logic_vector(to_unsigned(program, 8)));
            wait for 10 * CLK_PERIOD;  -- Allow processing time
        end procedure;
        
        -- Procedure to send Control Change message
        procedure send_control_change(channel : integer; cc_num : integer; cc_val : integer) is
        begin
            report "Sending Control Change: Channel " & integer'image(channel) & 
                   ", CC " & integer'image(cc_num) & ", Value " & integer'image(cc_val);
            send_midi_byte(std_logic_vector(to_unsigned(16#B0# + channel, 8)));
            send_midi_byte(std_logic_vector(to_unsigned(cc_num, 8)));
            send_midi_byte(std_logic_vector(to_unsigned(cc_val, 8)));
            wait for 10 * CLK_PERIOD;  -- Allow processing time
        end procedure;
        
    begin
        report "Starting MIDI Interface Test";
        
        -- Reset sequence
        reset_n <= '0';
        wait for 100 ns;
        reset_n <= '1';
        wait for 100 ns;
        
        -- Test 1: Program Change messages for presets
        report "--- Test 1: Program Change Presets ---";
        
        send_program_change(0, 0);  -- Clean preset
        assert bitcrush_depth = x"F" and sample_decimate = x"0" 
            report "PC 0 (Clean) failed" severity error;
        
        send_program_change(0, 1);  -- Light crush preset
        assert bitcrush_depth = x"C" and sample_decimate = x"1" 
            report "PC 1 (Light crush) failed" severity error;
        
        send_program_change(0, 2);  -- Medium crush preset
        assert bitcrush_depth = x"8" and sample_decimate = x"2" 
            report "PC 2 (Medium crush) failed" severity error;
        
        send_program_change(0, 3);  -- Heavy crush preset
        assert bitcrush_depth = x"4" and sample_decimate = x"4" 
            report "PC 3 (Heavy crush) failed" severity error;
        
        send_program_change(0, 4);  -- Retro lo-fi preset
        assert bitcrush_depth = x"2" and sample_decimate = x"6" 
            report "PC 4 (Retro lo-fi) failed" severity error;
        
        -- Test 2: Control Change messages
        report "--- Test 2: Control Change Messages ---";
        
        -- CC #1 - Bitcrush Depth
        send_control_change(0, 1, 0);    -- No crushing
        assert bitcrush_depth = x"F" report "CC1 value 0 failed" severity error;
        
        send_control_change(0, 1, 64);   -- Medium crushing
        assert bitcrush_depth = x"7" report "CC1 value 64 failed" severity error;
        
        send_control_change(0, 1, 127);  -- Maximum crushing
        assert bitcrush_depth = x"0" report "CC1 value 127 failed" severity error;
        
        -- CC #2 - Sample Decimation
        send_control_change(0, 2, 0);    -- No decimation
        assert sample_decimate = x"0" report "CC2 value 0 failed" severity error;
        
        send_control_change(0, 2, 64);   -- Medium decimation
        assert sample_decimate = x"8" report "CC2 value 64 failed" severity error;
        
        send_control_change(0, 2, 127);  -- Maximum decimation
        assert sample_decimate = x"F" report "CC2 value 127 failed" severity error;
        
        -- CC #7 - Master Volume
        send_control_change(0, 7, 0);    -- Minimum volume
        assert master_volume = x"00" report "CC7 value 0 failed" severity error;
        
        send_control_change(0, 7, 64);   -- Medium volume
        assert master_volume = x"80" report "CC7 value 64 failed" severity error;
        
        send_control_change(0, 7, 127);  -- Maximum volume
        assert master_volume = x"FE" report "CC7 value 127 failed" severity error;
        
        -- Test 3: Different MIDI channels
        report "--- Test 3: MIDI Channel Handling ---";
        
        send_program_change(1, 0);  -- Channel 1
        assert midi_channel = x"1" report "MIDI channel 1 failed" severity error;
        
        send_program_change(15, 0); -- Channel 15
        assert midi_channel = x"F" report "MIDI channel 15 failed" severity error;
        
        -- Test 4: Invalid/Unknown messages
        report "--- Test 4: Unknown Message Handling ---";
        
        -- Unknown Program Change
        send_program_change(0, 99);  -- Should be ignored
        -- Parameters should remain from previous test
        
        -- Unknown Control Change
        send_control_change(0, 99, 64);  -- Should be ignored
        
        wait for 1 ms;
        
        report "MIDI Interface Test Completed Successfully";
        test_done <= true;
        wait;
    end process;
    
end architecture testbench;