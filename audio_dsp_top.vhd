-- Simple I2S Pass-Through System
-- Top-level entity for Cyclone IV FPGA
-- Author: Group 10: Jon Ashley, Alix Guo, Finn Harvey
-- Device: EP4CE6E22C8

-- Libraries
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity audio_dsp_top is
    port (
        -- System clock (50MHz)
        clk_50mhz : in std_logic;
        reset_n   : in std_logic;   -- Active low reset

        -- I2S Interface to WM8731 CODEC (using correct pin names)
        i2s_mclk  : out std_logic;  -- Master clock (12.288MHz) - PIN_30
        i2s_bclk  : out std_logic;  -- Bit clock (1.536MHz) - PIN_31
        i2s_ws : out std_logic;  -- Left/Right clock (48kHz) - PIN_32  
        i2s_din   : in  std_logic;  -- Data from CODEC ADC - PIN_33
        i2s_dout  : out std_logic;  -- Data to CODEC DAC - PIN_34

        -- Debug/Status LEDs
        led       : out std_logic_vector(3 downto 0);   -- PIN_84 to 87

        -- Test points for debugging
        test_point_1 : out std_logic; -- PIN_50
        test_point_2 : out std_logic  -- PIN_51
    );
end entity audio_dsp_top;

architecture rtl of audio_dsp_top is

    -- ========================================================================
    -- COMPONENT DECLARATIONS
    -- ========================================================================
    
    component audio_pll is
        port (
            areset  : in  std_logic := '0';
            inclk0  : in  std_logic := '0';
            c0      : out std_logic;
            locked  : out std_logic
        );
    end component;
    
    component i2s is
        port (
            i2s_mclk : in std_logic;
            reset_n : in std_logic;
            i2s_bclk : out std_logic;
            i2s_ws : out std_logic;
            i2s_dac : out std_logic;
            i2s_adc : in std_logic;
            audio_out_left : in std_logic_vector(15 downto 0);
            audio_out_right : in std_logic_vector(15 downto 0);
            audio_out_valid : in std_logic;
            sample_request : out std_logic;
            audio_in_left : out std_logic_vector(15 downto 0);
            audio_in_right : out std_logic_vector(15 downto 0);
            audio_in_valid : out std_logic
        );
    end component;
    
    component audio_dsp_processor is
        port (
            clk_audio       : in  std_logic;
            reset_n         : in  std_logic;
            audio_in_left   : in  std_logic_vector(15 downto 0);
            audio_in_right  : in  std_logic_vector(15 downto 0);
            audio_in_valid  : in  std_logic;
            audio_out_left  : out std_logic_vector(15 downto 0);
            audio_out_right : out std_logic_vector(15 downto 0);
            audio_out_valid : out std_logic;
            effect_enable   : in  std_logic;
            effect_select   : in  std_logic_vector(2 downto 0);
            effect_param    : in  std_logic_vector(7 downto 0)
        );
    end component;

    -- ========================================================================
    -- INTERNAL SIGNALS
    -- ========================================================================

    -- PLL signals
    signal clk_audio     : std_logic;  -- 12.288MHz from PLL
    signal pll_locked    : std_logic;  -- PLL lock status
    signal pll_reset     : std_logic;  -- PLL reset (active high)
    signal i2s_reset     : std_logic;  -- I2S reset (active low, gated by PLL lock)

    -- Internal I2S clock signals
    signal i2s_bclk_int  : std_logic;
    signal i2s_ws_int    : std_logic;

    -- Audio data flow signals
    signal audio_in_left   : std_logic_vector(15 downto 0);
    signal audio_in_right  : std_logic_vector(15 downto 0);
    signal audio_in_valid  : std_logic;
    signal sample_request  : std_logic;

    -- DSP processed signals 
    signal dsp_out_left    : std_logic_vector(15 downto 0);
    signal dsp_out_right   : std_logic_vector(15 downto 0);
    signal dsp_out_valid   : std_logic;

    -- DSP control signals (can be controlled by switches/buttons later)
    signal effect_enable   : std_logic := '1';  -- Enable effects by default
    signal effect_select   : std_logic_vector(2 downto 0) := "001";  -- Default to gain
    signal effect_param    : std_logic_vector(7 downto 0) := x"80";  -- Default parameter

    -- Audio buffering signals (kept for future use)
    signal audio_buffer_left   : std_logic_vector(15 downto 0);
    signal audio_buffer_right  : std_logic_vector(15 downto 0);
    signal buffer_valid        : std_logic;


begin

    -- ========================================================================
    -- RESET LOGIC
    -- ========================================================================
    pll_reset <= not reset_n;                    -- PLL needs active high reset
    i2s_reset <= reset_n and pll_locked;         -- I2S starts only after PLL locks

    -- ========================================================================
    -- PLL INSTANTIATION
    -- ========================================================================
    u_audio_pll : audio_pll
        port map (
            areset => pll_reset,
            inclk0 => clk_50mhz,
            c0     => clk_audio,
            locked => pll_locked
        );

    -- ========================================================================
    -- DSP PROCESSOR INSTANTIATION
    -- ========================================================================
    u_dsp_processor : audio_dsp_processor
        port map (
            clk_audio       => clk_audio,
            reset_n         => i2s_reset,
            audio_in_left   => audio_in_left,
            audio_in_right  => audio_in_right,
            audio_in_valid  => audio_in_valid,
            audio_out_left  => dsp_out_left,
            audio_out_right => dsp_out_right,
            audio_out_valid => dsp_out_valid,
            effect_enable   => effect_enable,
            effect_select   => effect_select,
            effect_param    => effect_param
        );

    -- ========================================================================
    -- I2S INTERFACE INSTANTIATION
    -- ========================================================================
    u_i2s : i2s
        port map (
            i2s_mclk        => clk_audio,
            reset_n         => i2s_reset,
            i2s_bclk        => i2s_bclk_int,
            i2s_ws          => i2s_ws_int,
            i2s_dac         => i2s_dout,
            i2s_adc         => i2s_din,
            audio_out_left  => audio_in_left,      -- DIRECT BYPASS - Skip DSP for testing
            audio_out_right => audio_in_right,     -- DIRECT BYPASS - Skip DSP for testing  
            audio_out_valid => audio_in_valid,     -- DIRECT BYPASS - Skip DSP for testing
            sample_request  => sample_request,
            audio_in_left   => audio_in_left,       -- Raw audio FROM codec
            audio_in_right  => audio_in_right,      -- Raw audio FROM codec
            audio_in_valid  => audio_in_valid
        );

    -- ========================================================================
    -- OUTPUT ASSIGNMENTS
    -- ========================================================================
    
    -- I2S clock outputs (connect internal signals to external pins)
    i2s_mclk  <= clk_audio;        -- Send 12.288MHz master clock to CODEC
    i2s_bclk  <= i2s_bclk_int;     -- Send 1.536MHz bit clock to CODEC
    i2s_ws <= i2s_ws_int;       -- Send 48kHz word select to CODEC (corrected name)
    
    -- Status LEDs (inverted for active-low LEDs)
    led(0) <= not pll_locked;          -- PLL lock indicator (inverted)
    led(1) <= not audio_in_valid;      -- Audio input activity (inverted)
    led(2) <= not sample_request;      -- Sample rate indicator (inverted)
    led(3) <= not i2s_reset;           -- I2S system active (inverted)
    
    -- Test points for debugging
    test_point_1 <= pll_locked;       -- Check PLL lock status directly
    test_point_2 <= i2s_reset;        -- Check I2S reset status directly

end architecture rtl;