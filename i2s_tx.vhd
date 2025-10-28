library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- ============================================================================
-- 2. I2S SERIAL TRANSMITTER (DAC DATA)
-- ============================================================================
-- To transmit data to the DAC we must:
--      1. Convert the internal parallel audio data to I2S serial format
--      2. Serial multiplex the left and right channel data

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
    -- I2S Transmitter signals
    signal ws_prev : std_logic := '0';
    signal request_sample : std_logic := '0';

    -- Data storage
    signal left_data_reg : std_logic_vector(15 downto 0) := (others => '0');
    signal right_data_reg : std_logic_vector(15 downto 0) := (others => '0');

    -- Transmission control
    signal bit_count : integer range 0 to 16 := 0;
    signal transmitting : std_logic := '0';
    signal current_data : std_logic_vector(15 downto 0) := (others => '0');

begin
    -- ============================================================================
    -- I2S Transmitter Process - Simple and Direct I2S Implementation
    -- ============================================================================
    process(i2s_bclk, reset_n)
        variable bclk_count : integer range 0 to 20 := 0;
        variable tx_data : std_logic_vector(15 downto 0);
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
            -- Reset sample request each BCLK
            request_sample <= '0';

            -- On WS falling edge (beginning of left channel)
            if ws_prev = '1' and i2s_ws = '0' then
                request_sample <= '1';                              -- Assert request_sample
                if tx_ready = '1' then
                    left_data_reg <= audio_left;                    -- Load new left channel data
                    right_data_reg <= audio_right;                  -- Load new right channel data
                end if;
            end if;

            -- If WS has changed, reset BCLK counter and load new data
            if ws_prev /= i2s_ws then
                bclk_count := 0;                -- Reset counter on WS change
                if i2s_ws = '0' then
                    tx_data := left_data_reg;   -- Load new left channel data
                else
                    tx_data := right_data_reg;  -- Load new right channel data
                end if;
            else
                bclk_count := bclk_count + 1;   -- Increment bclk_count through the frame
            end if;

            -- I2S Data Transmission
            if bclk_count = 0 then
                -- Delay one bclk after WS change (setup time)
                i2s_sdata <= '0';                                   -- Data line low during setup
            elsif bclk_count >= 1 and bclk_count <= 16 then
                i2s_sdata <= tx_data(16 - bclk_count);              -- Shift out data (MSB first)
            else
                i2s_sdata <= '0';                                   -- Data line low when not transmitting
            end if;

            -- Store the previous WS state
            ws_prev <= i2s_ws;
        end if;
    end process;

    sample_request <= request_sample;   -- Generate a 1-cycle pulse to request new samples

end architecture rtl;
