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
    signal bclk_counter : unsigned(2 downto 0) := "000";    -- 3-bit counter for BCLK generation (counts 0-3, then resets)
    signal ws_counter : unsigned(7 downto 0) := "00000000"; -- 8-bit counter for WS generation (counts 0-255, wraps naturally)

    -- OUTPUT CLOCK SIGNALS
    signal bclk_signal : std_logic := '0';
    signal ws_signal : std_logic := '0';
    
    -- BCLK EDGE DETECTION SIGNALS
    signal bclk_prev : std_logic := '0';                    -- Previous BCLK state (for edge detection)
    signal bclk_edge : std_logic := '0';                    -- Single-cycle pulse on BCLK rising edge

begin

    -- ========================================================================
    -- BCLK GENERATION: Divide 12.288MHz by 8 to get 1.536MHz
    -- ========================================================================
    -- Toggles BCLK every 4 MCLK cycles to create 50% duty cycle
    -- Full BCLK period = 8 MCLK cycles (4 high, 4 low)
    process (i2s_mclk, reset_n)
    begin
        if reset_n = '0' then
            bclk_counter <= "000";
            bclk_signal <= '0';
        elsif rising_edge(i2s_mclk) then
            if bclk_counter = "011" then        -- When counter reaches 3
                bclk_signal <= not bclk_signal; -- Toggle BCLK
                bclk_counter <= "000";          -- Reset counter to 0
            else
                bclk_counter <= bclk_counter + 1;
            end if;
        end if;
    end process;

    -- ========================================================================
    -- BCLK EDGE DETECTION
    -- ========================================================================
    -- Detects rising edges of BCLK to synchronize WS counter
    -- Creates a single MCLK-cycle pulse when BCLK transitions from 0 to 1
    process (i2s_mclk, reset_n)
    begin
        if reset_n = '0' then
            bclk_prev <= '0';
            bclk_edge <= '0';
        elsif rising_edge(i2s_mclk) then
            bclk_prev <= bclk_signal;                       -- Capture current BCLK state
            bclk_edge <= bclk_signal and not bclk_prev;     -- Detect rising edge (0->1 transition)
        end if;
    end process;

    -- ========================================================================
    -- WS GENERATION: Count 32 BCLK cycles to get 48kHz
    -- ========================================================================
    -- Counter increments on BCLK rising edges (every 8 MCLK cycles)
    -- WS signal derived from bit 4, creating 32 BCLK cycle period:
    --   - WS = 0 for left channel  (counter bits 0-15)
    --   - WS = 1 for right channel (counter bits 16-31)
    -- Counter wraps naturally from 255 back to 0 (uses only lower 5 bits for WS)
    process (i2s_mclk, reset_n)
    begin
        if reset_n = '0' then
            ws_counter <= "00000000";
            ws_signal <= '0';
        elsif rising_edge(i2s_mclk) then
            if bclk_edge = '1' then                 -- Increment on BCLK rising edges
                ws_counter <= ws_counter + 1;       -- Natural wraparound at 255->0
            end if;
            ws_signal <= ws_counter(4);             -- Bit 4 toggles every 16 BCLK cycles
        end if;
    end process;

    -- ========================================================================
    -- CONNECT SIGNALS TO OUTPUTS
    -- ========================================================================
    i2s_bclk <= bclk_signal;
    i2s_ws <= ws_signal;

end architecture rtl;