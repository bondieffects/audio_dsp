-- Real-time Audio Digital Signal Processor with MIDI Control
-- Top-level entity for Cyclone IV FPGA with 7-segment display
-- Author: Group 10
-- Device: EP4CE6E22C8N

-- Libraries
library IEEE;                   -- Standard library
use IEEE.std_logic_1164.all;    -- Standard logic types (0, 1, Z, X)
use IEEE.numeric_std.all;       -- Numeric types (signed, unsigned)

entity audio_dsp_top is
    -- port() specifies all external connections used by this module
    port (
        -- Main system clock (50MHz)
        clk_50mhz : in std_logic;
        reset_n   : in std_logic;   -- Active low reset

        -- I2S Interface to WM8731 CODEC
        i2s_mclk  : out std_logic;  -- Master clock (12.288MHz)
        i2s_bclk  : out std_logic;  -- Bit clock (3.072MHz)
        i2s_lrclk : out std_logic;  -- Left/Right clock (48kHz)
        i2s_din   : in  std_logic;  -- Data from CODEC ADC
        i2s_dout  : out std_logic;  -- Data to CODEC DAC

        -- MIDI Interface from Arduino
        midi_rx   : in  std_logic;  -- MIDI data at 31250 baud

        -- Debug/Status LEDs
        led       : out std_logic_vector(3 downto 0);   -- 4-bit vector

        -- 7-segment display for MIDI parameter monitoring
        seg       : out std_logic_vector(6 downto 0);   -- 7-segment segments
        seg_sel   : out std_logic_vector(3 downto 0);   -- Digit select

        -- Test points for debugging
        test_point_1 : out std_logic;
        test_point_2 : out std_logic
    );
end entity audio_dsp_top;

