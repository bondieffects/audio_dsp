-- ============================================================================
-- 3. I2S SERIAL RECEIVER (ADC DATA)
-- ============================================================================
-- To receive data from the ADC we must:
--      1. Convert the I2S serial data to internal parallel audio format
--      2. Serial multiplex the left and right channel data

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity i2s_rx is
    port (
        -- Clock and reset
        i2s_bclk : in std_logic;
        i2s_ws   : in std_logic;
        reset_n  : in std_logic;

        -- I2S Serial Input (ADC DATA)
        i2s_sdata : in std_logic;

        -- Parallel Audio Output (16-bit samples)
        audio_left  : out std_logic_vector(15 downto 0);
        audio_right : out std_logic_vector(15 downto 0);
        rx_ready : out std_logic                     -- RX Ready Flag
    );
end entity i2s_rx;

architecture rtl of i2s_rx is

    -- Create a state machine for I2S data in
    type i2s_rx_state_t is (IDLE, LEFT_CHANNEL, RIGHT_CHANNEL);
    signal rx_state : i2s_rx_state_t := IDLE;

    -- Create a shift register for serial reception
    signal rx_shift_register : std_logic_vector(15 downto 0) := (others => '0');
    signal bit_counter : unsigned(4 downto 0) := "00000";

    -- Parallel Audio Data Outputs
    signal left_sample : std_logic_vector(15 downto 0) := (others => '0');
    signal right_sample : std_logic_vector(15 downto 0) := (others => '0');
    signal valid_output : std_logic := '0';

begin

    -- ============================================================================
    -- I2S RECEIVER STATE MACHINE
    -- ============================================================================
    -- Receive data on rising edge of BCLK
    -- I2S Format: MSB first, left-justified
    -- WS = 0: Left channel, WS = 1: Right channel

    process(i2s_bclk, reset_n)
    begin
        if reset_n = '0' then
            rx_state <= IDLE;
            rx_shift_register <= (others => '0');
            bit_counter <= "00000";
            left_sample <= (others => '0');
            right_sample <= (others => '0');
            valid_output <= '0';

        elsif rising_edge(i2s_bclk) then
            -- Don't clear valid_output every cycle - only when starting new frame

            case rx_state is

                when IDLE =>
                    valid_output <= '0';    -- Clear valid when idle
                    if i2s_ws = '0' then
                        bit_counter <= "00000";
                        rx_shift_register <= (others => '0');
                        rx_state <= LEFT_CHANNEL;
                    elsif i2s_ws = '1' then
                        bit_counter <= "00000";
                        rx_shift_register <= (others => '0');
                        rx_state <= RIGHT_CHANNEL;
                    end if;

                when LEFT_CHANNEL =>
                    if i2s_ws = '0' then
                        rx_shift_register <= rx_shift_register(14 downto 0) & i2s_sdata;
                        bit_counter <= bit_counter + 1;

                        -- After 16 bits, save and go idle
                        if bit_counter = "01110" then    -- Complete on 15th bit (16 total bits since counter starts at 0)                                   
                            left_sample <= rx_shift_register(14 downto 0) & i2s_sdata;  -- Concatenate 15 shifted bits + current bit = complete 16-bit sample
                            rx_state <= IDLE;
                        end if;
                    else
                        -- WS changed to right channel - start right channel reception
                        bit_counter <= "00000";
                        rx_shift_register <= (others => '0');
                        rx_state <= RIGHT_CHANNEL;
                    end if;

                when RIGHT_CHANNEL =>
                    if i2s_ws = '1' then
                        rx_shift_register <= rx_shift_register(14 downto 0) & i2s_sdata;
                        bit_counter <= bit_counter + 1;

                        -- After 16 bits, save and mark valid
                        if bit_counter = "01110" then    -- Complete on 15th bit (16 total bits since counter starts at 0)                               
                            right_sample <= rx_shift_register(14 downto 0) & i2s_sdata;  -- Concatenate 15 shifted bits + current bit = complete 16-bit sample
                            valid_output <= '1';                                         -- Right channel complete, both samples now available
                            rx_state <= IDLE;
                        end if;
                    else
                        -- WS changed to left channel - start left channel reception
                        bit_counter <= "00000";                 -- reset bit counter
                        rx_shift_register <= (others => '0');   -- reset shift register
                        rx_state <= LEFT_CHANNEL;               -- switch to left channel
                    end if;

            end case;
        end if;
    end process;

    -- ========================================================================
    -- CONNECT SIGNALS TO OUTPUTS
    -- ========================================================================
    audio_left <= left_sample;
    audio_right <= right_sample;
    rx_ready <= valid_output;

end architecture rtl;