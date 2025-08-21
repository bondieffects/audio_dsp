-- ============================================================================
-- DSP CONTROL EXAMPLE
-- ============================================================================
-- This file shows how you can control the DSP effects
-- You can integrate this into your main design or use it as reference

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity dsp_control_example is
    port (
        clk_50mhz     : in  std_logic;
        reset_n       : in  std_logic;
        
        -- Example: Use switches/buttons on your development board
        sw_effect_enable : in  std_logic;                      -- Switch to enable/disable effects
        sw_effect_select : in  std_logic_vector(2 downto 0);   -- 3 switches for effect selection
        btn_param_up     : in  std_logic;                      -- Button to increase parameter
        btn_param_down   : in  std_logic;                      -- Button to decrease parameter
        
        -- Outputs to DSP processor
        effect_enable : out std_logic;
        effect_select : out std_logic_vector(2 downto 0);
        effect_param  : out std_logic_vector(7 downto 0);
        
        -- Debug outputs
        param_display : out std_logic_vector(7 downto 0)  -- For 7-segment display or LEDs
    );
end entity dsp_control_example;

architecture rtl of dsp_control_example is

    signal param_counter    : unsigned(7 downto 0) := x"80";  -- Start at middle value
    signal btn_up_prev      : std_logic := '0';
    signal btn_down_prev    : std_logic := '0';
    signal btn_up_edge      : std_logic;
    signal btn_down_edge    : std_logic;

begin

    -- ========================================================================
    -- BUTTON EDGE DETECTION
    -- ========================================================================
    process(clk_50mhz, reset_n)
    begin
        if reset_n = '0' then
            btn_up_prev   <= '0';
            btn_down_prev <= '0';
            btn_up_edge   <= '0';
            btn_down_edge <= '0';
        elsif rising_edge(clk_50mhz) then
            btn_up_prev   <= btn_param_up;
            btn_down_prev <= btn_param_down;
            btn_up_edge   <= btn_param_up and not btn_up_prev;
            btn_down_edge <= btn_param_down and not btn_down_prev;
        end if;
    end process;

    -- ========================================================================
    -- PARAMETER CONTROL
    -- ========================================================================
    process(clk_50mhz, reset_n)
    begin
        if reset_n = '0' then
            param_counter <= x"80";  -- Reset to middle value
        elsif rising_edge(clk_50mhz) then
            if btn_up_edge = '1' and param_counter < 255 then
                param_counter <= param_counter + 16;  -- Increment by 16 for noticeable change
            elsif btn_down_edge = '1' and param_counter > 0 then
                param_counter <= param_counter - 16;  -- Decrement by 16
            end if;
        end if;
    end process;

    -- ========================================================================
    -- OUTPUT ASSIGNMENTS
    -- ========================================================================
    effect_enable <= sw_effect_enable;
    effect_select <= sw_effect_select;
    effect_param  <= std_logic_vector(param_counter);
    param_display <= std_logic_vector(param_counter);

end architecture rtl;

-- ============================================================================
-- EFFECT DESCRIPTIONS AND PARAMETER MEANINGS
-- ============================================================================
--
-- EFFECT_PASSTHROUGH (000): No processing, direct pass-through
--   - effect_param: Not used
--
-- EFFECT_GAIN (001): Volume control
--   - effect_param: Gain multiplier (0x00=silent, 0x80=normal, 0xFF=2x gain)
--   - Values > 0x80 will amplify, < 0x80 will attenuate
--
-- EFFECT_DELAY (010): Echo/delay effect
--   - effect_param: Delay in samples (0-255 samples)
--   - At 48kHz: 48 samples = 1ms, 240 samples = 5ms
--
-- EFFECT_LOWPASS (011): Low-pass filter (removes high frequencies)
--   - effect_param: Filter coefficient (0x00=very slow, 0xFF=very fast)
--   - Lower values = more filtering, higher values = less filtering
--
-- EFFECT_HIGHPASS (100): High-pass filter (removes low frequencies) - TO BE IMPLEMENTED
--   - effect_param: Filter coefficient
--
-- ============================================================================
-- RECOMMENDED TESTING PROCEDURE
-- ============================================================================
--
-- 1. Start with EFFECT_PASSTHROUGH (000) to verify audio still works
-- 2. Test EFFECT_GAIN (001):
--    - Try effect_param = 0x40 (quiet)
--    - Try effect_param = 0x80 (normal) 
--    - Try effect_param = 0xC0 (loud)
-- 3. Test EFFECT_DELAY (010):
--    - Try effect_param = 0x30 (48 samples ≈ 1ms)
--    - Try effect_param = 0x60 (96 samples ≈ 2ms)
-- 4. Test EFFECT_LOWPASS (011):
--    - Try effect_param = 0x20 (heavy filtering)
--    - Try effect_param = 0x80 (moderate filtering)
--    - Try effect_param = 0xE0 (light filtering)
--
-- ============================================================================
