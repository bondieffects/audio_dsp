-- Real-time Audio Digital Signal Processor
-- Top-level entity for Cyclone IV FPGA
-- Author: Group 10
-- Device: EP4CE6E22C8N

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity audio_dsp_top is
    port (
        -- System clock (50MHz)
        clk_50mhz : in std_logic;
        reset_n   : in std_logic;
        
        -- I2S Interface to WM8731 CODEC
        i2s_bclk  : out std_logic;  -- Bit clock (3.072MHz)
        i2s_lrclk : out std_logic;  -- Left/Right clock (48kHz)
        i2s_din   : in  std_logic;  -- Data from CODEC ADC
        i2s_dout  : out std_logic;  -- Data to CODEC DAC
        
        -- MIDI Interface from Arduino
        midi_rx   : in  std_logic;  -- MIDI data at 31250 baud
        
        -- Debug/Status LEDs
        led       : out std_logic_vector(3 downto 0);
        
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
    
    -- DSP control signals
    signal bitcrush_depth  : std_logic_vector(3 downto 0) := "1111"; -- Default: no crushing
    signal sample_decimate : std_logic_vector(3 downto 0) := "0000"; -- Default: no decimation
    
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
            audio_left_out  => audio_left_out,
            audio_right_out => audio_right_out,
            audio_valid     => audio_valid
        );
    
    -- Connect I2S clocks to outputs
    i2s_bclk  <= i2s_bclk_int;
    i2s_lrclk <= i2s_lrclk_int;
    
    -- Simple passthrough for now (will be replaced with DSP processing)
    audio_left_out  <= audio_left_in;
    audio_right_out <= audio_right_in;
    
    -- Status LEDs
    led(0) <= pll_locked;
    led(1) <= audio_valid;
    led(2) <= i2s_lrclk_int;
    led(3) <= not reset_n;
    
    -- Test points for debugging
    test_point_1 <= i2s_bclk_int;
    test_point_2 <= i2s_lrclk_int;
    
end architecture rtl;