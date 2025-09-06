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

    -- State machine for I2S transmission
    type i2s_tx_state_t is (IDLE, LEFT_CHANNEL, RIGHT_CHANNEL);
    signal tx_state : i2s_tx_state_t := IDLE;

    -- Shift register for serial transmission
    signal tx_shift_register : std_logic_vector(15 downto 0) := (others => '0');
    signal bit_counter : unsigned(4 downto 0) := "00000";

    -- Sample request generation
    signal request_sample : std_logic := '0';

    -- Data latching
    signal left_data_latched  : std_logic_vector(15 downto 0) := (others => '0');
    signal right_data_latched : std_logic_vector(15 downto 0) := (others => '0');

begin

    -- ============================================================================
    -- Sample Request Generation
    -- ============================================================================
    process(i2s_bclk, reset_n)
    begin
        if reset_n = '0' then
            request_sample <= '0';
        elsif rising_edge(i2s_bclk) then
            -- Generate sample request at start of left channel
            if i2s_ws = '0' and tx_state = IDLE then
                request_sample <= '1';
            else
                request_sample <= '0';
            end if;
        end if;
    end process;

    -- ============================================================================
    -- Data Latching (Capture data when tx_ready is asserted)
    -- ============================================================================
    process(i2s_bclk, reset_n)
    begin
        if reset_n = '0' then
            left_data_latched  <= (others => '0');
            right_data_latched <= (others => '0');
        elsif rising_edge(i2s_bclk) then
            -- Latch data whenever new valid data is available
            if tx_ready = '1' then
                left_data_latched  <= audio_left;
                right_data_latched <= audio_right;
            end if;
        end if;
    end process;

    -- ============================================================================
    -- I2S TRANSMITTER STATE MACHINE
    -- ============================================================================
    process(i2s_bclk, reset_n)
    begin
        if reset_n = '0' then
            tx_state <= IDLE;
            tx_shift_register <= (others => '0');
            bit_counter <= "00000";
            i2s_sdata <= '0';

        elsif falling_edge(i2s_bclk) then  -- Transmit on falling edge per I2S spec

            case tx_state is

                when IDLE =>
                    i2s_sdata <= '0';
                    if i2s_ws = '0' then
                        -- Start left channel
                        tx_shift_register <= left_data_latched(14 downto 0) & '0';  -- Pre-shift for next bit
                        bit_counter <= "00001";  -- Start at 1 since we're outputting bit 0 now
                        tx_state <= LEFT_CHANNEL;
                        i2s_sdata <= left_data_latched(15);  -- Output MSB immediately
                    elsif i2s_ws = '1' then
                        -- Start right channel
                        tx_shift_register <= right_data_latched(14 downto 0) & '0';  -- Pre-shift for next bit
                        bit_counter <= "00001";  -- Start at 1 since we're outputting bit 0 now
                        tx_state <= RIGHT_CHANNEL;
                        i2s_sdata <= right_data_latched(15);  -- Output MSB immediately
                    end if;

                when LEFT_CHANNEL =>
                    if i2s_ws = '0' then
                        -- Continue left channel transmission
                        i2s_sdata <= tx_shift_register(15);
                        tx_shift_register <= tx_shift_register(14 downto 0) & '0';
                        bit_counter <= bit_counter + 1;

                        -- After 16 bits, go idle
                        if bit_counter = "10000" then  -- 16 in binary (since we start at 1)
                            tx_state <= IDLE;
                        end if;
                    else
                        -- WS changed to right channel
                        bit_counter <= "00001";  -- Start at 1 since we're outputting bit 0 now
                        tx_shift_register <= right_data_latched(14 downto 0) & '0';  -- Pre-shift for next bit
                        tx_state <= RIGHT_CHANNEL;
                        i2s_sdata <= right_data_latched(15);  -- Output MSB immediately
                    end if;

                when RIGHT_CHANNEL =>
                    if i2s_ws = '1' then
                        -- Continue right channel transmission
                        i2s_sdata <= tx_shift_register(15);
                        tx_shift_register <= tx_shift_register(14 downto 0) & '0';
                        bit_counter <= bit_counter + 1;

                        -- After 16 bits, go idle
                        if bit_counter = "10000" then  -- 16 in binary (since we start at 1)
                            tx_state <= IDLE;
                        end if;
                    else
                        -- WS changed to left channel
                        bit_counter <= "00001";  -- Start at 1 since we're outputting bit 0 now
                        tx_shift_register <= left_data_latched(14 downto 0) & '0';  -- Pre-shift for next bit
                        tx_state <= LEFT_CHANNEL;
                        i2s_sdata <= left_data_latched(15);  -- Output MSB immediately
                    end if;

            end case;
        end if;
    end process;

    -- Output assignment
    sample_request <= request_sample;

end architecture rtl;
