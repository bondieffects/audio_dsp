-- ============================================================================
-- ENTITY
-- ============================================================================
-- The entity is a description of the system's INPUTS and OUTPUTS
--      Example:
--          entity entity_name is
--              port (port_name : <mode> <type>;
--              port_name : <mode> <type>);
--          end entity;
-- ============================================================================
--
-- ============================================================================
-- ARCHITECTURE
-- ============================================================================
-- The architecture is a description of the system's BEHAVIOUR
--
--      Example:
--          architecture architecture_name of <entity associated with> is
--              user-defined enumerated type declarations (optional)
--              signal declarations (optional)
--              constant declarations (optional)
--              component declarations (optional)
--              begin
--                  behavioral description of the system goes here
--          end architecture;
-- ============================================================================

-- ========================================================================
-- 5. TOP-LEVEL I2S INTERFACE
-- ========================================================================
-- Integrate clock generator, transmitter and receiver

-- LIBRARIES and PACKAGES for i2s
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;


entity i2s is 
    port (
        -- System interface
        i2s_mclk : in std_logic;
        reset_n : in std_logic;

        -- I2S external signals
        i2s_bclk : out std_logic;       -- Bit clock
        i2s_ws : out std_logic;         -- Word select
        i2s_dac : out std_logic;       -- Serial data to DAC
        i2s_adc : in std_logic;        -- Serial data from ADC

        -- Internal Parallel Audio Busses
        -- Playback Path (FPGA -> CODEC)
        audio_out_left : in std_logic_vector(15 downto 0);      -- Left channel audio output
        audio_out_right : in std_logic_vector(15 downto 0);     -- Right channel audio output
        audio_out_valid : in std_logic;                         -- Output valid signal
        sample_request : out std_logic;                         -- Sample request signal

        -- Record Path (CODEC->FPGA)
        audio_in_left : out std_logic_vector(15 downto 0);      -- Left channel audio input
        audio_in_right : out std_logic_vector(15 downto 0);     -- Right channel audio input
        audio_in_valid : out std_logic                          -- Input valid signal
    );
end entity i2s;

architecture rtl of i2s is

    -- Internal I2S clocks
    signal bclk_signal : std_logic;
    signal ws_signal : std_logic;

begin

    -- ========================================================================
    -- INSTANTIATE CLOCK GENERATOR
    -- ========================================================================
    u_clock_gen : entity work.i2s_clocks
        port map (
            i2s_mclk => i2s_mclk,
            reset_n => reset_n,
            i2s_bclk => bclk_signal,
            i2s_ws => ws_signal
        );

    -- ========================================================================
    -- INSTANTIATE TRANSMITTER (PLAYBACK)
    -- ========================================================================
    u_tx : entity work.i2s_tx
        port map (
            i2s_bclk => bclk_signal,
            i2s_ws => ws_signal,
            reset_n => reset_n,
            audio_left => audio_out_left,
            audio_right => audio_out_right,
            tx_ready => audio_out_valid,
            i2s_sdata => i2s_dac,
            sample_request => sample_request
        );

    -- ========================================================================
    -- INSTANTIATE RECEIVER (RECORD)
    -- ========================================================================
    u_rx : entity work.i2s_rx
        port map (
            i2s_bclk => bclk_signal,
            i2s_ws => ws_signal,
            reset_n => reset_n,
            i2s_sdata => i2s_adc,
            audio_left => audio_in_left,
            audio_right => audio_in_right,
            rx_ready => audio_in_valid
        );

    -- ========================================================================
    -- CONNECT SIGNALS TO OUTPUTS
    -- ========================================================================
    i2s_bclk <= bclk_signal;       -- Connect internal BCLK to output
    i2s_ws <= ws_signal;         -- Connect internal WS to output

end architecture rtl;