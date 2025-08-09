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

    -- Clock domain crossing synchronizers
    signal param_updated_sync : std_logic_vector(2 downto 0) := (others => '0');
    signal bitcrush_depth_sync : std_logic_vector(3 downto 0) := (others => '0');
    signal sample_decimate_sync : std_logic_vector(3 downto 0) := (others => '0');
    signal master_volume_sync : std_logic_vector(7 downto 0) := (others => '0');

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

    -- DSP process
    dsp_process : process(clk_audio, reset_n)
    begin
        if reset_n = '0' then
            audio_left_processed <= (others => '0');
            audio_right_processed <= (others => '0');

        elsif rising_edge(clk_audio) then
            if audio_valid = '1' then
                -- Simple bit crushing - just mask lower bits
                case bitcrush_depth_sync is
                    when x"0" => 
                        -- 1-bit (extreme crushing) - MSB + 15 zeros
                        audio_left_processed <= audio_left_in(15) & (14 downto 0 => '0');
                        audio_right_processed <= audio_right_in(15) & (14 downto 0 => '0');
                    when x"1" | x"2" | x"3" => 
                        -- 2-4 bit crushing - top 4 bits + 12 zeros
                        audio_left_processed <= audio_left_in(15 downto 12) & (11 downto 0 => '0');
                        audio_right_processed <= audio_right_in(15 downto 12) & (11 downto 0 => '0');
                    when x"4" | x"5" | x"6" | x"7" => 
                        -- 5-8 bit crushing - top 8 bits + 8 zeros
                        audio_left_processed <= audio_left_in(15 downto 8) & (7 downto 0 => '0');
                        audio_right_processed <= audio_right_in(15 downto 8) & (7 downto 0 => '0');
                    when others => 
                        -- No crushing
                        audio_left_processed <= audio_left_in;
                        audio_right_processed <= audio_right_in;
                end case;
            end if;
        end if;
    end process;

    -- Synchronize MIDI parameters to audio clock domain
    parameter_sync_process : process(clk_audio, reset_n)
    begin
        if reset_n = '0' then
            param_updated_sync <= (others => '0');
            bitcrush_depth_sync <= (others => '0');
            sample_decimate_sync <= (others => '0');
            master_volume_sync <= (others => '0');
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

    -- Status LEDs
    led(0) <= pll_locked;                              -- PLL lock status
    led(1) <= audio_valid;                             -- Audio data valid
    led(2) <= param_updated_sync(2);                   -- MIDI parameter update sync
    led(3) <= '1' when bitcrush_depth_sync /= x"F" else '0';  -- Bit crusher active

    -- Test points for debugging
    test_point_1 <= i2s_bclk_int;
    test_point_2 <= midi_valid;     -- MIDI activity indicator

end architecture rtl;