library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- ============================================================================
-- 2. I2S SERIAL TRANSMITTER (DAC DATA)
-- ============================================================================
-- Converts parallel 16-bit audio samples to serial I2S format for DAC transmission
-- Implements Philips I2S standard with:
--   - MSB-first transmission in two's complement format
--   - WS low = left channel, WS high = right channel
--   - Data transitions on falling edge of BCLK (sampled by DAC on rising edge)
--   - One BCLK period delay after WS transition (required setup time)

entity i2s_tx is
    port (
        -- Clocks and Reset
        i2s_bclk : in std_logic;
        i2s_ws   : in std_logic;
        reset_n  : in std_logic;

        -- Parallel audio data inputs (16-bit samples)
        audio_left  : in std_logic_vector(15 downto 0);
        audio_right : in std_logic_vector(15 downto 0);
        tx_ready : in std_logic;

        -- I2S Serial Data Output
        i2s_sdata : out std_logic;
        sample_request : out std_logic
    );
end entity i2s_tx;

architecture rtl of i2s_tx is
    -- WS EDGE DETECTION
    signal ws_prev : std_logic := '0';                          -- Previous WS state for edge detection
    signal request_sample : std_logic := '0';                   -- Single-cycle pulse to request new samples

    -- AUDIO DATA REGISTERS
    signal left_data_reg : std_logic_vector(15 downto 0) := (others => '0');    -- Latched left channel data
    signal right_data_reg : std_logic_vector(15 downto 0) := (others => '0');   -- Latched right channel data

begin
    -- ============================================================================
    -- I2S TRANSMITTER PROCESS
    -- ============================================================================
    -- Operates on BCLK falling edge to ensure data is stable for DAC rising edge sampling
    -- Uses bit-indexing (not shift register) to serialize 16-bit parallel data
    -- BCLK counter tracks position within each 16-bit transmission frame
    process(i2s_bclk, reset_n)
        variable bclk_count : integer range 0 to 16 := 0;       -- Bit position counter
        variable tx_data : std_logic_vector(15 downto 0);       -- Active transmission data
    begin
        if reset_n = '0' then
            -- Reset all signals
            i2s_sdata <= '0';
            ws_prev <= '0';
            request_sample <= '0';
            left_data_reg <= (others => '0');
            right_data_reg <= (others => '0');
            bclk_count := 0;
            tx_data := (others => '0');

        elsif falling_edge(i2s_bclk) then
            -- Default: clear sample request (creates single-cycle pulse)
            request_sample <= '0';

            -- ================================================================
            -- SAMPLE REQUEST AND CAPTURE
            -- ================================================================
            -- Detect WS falling edge (1->0 transition marks start of left channel)
            if ws_prev = '1' and i2s_ws = '0' then
                request_sample <= '1';                              -- Request new sample pair
                if tx_ready = '1' then                              -- If data is ready
                    left_data_reg <= audio_left;                    -- Latch left channel
                    right_data_reg <= audio_right;                  -- Latch right channel
                end if;
            end if;

            -- ================================================================
            -- CHANNEL SWITCHING AND DATA LOADING
            -- ================================================================
            -- Detect any WS transition (channel change)
            if ws_prev /= i2s_ws then
                bclk_count := 0;                    -- Reset bit counter at start of new channel
                if i2s_ws = '0' then
                    tx_data := left_data_reg;       -- WS low: transmit left channel
                else
                    tx_data := right_data_reg;      -- WS high: transmit right channel
                end if;
            else
                bclk_count := bclk_count + 1;       -- Increment bit position counter
            end if;

            -- ================================================================
            -- SERIAL DATA TRANSMISSION (using bit-indexing)
            -- ================================================================
            -- I2S timing: 1 BCLK delay after WS change, then 16 bits MSB-first
            if bclk_count = 0 then
                i2s_sdata <= '0';                                   -- Setup time: data line low
            elsif bclk_count >= 1 and bclk_count <= 16 then
                i2s_sdata <= tx_data(16 - bclk_count);              -- Transmit bit (MSB first)
                                                                     -- bclk_count=1: bit 15 (MSB)
                                                                     -- bclk_count=16: bit 0 (LSB)
            else
                i2s_sdata <= '0';                                   -- After 16 bits: data line low
            end if;

            -- Store current WS for next cycle edge detection
            ws_prev <= i2s_ws;
        end if;
    end process;

    -- Output assignment: propagate sample request pulse to external logic
    sample_request <= request_sample;

end architecture rtl;
