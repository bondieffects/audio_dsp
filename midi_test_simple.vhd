-- Simple MIDI Test Module
-- Displays MIDI parameters on LEDs for testing
-- Author: Based on Group 10 design

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity midi_test_simple is
    port (
        clk_50mhz : in  std_logic;
        reset_n   : in  std_logic;
        midi_rx   : in  std_logic;
        
        -- LED outputs for parameter display
        led       : out std_logic_vector(3 downto 0);
        
        -- 7-segment display for parameter values
        seg       : out std_logic_vector(6 downto 0);
        seg_sel   : out std_logic_vector(3 downto 0);
        
        -- Test points
        test_midi_valid : out std_logic;
        test_midi_error : out std_logic
    );
end entity midi_test_simple;

architecture rtl of midi_test_simple is
    
    -- MIDI signals
    signal midi_data       : std_logic_vector(7 downto 0);
    signal midi_valid      : std_logic;
    signal midi_error      : std_logic;
    
    -- Parsed MIDI parameters
    signal bitcrush_depth  : std_logic_vector(3 downto 0);
    signal sample_decimate : std_logic_vector(3 downto 0);
    signal master_volume   : std_logic_vector(7 downto 0);
    signal param_updated   : std_logic;
    signal midi_channel    : std_logic_vector(3 downto 0);
    
    -- Display signals
    signal display_counter : unsigned(25 downto 0) := (others => '0');
    signal display_mode    : unsigned(1 downto 0) := "00";
    signal current_param   : std_logic_vector(7 downto 0);
    
    -- Individual digit data signals
    signal digit_0_data : std_logic_vector(3 downto 0);  -- Rightmost - Bitcrush
    signal digit_1_data : std_logic_vector(3 downto 0);  -- Decimation  
    signal digit_2_data : std_logic_vector(3 downto 0);  -- Volume upper nibble
    signal digit_3_data : std_logic_vector(3 downto 0);  -- Leftmost - Channel
    
    -- Components
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
    
begin
    
    -- Instantiate MIDI UART receiver
    u_midi_uart : midi_uart_rx
        port map (
            clk        => clk_50mhz,
            reset_n    => reset_n,
            midi_rx    => midi_rx,
            data_out   => midi_data,
            data_valid => midi_valid,
            error      => midi_error
        );
    
    -- Instantiate MIDI parser  
    u_midi_parser : midi_parser
        port map (
            clk             => clk_50mhz,
            reset_n         => reset_n,
            midi_data       => midi_data,
            midi_valid      => midi_valid,
            bitcrush_depth  => bitcrush_depth,
            sample_decimate => sample_decimate,
            master_volume   => master_volume,
            param_updated   => param_updated,
            midi_channel    => midi_channel
        );
    
    -- Display multiplexer
    process(clk_50mhz, reset_n)
    begin
        if reset_n = '0' then
            display_counter <= (others => '0');
            display_mode <= "00";
        elsif rising_edge(clk_50mhz) then
            display_counter <= display_counter + 1;
            -- Switch digits much faster - every 2^16 clocks (~1.3ms at 50MHz)
            if display_counter(15 downto 0) = 0 then
                display_mode <= display_mode + 1;
            end if;
        end if;
    end process;
    
    -- Assign parameter data to digits
    digit_0_data <= bitcrush_depth;                    -- Bitcrush depth
    digit_1_data <= sample_decimate;                   -- Sample decimation
    digit_2_data <= master_volume(7 downto 4);         -- Master volume upper nibble
    digit_3_data <= midi_channel;                      -- MIDI channel
    
    -- Select which digit to display based on counter
    process(display_mode, digit_0_data, digit_1_data, digit_2_data, digit_3_data)
    begin
        case display_mode is
            when "00" => 
                current_param <= "0000" & digit_0_data;  -- Bitcrush depth
                seg_sel <= "1110";  -- Activate digit 0 (rightmost)
            when "01" => 
                current_param <= "0000" & digit_1_data;  -- Sample decimation  
                seg_sel <= "1101";  -- Activate digit 1
            when "10" => 
                current_param <= "0000" & digit_2_data;  -- Master volume upper nibble
                seg_sel <= "1011";  -- Activate digit 2
            when "11" => 
                current_param <= "0000" & digit_3_data;  -- MIDI channel
                seg_sel <= "0111";  -- Activate digit 3 (leftmost)
            when others =>
                current_param <= x"00";
                seg_sel <= "1111";  -- All digits off
        end case;
    end process;
    
    -- Simple 7-segment decoder (hexadecimal) - Active LOW for common anode
    process(current_param(3 downto 0))
    begin
        case current_param(3 downto 0) is
            when x"0" => seg <= "0000001";  -- 0
            when x"1" => seg <= "1001111";  -- 1
            when x"2" => seg <= "0010010";  -- 2
            when x"3" => seg <= "0000110";  -- 3
            when x"4" => seg <= "1001100";  -- 4
            when x"5" => seg <= "0100100";  -- 5
            when x"6" => seg <= "0100000";  -- 6
            when x"7" => seg <= "0001111";  -- 7
            when x"8" => seg <= "0000000";  -- 8
            when x"9" => seg <= "0000100";  -- 9
            when x"A" => seg <= "0001000";  -- A
            when x"B" => seg <= "1100000";  -- b
            when x"C" => seg <= "0110001";  -- C
            when x"D" => seg <= "1000010";  -- d
            when x"E" => seg <= "0110000";  -- E
            when x"F" => seg <= "0111000";  -- F
            when others => seg <= "1111111"; -- blank (all off)
        end case;
    end process;
    
    -- LED status indicators
    led(0) <= '1' when unsigned(bitcrush_depth) < 8 else '0';   -- Heavy crushing indicator (inverted bit depth)
    led(1) <= '1' when unsigned(sample_decimate) > 0 else '0';  -- Any decimation indicator  
    led(2) <= param_updated;                                    -- Parameter update indicator
    led(3) <= midi_error;                                       -- MIDI error indicator
    
    -- Test point outputs
    test_midi_valid <= midi_valid;
    test_midi_error <= midi_error;
    
end architecture rtl;