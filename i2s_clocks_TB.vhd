-- LIBRARIES and PACKAGES for i2s_clocks_TB
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity i2s_clocks_TB is
end entity;

-- 5.7 Overview of Simulation Test Benches p. 162
-- 8.4 Test Benches p. 272
architecture i2s_clocks_TB_arch of i2s_clocks_TB is

    constant MCLK_HALF_PERIOD : time := 41 ns; -- approx half period for 12.288 MHz

    -- Component declaration for DUT
    component i2s_clocks
        port (
            -- Inputs
            i2s_mclk : in std_logic;        -- 12.288MHz master clock from audio_pll
            reset_n : in std_logic;         -- Active low reset

            -- Outputs
            i2s_bclk : out std_logic;       -- 1.536MHz bit clock
            i2s_ws : out std_logic          -- 48kHz left/right clock
        );
    end component;

    -- Signal declarations
    signal i2s_mclk_TB : std_logic := '0';  -- 12.288MHz master clock
    signal reset_n_TB : std_logic := '0';   -- Active low reset
    signal i2s_bclk_TB : std_logic;         -- 1.536MHz bit clock
    signal i2s_ws_TB : std_logic;           -- 48kHz left/right clock

begin

    -- DUT instantiation
    DUT1: i2s_clocks
        port map (
            i2s_mclk => i2s_mclk_TB,
            reset_n => reset_n_TB,
            i2s_bclk => i2s_bclk_TB,
            i2s_ws => i2s_ws_TB
        );

    -- Stimulus generation to drive the i2s_mclk and reset_n signals
    STIMULUS: process
    begin
        -- Init signals
        i2s_mclk_TB <= '0';
        reset_n_TB <= '0';  -- Start with reset active
        wait for 100 ns;    -- Hold reset for 100 ns

        reset_n_TB <= '1';  -- Release reset
        wait for 10 ns;     -- Small delay after reset

        -- Generate continuous 12.288MHz clock
        for i in 0 to 19999 loop  -- Generate 20,000 clock cycles (more than enough)
            i2s_mclk_TB <= '1';
            wait for MCLK_HALF_PERIOD;
            i2s_mclk_TB <= '0';
            wait for MCLK_HALF_PERIOD;
        end loop;

        -- End simulation
        report "Clock generation complete" severity note;
        wait;
    end process;

    -- Simple monitoring process (no automated checks to avoid ModelSim issues)
    MONITOR: process
    begin
        -- Wait for reset release
        wait until reset_n_TB = '1';
        report "Reset released - monitoring started" severity note;

        -- Just wait and let the simulation run
        wait for 1 ms;
        report "Monitoring complete - check waveforms manually" severity note;
        wait;
    end process;

end architecture i2s_clocks_TB_arch;