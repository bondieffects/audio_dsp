-- Real-time Audio Digital Signal Processor with MIDI Control
-- Top-level entity for Cyclone IV FPGA
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
        led       : out std_logic_vector(3 downto 0);   -- 4-bit vector.

        -- Test points for debugging
        test_point_1 : out std_logic;
        test_point_2 : out std_logic
    );
end entity audio_dsp_top;

-- TODO: review and add comments from here down
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
    i2s_mclk  <= clk_audio;      -- NEW: Master clock output
    i2s_bclk  <= i2s_bclk_int;
    i2s_lrclk <= i2s_lrclk_int;
    
    -- DSP Processing (Fixed version)
    dsp_process : process(clk_audio, reset_n)
        variable left_temp  : signed(31 downto 0);
        variable right_temp : signed(31 downto 0);
        variable volume_mult : signed(8 downto 0);  -- Changed to signed and made 9 bits
        
        -- Bit crushing variables
        variable crush_shift : natural range 0 to 15;
        variable left_crushed : signed(15 downto 0);
        variable right_crushed : signed(15 downto 0);
        
        -- Sample decimation variables
        variable decimate_counter : unsigned(3 downto 0) := (others => '0');
        variable decimate_threshold : unsigned(3 downto 0);
        variable hold_left : signed(15 downto 0) := (others => '0');
        variable hold_right : signed(15 downto 0) := (others => '0');
        
        -- Temporary variables for safer arithmetic
        variable left_mult_temp : signed(24 downto 0);  -- 16 + 9 = 25 bits max
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
                crush_shift := to_integer(unsigned(bitcrush_depth));
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
                decimate_threshold := unsigned(sample_decimate);
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
                volume_mult := signed('0' & master_volume);  -- 9-bit signed
                
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
    
    -- Status LEDs
    led(0) <= pll_locked;           -- PLL lock status
    led(1) <= audio_valid;          -- Audio data valid
    led(2) <= param_updated;        -- MIDI parameter update
    led(3) <= midi_error;           -- MIDI error indicator
    
    -- Test points for debugging
    test_point_1 <= i2s_bclk_int;
    test_point_2 <= midi_valid;     -- MIDI activity indicator
    
end architecture rtl;