architecture rtl of audio_dsp_top is

    -- Clock signals
    signal clk_audio     : std_logic;  -- Audio clock domain (12.288MHz)
    signal i2s_bclk_int  : std_logic;  -- Internal BCLK
    signal i2s_lrclk_int : std_logic;  -- Internal LRCLK
    signal pll_locked    : std_logic;  -- PLL lock indicator

    -- Audio data signals
    signal audio_left_in   : std_logic_vector(15 downto 0);
    signal audio_right_in  : std_logic_vector(15 downto 0);
    signal audio_left_out  : std_logic_vector(15 downto 0);
    signal audio_right_out : std_logic_vector(15 downto 0);
    signal audio_valid     : std_logic;
    
    -- Processed audio signals
    signal audio_left_processed  : std_logic_vector(15 downto 0);
    signal audio_right_processed : std_logic_vector(15 downto 0);
    
    -- MIDI interface signals
    signal midi_data       : std_logic_vector(7 downto 0);
    signal midi_valid      : std_logic;
    signal midi_error      : std_logic;
    
    -- DSP control signals from MIDI
    signal bitcrush_depth  : std_logic_vector(3 downto 0);
    signal sample_decimate : std_logic_vector(3 downto 0);
    signal master_volume   : std_logic_vector(7 downto 0);
    signal param_updated   : std_logic;
    signal midi_channel    : std_logic_vector(3 downto 0);

    -- Clock domain crossing synchronizers
    signal param_updated_sync : std_logic_vector(2 downto 0) := (others => '0');
    signal bitcrush_depth_sync : std_logic_vector(3 downto 0) := (others => '0');
    signal sample_decimate_sync : std_logic_vector(3 downto 0) := (others => '0');
    signal master_volume_sync : std_logic_vector(7 downto 0) := (others => '0');

    -- 7-segment display signals
    signal display_counter : unsigned(15 downto 0) := (others => '0');
    signal display_mode    : unsigned(1 downto 0) := "00";
    signal current_param   : std_logic_vector(3 downto 0);
    signal digit_0_data    : std_logic_vector(3 downto 0);  -- Rightmost - Bitcrush
    signal digit_1_data    : std_logic_vector(3 downto 0);  -- Decimation  
    signal digit_2_data    : std_logic_vector(3 downto 0);  -- Volume upper nibble
    signal digit_3_data    : std_logic_vector(3 downto 0);  -- Leftmost - Channel

    -- Component declarations
    component i2s_clock_gen is
        port (
            clk_50mhz    : in  std_logic;
            reset_n      : in  std_logic;
            clk_audio    : out std_logic;
            i2s_bclk     : out std_logic;
            i2s_lrclk    : out std_logic;
            pll_locked   : out std_logic
        );
    end component;
    
    component i2s_interface is
        port (
            clk_audio      : in  std_logic;
            reset_n        : in  std_logic;
            i2s_bclk       : in  std_logic;
            i2s_lrclk      : in  std_logic;
            i2s_din        : in  std_logic;
            i2s_dout       : out std_logic;
            audio_left_in  : out std_logic_vector(15 downto 0);
            audio_right_in : out std_logic_vector(15 downto 0);
            audio_left_out : in  std_logic_vector(15 downto 0);
            audio_right_out: in  std_logic_vector(15 downto 0);
            audio_valid    : out std_logic
        );
    end component;
    
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
    
    -- Instantiate I2S clock generator
    u_i2s_clocks : i2s_clock_gen
        port map (
            clk_50mhz  => clk_50mhz,
            reset_n    => reset_n,
            clk_audio  => clk_audio,
            i2s_bclk   => i2s_bclk_int,
            i2s_lrclk  => i2s_lrclk_int,
            pll_locked => pll_locked
        );
    
    -- Instantiate I2S interface
    u_i2s_interface : i2s_interface
        port map (
            clk_audio       => clk_audio,
            reset_n         => reset_n,
            i2s_bclk        => i2s_bclk_int,
            i2s_lrclk       => i2s_lrclk_int,
            i2s_din         => i2s_din,
            i2s_dout        => i2s_dout,
            audio_left_in   => audio_left_in,
            audio_right_in  => audio_right_in,
            audio_left_out  => audio_left_processed,
            audio_right_out => audio_right_processed,
            audio_valid     => audio_valid
        );
    
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
    
    -- Connect I2S clocks to outputs
    i2s_mclk  <= clk_audio;
    i2s_bclk  <= i2s_bclk_int;
    i2s_lrclk <= i2s_lrclk_int;

    -- DSP process (enhanced with proper bit crushing and volume control)
    dsp_process : process(clk_audio, reset_n)
        variable left_temp  : signed(31 downto 0);
        variable right_temp : signed(31 downto 0);
        variable volume_mult : signed(8 downto 0);
        variable crush_shift : natural range 0 to 15;
        variable left_crushed : signed(15 downto 0);
        variable right_crushed : signed(15 downto 0);
        variable decimate_counter : unsigned(3 downto 0) := (others => '0');
        variable decimate_threshold : unsigned(3 downto 0);
        variable hold_left : signed(15 downto 0) := (others => '0');
        variable hold_right : signed(15 downto 0) := (others => '0');
        variable left_mult_temp : signed(24 downto 0);
        variable right_mult_temp : signed(24 downto 0);
    begin
        if reset_n = '0' then
            audio_left_processed <= (others => '0');
            audio_right_processed <= (others => '0');
            decimate_counter := (others => '0');
            hold_left := (others => '0');
            hold_right := (others => '0');

        elsif rising_edge(clk_audio) then
            if audio_valid = '1' then
                -- Convert inputs to signed
                left_temp := resize(signed(audio_left_in), 32);
                right_temp := resize(signed(audio_right_in), 32);
                
                -- Apply bit crushing with bounds checking
                crush_shift := to_integer(unsigned(bitcrush_depth_sync));
                if crush_shift < 16 then
                    -- Ensure we don't shift by more than available bits
                    if crush_shift > 0 then
                        -- Shift right to remove bits, then shift back
                        left_temp := shift_left(shift_right(left_temp, crush_shift), crush_shift);
                        right_temp := shift_left(shift_right(right_temp, crush_shift), crush_shift);
                    end if;
                    left_crushed := resize(left_temp, 16);
                    right_crushed := resize(right_temp, 16);
                else
                    -- Full bit depth (no crushing)
                    left_crushed := signed(audio_left_in);
                    right_crushed := signed(audio_right_in);
                end if;
                
                -- Apply sample decimation (sample and hold)
                decimate_threshold := unsigned(sample_decimate_sync);
                if decimate_counter = 0 then
                    -- Update held samples
                    hold_left := left_crushed;
                    hold_right := right_crushed;
                end if;
                
                -- Increment decimation counter
                if decimate_threshold > 0 then
                    if decimate_counter >= decimate_threshold then
                        decimate_counter := (others => '0');
                    else
                        decimate_counter := decimate_counter + 1;
                    end if;
                else
                    decimate_counter := (others => '0');
                end if;
                
                -- Apply master volume with proper bit width handling
                volume_mult := signed('0' & master_volume_sync);  -- 9-bit signed
                
                -- Perform multiplication with proper sizing
                left_mult_temp := hold_left * volume_mult;   -- 16 * 9 = 25 bits
                right_mult_temp := hold_right * volume_mult; -- 16 * 9 = 25 bits
                
                -- Scale back down (divide by 128 to maintain roughly same amplitude)
                left_temp := resize(shift_right(left_mult_temp, 7), 32);
                right_temp := resize(shift_right(right_mult_temp, 7), 32);
                
                -- Clamp to 16-bit range
                if left_temp > 32767 then
                    audio_left_processed <= std_logic_vector(to_signed(32767, 16));
                elsif left_temp < -32768 then
                    audio_left_processed <= std_logic_vector(to_signed(-32768, 16));
                else
                    audio_left_processed <= std_logic_vector(resize(left_temp, 16));
                end if;
                
                if right_temp > 32767 then
                    audio_right_processed <= std_logic_vector(to_signed(32767, 16));
                elsif right_temp < -32768 then
                    audio_right_processed <= std_logic_vector(to_signed(-32768, 16));
                else
                    audio_right_processed <= std_logic_vector(resize(right_temp, 16));
                end if;
            end if;
        end if;
    end process;

    -- Synchronize MIDI parameters to audio clock domain
    parameter_sync_process : process(clk_audio, reset_n)
    begin
        if reset_n = '0' then
            param_updated_sync <= (others => '0');
            bitcrush_depth_sync <= x"F";  -- Default: no crushing
            sample_decimate_sync <= x"0"; -- Default: no decimation
            master_volume_sync <= x"7F";  -- Default: mid volume
        elsif rising_edge(clk_audio) then
            -- 3-stage synchronizer for parameter updates
            param_updated_sync <= param_updated_sync(1 downto 0) & param_updated;

            -- Latch parameters when update is detected
            if param_updated_sync(2) = '1' and param_updated_sync(1) = '0' then
                bitcrush_depth_sync <= bitcrush_depth;
                sample_decimate_sync <= sample_decimate;
                master_volume_sync <= master_volume;
            end if;
        end if;
    end process;

    -- 7-segment display multiplexing counter (fast switching for persistence of vision)
    display_counter_process : process(clk_50mhz, reset_n)
    begin
        if reset_n = '0' then
            display_counter <= (others => '0');
            display_mode <= "00";
        elsif rising_edge(clk_50mhz) then
            display_counter <= display_counter + 1;
            -- Switch digits every 2^16 clocks (~1.3ms at 50MHz) for persistence of vision
            if display_counter = 0 then
                display_mode <= display_mode + 1;
            end if;
        end if;
    end process;

    -- Assign parameter data to display digits
    digit_0_data <= bitcrush_depth;                -- Rightmost: Bitcrush depth
    digit_1_data <= sample_decimate;               -- Decimation factor
    digit_2_data <= master_volume(7 downto 4);     -- Volume upper nibble
    digit_3_data <= midi_channel;                  -- Leftmost: MIDI channel

    -- Select which digit to display based on multiplexing counter
    display_mux_process : process(display_mode, digit_0_data, digit_1_data, digit_2_data, digit_3_data)
    begin
        case display_mode is
            when "00" => 
                current_param <= digit_0_data;  -- Bitcrush depth
                seg_sel <= "1110";  -- Activate digit 0 (rightmost)
            when "01" => 
                current_param <= digit_1_data;  -- Sample decimation  
                seg_sel <= "1101";  -- Activate digit 1
            when "10" => 
                current_param <= digit_2_data;  -- Master volume upper nibble
                seg_sel <= "1011";  -- Activate digit 2
            when "11" => 
                current_param <= digit_3_data;  -- MIDI channel
                seg_sel <= "0111";  -- Activate digit 3 (leftmost)
            when others =>
                current_param <= x"0";
                seg_sel <= "1111";  -- All digits off
        end case;
    end process;

    -- 7-segment decoder (hexadecimal) - Active LOW for common anode displays
    seg_decoder_process : process(current_param)
    begin
        case current_param is
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

    -- Status LEDs (enhanced)
    led(0) <= pll_locked;                                      -- PLL lock status
    led(1) <= audio_valid;                                     -- Audio data valid
    led(2) <= param_updated;                                   -- MIDI parameter update
    led(3) <= '1' when unsigned(bitcrush_depth) < 12 else '0'; -- Active crushing indicator

    -- Test points for debugging
    test_point_1 <= i2s_bclk_int;    -- I2S bit clock
    test_point_2 <= midi_valid;      -- MIDI activity indicator

end architecture rtl;