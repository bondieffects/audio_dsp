-- ============================================================================
-- 1. I2S Clock Generator
-- ============================================================================
-- The I2S master must generate the I2S clocks:
--   - I2S Master Clock (MCLK)      12.288MHz from audio_pll (generated IP)
--   - I2S Bit Clock (BCLK)         1.536MHz (MCLK/8 = 32 × 48kHz for 16-bit stereo)
--   - I2S Word Select (WS)         48kHz (BCLK/32)

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
    signal ws_counter : unsigned(4 downto 0) := "00000";    -- For WS generation (count 32 BCLK cycles)

    -- OUTPUT CLOCK SIGNALS
    signal bclk_signal : std_logic := '0';
    
    -- BCLK edge detection for WS counting
    signal bclk_prev : std_logic := '0';
    signal bclk_edge : std_logic := '0';

begin

    -- ========================================================================
    -- BCLK GENERATION: Divide 12.288MHz by 8 to get 1.536MHz
    -- ========================================================================
    process (i2s_mclk, reset_n)
    begin
        if reset_n = '0' then
            bclk_counter <= "000";
            bclk_signal <= '0';
        elsif rising_edge(i2s_mclk) then
            if bclk_counter = "011" then  -- Count 0,1,2,3
                bclk_signal <= not bclk_signal;
                bclk_counter <= "000";
            else
                bclk_counter <= bclk_counter + 1;
            end if;
        end if;
    end process;

    -- ========================================================================
    -- BCLK EDGE DETECTION
    -- ========================================================================
    process (i2s_mclk, reset_n)
    begin
        if reset_n = '0' then
            bclk_prev <= '0';
            bclk_edge <= '0';
        elsif rising_edge(i2s_mclk) then
            bclk_prev <= bclk_signal;
            -- Detect rising edge of BCLK
            bclk_edge <= bclk_signal and not bclk_prev;
        end if;
    end process;

    -- ========================================================================
    -- WS GENERATION: Count 32 BCLK cycles to get 48kHz
    -- ========================================================================
    -- For 16-bit I2S: 16 BCLK cycles per channel, 32 total per sample period
    -- WS = 0 for left channel (counts 0-15), WS = 1 for right channel (counts 16-31)
    process (i2s_mclk, reset_n)
    begin
        if reset_n = '0' then
            ws_counter <= "00000";
        elsif rising_edge(i2s_mclk) then
            if bclk_edge = '1' then  -- Count on BCLK rising edges
                ws_counter <= ws_counter + 1;
                -- Counter automatically wraps from 31 back to 0 (5-bit counter)
            end if;
        end if;
    end process;

    -- ========================================================================
    -- CONNECT SIGNALS TO OUTPUTS
    -- ========================================================================
    i2s_bclk <= bclk_signal;
    i2s_ws <= ws_counter(4);

end architecture rtl;