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
    
    -- Word-select Edge Detector
    signal ws_prev : std_logic := '0';
    signal ws_falling_edge : std_logic := '0';
    signal ws_rising_edge : std_logic := '0';

    -- Parallel Audio Data Outputs
    signal left_sample : std_logic_vector(15 downto 0) := (others => '0');
    signal right_sample : std_logic_vector(15 downto 0) := (others => '0');
    signal valid_output : std_logic := '0';

begin

    -- ============================================================================
    -- Word-select Edge Detector
    -- ============================================================================
    process(i2s_bclk, reset_n)
    begin
        if reset_n = '0' then
            ws_prev <= '0';
            ws_falling_edge <= '0';
            ws_rising_edge <= '0';
        elsif rising_edge(i2s_bclk) then
            ws_prev <= i2s_ws;
            -- Detect falling edge (1→0) for left channel start
            ws_falling_edge <= ws_prev and not i2s_ws;
            -- Detect rising edge (0→1) for right channel start  
            ws_rising_edge <= not ws_prev and i2s_ws;
        end if;
    end process;

    -- ============================================================================
    -- I2S RECEIVER STATE MACHINE
    -- ============================================================================
    -- "Serial data... is latched... on the rising edge of [BCLK]."
    -- I2S Format: MSB first, left-justified
    -- WS = 0: Left channel, WS = 1: Right channel

    process(i2s_bclk, reset_n)
    begin
        if reset_n = '0' then
            -- Clean reset of all signals
            rx_state <= IDLE;
            rx_shift_register <= (others => '0');
            bit_counter <= "00000";
            left_sample <= (others => '0');
            right_sample <= (others => '0');
            valid_output <= '0';

        elsif rising_edge(i2s_bclk) then
            valid_output <= '0';  -- Default state, will be set to '1' when both channels complete

            case rx_state is
                when IDLE =>
                    -- Check for WS transitions to start receiving
                    if ws_falling_edge = '1' then
                        -- WS goes low: start receiving left channel
                        bit_counter <= "00000";
                        rx_shift_register <= (others => '0');
                        rx_state <= LEFT_CHANNEL;
                    elsif ws_rising_edge = '1' then
                        -- WS goes high: start receiving right channel
                        bit_counter <= "00000";
                        rx_shift_register <= (others => '0');
                        rx_state <= RIGHT_CHANNEL;
                    end if;

                when LEFT_CHANNEL =>
                    -- Shift in data bit by bit
                    rx_shift_register <= rx_shift_register(14 downto 0) & i2s_sdata;
                    bit_counter <= bit_counter + 1;

                    -- After 16 bits, save left channel and check for channel change
                    if bit_counter = "01111" then
                        left_sample <= rx_shift_register(14 downto 0) & i2s_sdata;
                        -- Check if we should continue or switch channels
                        if ws_rising_edge = '1' then
                            -- WS went high during reception, switch to right
                            bit_counter <= "00000";
                            rx_shift_register <= (others => '0');
                            rx_state <= RIGHT_CHANNEL;
                        end if;
                    elsif ws_rising_edge = '1' then
                        -- WS changed mid-reception, switch immediately
                        bit_counter <= "00000";
                        rx_shift_register <= (others => '0');
                        rx_state <= RIGHT_CHANNEL;
                    end if;

                when RIGHT_CHANNEL =>
                    -- Shift in data bit by bit
                    rx_shift_register <= rx_shift_register(14 downto 0) & i2s_sdata;
                    bit_counter <= bit_counter + 1;

                    -- After 16 bits, save right channel and mark data valid
                    if bit_counter = "01111" then
                        right_sample <= rx_shift_register(14 downto 0) & i2s_sdata;
                        valid_output <= '1';  -- Both channels received, data is ready
                        
                        -- Check if we should continue or switch channels
                        if ws_falling_edge = '1' then
                            -- WS went low during reception, switch to left
                            bit_counter <= "00000";
                            rx_shift_register <= (others => '0');
                            rx_state <= LEFT_CHANNEL;
                        else
                            rx_state <= IDLE;
                        end if;
                    elsif ws_falling_edge = '1' then
                        -- WS changed mid-reception, switch immediately
                        bit_counter <= "00000";
                        rx_shift_register <= (others => '0');
                        rx_state <= LEFT_CHANNEL;
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