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
        rx_ready : out std_logic
    );
end entity i2s_rx;

architecture rtl of i2s_rx is

    -- State machine for I2S RX
    type i2s_rx_state_t is (IDLE, LEFT_CHANNEL, RIGHT_CHANNEL);
    signal rx_state : i2s_rx_state_t := IDLE;

    -- Shift register for serial reception
    signal rx_shift_register : std_logic_vector(15 downto 0) := (others => '0');
    signal bit_counter : unsigned(4 downto 0) := "00000";
    signal sync_ready : std_logic := '0';  -- '1' means ready to capture data, '0' means waiting for sync

    -- Parallel Audio Data Outputs
    signal left_sample : std_logic_vector(15 downto 0) := (others => '0');
    signal right_sample : std_logic_vector(15 downto 0) := (others => '0');
    signal valid_output : std_logic := '0';

begin

    -- ============================================================================
    -- I2S RECEIVER STATE MACHINE
    -- ============================================================================
    -- "Serial data... is latched... on the rising edge of [BCLK]."
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
            sync_ready <= '0';

        elsif rising_edge(i2s_bclk) then
            valid_output <= '0';

            case rx_state is

                when IDLE =>
                    if i2s_ws = '0' then
                        bit_counter <= "00000";
                        rx_shift_register <= (others => '0');
                        sync_ready <= '0';
                        rx_state <= LEFT_CHANNEL;
                    end if;

                when LEFT_CHANNEL =>
                    if i2s_ws = '0' then
                        if sync_ready = '0' then                                                -- wait for sync
                            sync_ready <= '1';
                        else
                            rx_shift_register <= rx_shift_register(14 downto 0) & i2s_sdata;    -- Shift new bits left, MSB enters at bit 0 and gets shifted to bit 15
                            bit_counter <= bit_counter + 1;                                     -- increment bit counter

                            if bit_counter = "01111" then                                       -- After 16 bits
                                left_sample <= rx_shift_register(14 downto 0) & i2s_sdata;      -- Combine 15 buffered bits with final bit to form complete sample
                                bit_counter <= "00000";                                         -- reset bit counter
                                rx_shift_register <= (others => '0');                           -- clear shift register
                                sync_ready <= '0';                                              -- reset sync_ready
                                rx_state <= RIGHT_CHANNEL;                                      -- switch to right channel
                            end if;
                        end if;
                    else
                        bit_counter <= "00000";                                                 -- WS changed to right channel
                        rx_shift_register <= (others => '0');                                   -- clear shift register
                        sync_ready <= '0';                                                      -- reset sync_ready
                        rx_state <= RIGHT_CHANNEL;                                              -- switch to right channel
                    end if;

                when RIGHT_CHANNEL =>
                    if i2s_ws = '1' then
                        if sync_ready = '0' then                                                -- wait for sync
                            sync_ready <= '1';
                        else
                            rx_shift_register <= rx_shift_register(14 downto 0) & i2s_sdata;    -- Shift new bits left, MSB enters at bit 0 and gets shifted to bit 15
                            bit_counter <= bit_counter + 1;                                     -- increment bit counter

                            if bit_counter = "01111" then                                       -- After 16 data bits
                                right_sample <= rx_shift_register(14 downto 0) & i2s_sdata;     -- Combine 15 buffered bits with final bit to form complete sample
                                valid_output <= '1';                                            -- left and right samples ready
                                bit_counter <= "00000";                                         -- reset bit counter
                                rx_shift_register <= (others => '0');                           -- clear shift register
                                sync_ready <= '0';                                              -- reset sync_ready
                                rx_state <= LEFT_CHANNEL;                                       -- switch back to left channel
                            end if;
                        end if;
                    else
                        bit_counter <= "00000";                                                 -- WS changed to left channel
                        rx_shift_register <= (others => '0');                                   -- clear shift register
                        sync_ready <= '0';                                                      -- reset sync_ready
                        rx_state <= LEFT_CHANNEL;                                               -- switch to left channel
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