-- ============================================================================
-- I2S SERIAL RECEIVER (ADC DATA)
-- ============================================================================
-- This module receives stereo audio data from an ADC via the I2S protocol.
--
-- I2S Protocol Summary:
--   - Data is transmitted MSB-first, left-justified
--   - WS (Word Select) = 0: Left channel data
--   - WS (Word Select) = 1: Right channel data
--   - Data is latched on the rising edge of BCLK (Bit Clock)
--   - Each channel transmits 16 bits per sample
--
-- Functionality:
--   1. Detects WS transitions to identify channel boundaries
--   2. Shifts in serial data bit-by-bit on each BCLK rising edge
--   3. Converts serial I2S data to parallel 16-bit samples
--   4. Outputs separate left and right channel data
--   5. Asserts rx_ready when a complete stereo pair is received
--
-- ============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity i2s_rx is
    port (
        -- Clock and reset
        i2s_bclk : in std_logic;  -- I2S bit clock (BCLK) - data is latched on rising edge
        i2s_ws   : in std_logic;  -- I2S word select (WS/LRCLK) - 0=left, 1=right channel
        reset_n  : in std_logic;  -- Active-low asynchronous reset

        -- I2S Serial Input (from ADC)
        i2s_sdata : in std_logic; -- Serial data input, MSB-first, left-justified

        -- Parallel Audio Output (16-bit samples)
        audio_left  : out std_logic_vector(15 downto 0); -- Left channel parallel output
        audio_right : out std_logic_vector(15 downto 0); -- Right channel parallel output
        rx_ready    : out std_logic                      -- Pulses high for 1 BCLK when stereo pair is complete
    );
end entity i2s_rx;

architecture rtl of i2s_rx is

    -- State machine for I2S reception
    -- IDLE: Waiting for WS transition to begin reception
    -- LEFT_CHANNEL: Receiving 16 bits of left channel data
    -- RIGHT_CHANNEL: Receiving 16 bits of right channel data
    type i2s_rx_state_t is (IDLE, LEFT_CHANNEL, RIGHT_CHANNEL);
    signal rx_state : i2s_rx_state_t := IDLE;

    -- Shift register for serial-to-parallel conversion (16 bits)
    signal rx_shift_register : std_logic_vector(15 downto 0) := (others => '0');
    
    -- Counts bits received in current channel (0-15)
    signal bit_counter : unsigned(4 downto 0) := "00000";
    
    -- Word-Select edge detection signals
    signal ws_prev          : std_logic := '0'; -- Previous WS value for edge detection
    signal ws_falling_edge  : std_logic := '0'; -- High for 1 BCLK when WS transitions 1→0 (left channel start)
    signal ws_rising_edge   : std_logic := '0'; -- High for 1 BCLK when WS transitions 0→1 (right channel start)

    -- Internal storage for received parallel samples
    signal left_sample   : std_logic_vector(15 downto 0) := (others => '0');  -- Latched left channel data
    signal right_sample  : std_logic_vector(15 downto 0) := (others => '0'); -- Latched right channel data
    signal valid_output  : std_logic := '0';                                 -- Indicates complete stereo pair received

