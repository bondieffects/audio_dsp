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
        audio_valid : in std_logic;

        -- I2S Serial Data Output
        i2s_sdata : out std_logic;
        sample_request : out std_logic
    );
end entity i2s_tx;

architecture rtl of i2s_tx is

    -- State machine for I2S transmission
    type i2s_tx_state_t is (IDLE, LEFT_CHANNEL, RIGHT_CHANNEL, WAIT_NEXT);
    signal tx_state : i2s_tx_state_t := IDLE;

    -- Shift register for serial transmission
    signal tx_shift_register : std_logic_vector(15 downto 0) := (others => '0');
    signal bit_counter : unsigned(4 downto 0) := "00000";

    -- Word-select Edge Detection
    signal ws_prev : std_logic := '0';
    signal ws_falling_edge : std_logic := '0';
    signal ws_rising_edge : std_logic := '0';

    -- Sample request generation
    signal request_sample : std_logic := '0';
    signal request_pending : std_logic := '0';

    -- Data latching
    signal left_data_latched  : std_logic_vector(15 downto 0) := (others => '0');
    signal right_data_latched : std_logic_vector(15 downto 0) := (others => '0');

begin

    -- ============================================================================
    -- Word-select Edge Detection (FIXED)
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
    -- Sample Request Generation (Generate request once per frame)
    -- ============================================================================
    process(i2s_bclk, reset_n)
    begin
        if reset_n = '0' then
            request_sample <= '0';
            request_pending <= '0';
        elsif rising_edge(i2s_bclk) then
            -- Generate sample request at start of frame (falling edge of WS)
            if ws_falling_edge = '1' then
                request_sample <= '1';
                request_pending <= '1';
            elsif request_pending = '1' and bit_counter = "00001" then
                -- Clear request after first bit to create a pulse
                request_sample <= '0';
                request_pending <= '0';
            else
                request_sample <= '0';
            end if;
        end if;
    end process;

    -- ============================================================================
    -- Data Latching (Capture data when valid)
    -- ============================================================================
    process(i2s_bclk, reset_n)
    begin
        if reset_n = '0' then
            left_data_latched  <= (others => '0');
            right_data_latched <= (others => '0');
        elsif rising_edge(i2s_bclk) then
            -- Latch new data when available and at frame start
            if ws_falling_edge = '1' and audio_valid = '1' then
                left_data_latched  <= audio_left;
                right_data_latched <= audio_right;
            elsif ws_falling_edge = '1' and audio_valid = '0' then
                -- If no valid data, maintain previous values to avoid glitches
                -- Alternatively, you could fade to zero here
                null;  -- Keep previous values
            end if;
        end if;
    end process;

    -- ============================================================================
    -- I2S TRANSMITTER STATE MACHINE (FIXED)
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
                    
                    -- Start left channel transmission on WS falling edge
                    if ws_falling_edge = '1' then
                        tx_shift_register <= left_data_latched;
                        bit_counter <= "00000";
                        tx_state <= LEFT_CHANNEL;
                        i2s_sdata <= left_data_latched(15);  -- Start outputting immediately
                    
                    -- Start right channel transmission on WS rising edge
                    elsif ws_rising_edge = '1' then
                        tx_shift_register <= right_data_latched;
                        bit_counter <= "00000";
                        tx_state <= RIGHT_CHANNEL;
                        i2s_sdata <= right_data_latched(15);  -- Start outputting immediately
                    end if;

                when LEFT_CHANNEL =>
                    -- Output current bit
                    i2s_sdata <= tx_shift_register(15);
                    
                    -- Shift for next bit
                    tx_shift_register <= tx_shift_register(14 downto 0) & '0';
                    bit_counter <= bit_counter + 1;

                    -- Check for channel transition or completion
                    if bit_counter = "01111" then  -- After 16 bits
                        if ws_rising_edge = '1' then
                            -- Immediate transition to right channel
                            tx_shift_register <= right_data_latched;
                            bit_counter <= "00000";
                            tx_state <= RIGHT_CHANNEL;
                        else
                            tx_state <= WAIT_NEXT;
                        end if;
                    elsif ws_rising_edge = '1' then
                        -- Mid-transmission channel change (shouldn't happen in normal operation)
                        tx_shift_register <= right_data_latched;
                        bit_counter <= "00000";
                        tx_state <= RIGHT_CHANNEL;
                    end if;

                when RIGHT_CHANNEL =>
                    -- Output current bit
                    i2s_sdata <= tx_shift_register(15);
                    
                    -- Shift for next bit
                    tx_shift_register <= tx_shift_register(14 downto 0) & '0';
                    bit_counter <= bit_counter + 1;

                    -- Check for channel transition or completion
                    if bit_counter = "01111" then  -- After 16 bits
                        if ws_falling_edge = '1' then
                            -- Immediate transition to left channel
                            tx_shift_register <= left_data_latched;
                            bit_counter <= "00000";
                            tx_state <= LEFT_CHANNEL;
                        else
                            tx_state <= WAIT_NEXT;
                        end if;
                    elsif ws_falling_edge = '1' then
                        -- Mid-transmission channel change (shouldn't happen in normal operation)
                        tx_shift_register <= left_data_latched;
                        bit_counter <= "00000";
                        tx_state <= LEFT_CHANNEL;
                    end if;

                when WAIT_NEXT =>
                    -- Wait for next channel to start
                    i2s_sdata <= '0';
                    
                    if ws_falling_edge = '1' then
                        tx_shift_register <= left_data_latched;
                        bit_counter <= "00000";
                        tx_state <= LEFT_CHANNEL;
                    elsif ws_rising_edge = '1' then
                        tx_shift_register <= right_data_latched;
                        bit_counter <= "00000";
                        tx_state <= RIGHT_CHANNEL;
                    end if;

            end case;
        end if;
    end process;

    -- Output assignment
    sample_request <= request_sample;

end architecture rtl;