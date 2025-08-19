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

        -- I2S Interface to WM8731 CODEC
        i2s_mclk  : out std_logic;  -- Master clock (12.288MHz) - PIN_30
        i2s_bclk  : out std_logic;  -- Bit clock (1.536MHz) - PIN_31
        i2s_ws    : out std_logic;  -- Word select (48kHz) - PIN_32
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
    
    -- Your existing audio_pll component
    component audio_pll is
        port (
            areset  : in  std_logic := '0';
            inclk0  : in  std_logic := '0';
            c0      : out std_logic;
            locked  : out std_logic
        );
    end component;
    
    -- Your existing i2s component
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

    -- ========================================================================
    -- INTERNAL SIGNALS
    -- ========================================================================
    
    -- PLL signals
    signal i2s_mclk_int  : std_logic;  -- 12.288MHz from PLL
    signal pll_locked    : std_logic;  -- PLL lock status
    signal pll_reset     : std_logic;  -- PLL reset (active high)
    signal i2s_reset     : std_logic;  -- I2S reset (active low, gated by PLL lock)
    
    -- Internal I2S signals (avoid confusion with external pins)
    signal i2s_bclk_int    : std_logic;
    signal i2s_ws_int      : std_logic;
    signal sample_request  : std_logic;
    signal audio_in_left   : std_logic_vector(15 downto 0);
    signal audio_in_right  : std_logic_vector(15 downto 0);
    signal audio_in_valid  : std_logic;
    
    -- Simple pass-through - input directly connects to output
    signal audio_out_valid : std_logic := '1';  -- Always valid

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
            c0     => i2s_mclk_int,
            locked => pll_locked
        );

    -- ========================================================================
    -- I2S INTERFACE INSTANTIATION
    -- ========================================================================
    u_i2s : i2s
        port map (
            i2s_mclk        => i2s_mclk_int,
            reset_n         => i2s_reset,
            i2s_bclk        => i2s_bclk_int,      -- Internal signal
            i2s_ws          => i2s_ws_int,        -- Internal signal
            i2s_dac         => i2s_dout,
            i2s_adc         => i2s_din,
            audio_out_left  => audio_in_left,    -- PASS-THROUGH: Input -> Output
            audio_out_right => audio_in_right,   -- PASS-THROUGH: Input -> Output
            audio_out_valid => audio_out_valid,
            sample_request  => sample_request,
            audio_in_left   => audio_in_left,
            audio_in_right  => audio_in_right,
            audio_in_valid  => audio_in_valid
        );

    -- ========================================================================
    -- OUTPUT ASSIGNMENTS
    -- ========================================================================
    
    -- I2S clock outputs (connect internal signals to external pins)
    i2s_mclk <= i2s_mclk_int;     -- Send 12.288MHz master clock to CODEC
    i2s_bclk <= i2s_bclk_int;     -- Send 1.536MHz bit clock to CODEC
    i2s_ws   <= i2s_ws_int;       -- Send 48kHz word select to CODEC
    
    -- Status LEDs
    led(0) <= pll_locked;         -- PLL lock indicator
    led(1) <= audio_in_valid;     -- Audio input activity
    led(2) <= sample_request;     -- Sample rate indicator (will blink at 48kHz)
    led(3) <= i2s_reset;          -- I2S system active
    
    -- Test points for debugging
    test_point_1 <= i2s_bclk_int;  -- Bit clock for scope measurement (1.536MHz)
    test_point_2 <= sample_request; -- Sample rate timing (48kHz)

end architecture rtl;