begin

    -- ============================================================================
    -- Word-Select Edge Detector
    -- ============================================================================
    -- Detects transitions in the WS signal to identify channel boundaries.
    -- - Falling edge (1→0): Indicates start of left channel transmission
    -- - Rising edge (0→1): Indicates start of right channel transmission
    -- Both edge signals pulse high for exactly one BCLK cycle.
    -- ============================================================================
    process(i2s_bclk, reset_n)
    begin
        if reset_n = '0' then
            ws_prev <= '0';
            ws_falling_edge <= '0';
            ws_rising_edge <= '0';
        elsif rising_edge(i2s_bclk) then
            ws_prev <= i2s_ws;
            -- Detect falling edge (1→0) indicating left channel start
            ws_falling_edge <= ws_prev and not i2s_ws;
            -- Detect rising edge (0→1) indicating right channel start
            ws_rising_edge <= not ws_prev and i2s_ws;
        end if;
    end process;

    -- ============================================================================
    -- I2S RECEIVER STATE MACHINE
    -- ============================================================================
    -- Implements a state machine to receive I2S serial data and convert to parallel.
    --
    -- State Transitions:
    --   IDLE → LEFT_CHANNEL:  When WS falling edge detected
    --   IDLE → RIGHT_CHANNEL: When WS rising edge detected
    --   LEFT_CHANNEL → RIGHT_CHANNEL: After 16 bits received or premature WS change
    --   RIGHT_CHANNEL → LEFT_CHANNEL: After 16 bits received or premature WS change
    --   RIGHT_CHANNEL → IDLE: If no immediate transition to left channel
    --
    -- Operation:
    --   - Data is sampled on BCLK rising edge (per I2S specification)
    --   - Shifts in data MSB-first into a 16-bit shift register
    --   - After 16 bits, latches the complete sample and transitions to next channel
    --   - Asserts valid_output for 1 BCLK cycle when both channels are received
    --   - Handles premature WS transitions (error recovery)
    -- ============================================================================
    process(i2s_bclk, reset_n)
    begin
        if reset_n = '0' then
            -- Asynchronous reset: Initialize all signals to safe defaults
            rx_state <= IDLE;
            rx_shift_register <= (others => '0');
            bit_counter <= "00000";
            left_sample <= (others => '0');
            right_sample <= (others => '0');
            valid_output <= '0';

        elsif rising_edge(i2s_bclk) then
            -- Clear the valid_output flag by default; will be set when stereo pair completes
            valid_output <= '0';

            case rx_state is
                when IDLE =>
                    -- Wait for WS transition to begin reception
                    if ws_falling_edge = '1' then
                        -- WS transitioned to '0' → Start left channel reception
                        bit_counter <= "00000";
                        rx_shift_register <= (others => '0');
                        rx_state <= LEFT_CHANNEL;
                    elsif ws_rising_edge = '1' then
                        -- WS transitioned to '1' → Start right channel reception
                        bit_counter <= "00000";
                        rx_shift_register <= (others => '0');
                        rx_state <= RIGHT_CHANNEL;
                    end if;

                when LEFT_CHANNEL =>
                    -- Receive left channel data (16 bits, MSB-first)
                    -- Shift in new bit from i2s_sdata
                    rx_shift_register <= rx_shift_register(14 downto 0) & i2s_sdata;
                    bit_counter <= bit_counter + 1;

                    -- Check if 16 bits have been received
                    if bit_counter = "01111" then
                        -- Latch the complete 16-bit left sample
                        -- Include the current bit being shifted in
                        left_sample <= rx_shift_register(14 downto 0) & i2s_sdata;

                        -- Expect WS to transition to right channel
                        if ws_rising_edge = '1' then
                            bit_counter <= "00000";
                            rx_shift_register <= (others => '0');
                            rx_state <= RIGHT_CHANNEL;
                        end if;

                    -- Handle premature WS transition (error recovery)
                    elsif ws_rising_edge = '1' then
                        bit_counter <= "00000";
                        rx_shift_register <= (others => '0');
                        rx_state <= RIGHT_CHANNEL;
                    end if;

                when RIGHT_CHANNEL =>
                    -- Receive right channel data (16 bits, MSB-first)
                    -- Shift in new bit from i2s_sdata
                    rx_shift_register <= rx_shift_register(14 downto 0) & i2s_sdata;
                    bit_counter <= bit_counter + 1;

                    -- Check if 16 bits have been received
                    if bit_counter = "01111" then
                        -- Latch the complete 16-bit right sample
                        -- Include the current bit being shifted in
                        right_sample <= rx_shift_register(14 downto 0) & i2s_sdata;
                        -- Both channels received - assert valid_output for 1 BCLK cycle
                        valid_output <= '1';

                        -- Expect WS to transition to left channel
                        if ws_falling_edge = '1' then
                            bit_counter <= "00000";
                            rx_shift_register <= (others => '0');
                            rx_state <= LEFT_CHANNEL;
                        else
                            -- Return to IDLE if no immediate transition
                            rx_state <= IDLE;
                        end if;

                    -- Handle premature WS transition (error recovery)
                    elsif ws_falling_edge = '1' then
                        bit_counter <= "00000";
                        rx_shift_register <= (others => '0');
                        rx_state <= LEFT_CHANNEL;
                    end if;

            end case;
        end if;
    end process;

    -- ============================================================================
    -- OUTPUT ASSIGNMENTS
    -- ============================================================================
    -- Drive the output ports with internal signals
    -- - audio_left/right: Hold the most recently received complete samples
    -- - rx_ready: Pulses high for 1 BCLK when a stereo pair is received
    -- ============================================================================
    audio_left <= left_sample;
    audio_right <= right_sample;
    rx_ready <= valid_output;

end architecture rtl;