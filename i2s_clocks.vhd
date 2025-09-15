-- ============================================================================
-- 1. I2S Clock Generator
-- ============================================================================
-- The I2S master must generate the I2S clocks:
--   - I2S Master Clock (MCLK)      12.288MHz from audio_pll (generated IP)
--   - I2S Bit Clock (BCLK)         1.536MHz (MCLK/8 for 16-bit stereo)
--   - I2S Word Select (WS)         48kHz (MCLK/256)

-- LIBRARIES and PACKAGES for i2s_clocks
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;


entity i2s_clocks is 
    port (
        -- Inputs
        i2s_mclk : in std_logic;        -- 12.288MHz master clock from audio_pll
        reset_n : in std_logic;         -- Active low reset

        -- Outputs
        i2s_bclk : out std_logic;       -- 1.536MHz bit clock
        i2s_ws : out std_logic          -- 48kHz left/right clock
    );
end entity i2s_clocks;

-- Register-Transfer Level (RTL) describes how data flows between
-- registers (storage elements like flip-flops) and the
-- operations (combinational logic) performed on that data between clock edges.
architecture rtl of i2s_clocks is

    -- CLOCK DIVISION SIGNALS
    signal bclk_counter : unsigned(2 downto 0) := "000";    -- For BCLK generation (divide by 8)
    signal ws_counter : unsigned(7 downto 0) := "00000000"; -- For WS generation (divide by 256)

    -- OUTPUT CLOCK SIGNALS
    signal bclk_signal : std_logic := '0';
    signal ws_signal : std_logic := '0';

begin

    -- ========================================================================
    -- BCLK GENERATION: Divide 12.288MHz by 8 to get 1.536MHz
    -- ========================================================================
    process (i2s_mclk, reset_n)
    begin
        if reset_n = '0' then
            bclk_counter <= "000";
            bclk_signal <= '0';                 -- Start with BCLK low
        elsif rising_edge(i2s_mclk) then
            bclk_counter <= bclk_counter + 1;
            bclk_signal <= bclk_counter(2);     -- When we get to bit 2, toggle BCLK high
        end if;
    end process;

    -- ========================================================================
    -- WS GENERATION: Divide 12.288MHz by 256 to get 48kHz
    -- ========================================================================
    -- WS = 0 for left channel (counts 0-127), WS = 1 for right channel (counts 128-255)
    process (i2s_mclk, reset_n)
    begin
        if reset_n = '0' then
            ws_counter <= "00000000";
            ws_signal <= '0';             -- Start with left channel (WS=0)
        elsif rising_edge(i2s_mclk) then
            ws_counter <= ws_counter + 1; -- increment counter
            ws_signal <= ws_counter(7);   -- when we get to bit 7, switch to right channel (WS=1)
        end if;
    end process;

    -- ========================================================================
    -- CONNECT SIGNALS TO OUTPUTS
    -- ========================================================================
    i2s_bclk <= bclk_signal;
    i2s_ws <= ws_signal;

end architecture rtl;