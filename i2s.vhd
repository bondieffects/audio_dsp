-- ============================================================================
-- I2S MODULE
-- ============================================================================

-- LIBRARIES and PACKAGES
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

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


-- ============================================================================
-- 1. I2S Clock Generator
-- ============================================================================
-- The I2S master must generate the I2S clocks:
--   - I2S Master Clock (MCLK)      12.288MHz from audio_pll (generated IP)
--   - I2S Bit Clock (BCLK)         1.536MHz (MCLK/8 = 32 × 48kHz for 16-bit stereo)
--   - I2S Word Select (WS)         48kHz (BCLK/32)

-- LIBRARIES and PACKAGES for i2s_clocks
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;


entity i2s_clocks is 
    port (
        -- Inputs
        i2s_mclk : in std_logic;        -- 12.288MHz master clock from audio_pll
        reset_n : in std_logic;         -- Active low reset

        -- Outputs
        i2s_bclk : out std_logic;       -- 1.536MHz bit clock
        i2s_ws : out std_logic          -- 48kHz left/right clock
    );
end entity i2s_clocks;

-- Register-Transfer Level (RTL) describes how data flows between
-- registers (storage elements like flip-flops) and the
-- operations (combinational logic) performed on that data between clock edges.
architecture rtl of i2s_clocks is

    -- CLOCK DIVISION SIGNALS
    signal bclk_counter : unsigned(2 downto 0) := "000";    -- For BCLK generation (divide by 8)
    signal ws_counter : unsigned(4 downto 0) := "00000";    -- For WS generation (count 32 BCLK cycles)

    -- OUTPUT CLOCK SIGNALS
    signal bclk_signal : std_logic := '0';
    
    -- BCLK edge detection for WS counting
    signal bclk_prev : std_logic := '0';
    signal bclk_edge : std_logic := '0';

begin

    -- ========================================================================
    -- BCLK GENERATION: Divide 12.288MHz by 8 to get 1.536MHz
    -- ========================================================================
    process (i2s_mclk, reset_n)
    begin
        if reset_n = '0' then
            bclk_counter <= "000";
            bclk_signal <= '0';
        elsif rising_edge(i2s_mclk) then
            if bclk_counter = "011" then  -- Count 0,1,2,3
                bclk_signal <= not bclk_signal;
                bclk_counter <= "000";
            else
                bclk_counter <= bclk_counter + 1;
            end if;
        end if;
    end process;

    -- ========================================================================
    -- BCLK EDGE DETECTION
    -- ========================================================================
    process (i2s_mclk, reset_n)
    begin
        if reset_n = '0' then
            bclk_prev <= '0';
            bclk_edge <= '0';
        elsif rising_edge(i2s_mclk) then
            bclk_prev <= bclk_signal;
            -- Detect rising edge of BCLK
            bclk_edge <= bclk_signal and not bclk_prev;
        end if;
    end process;

    -- ========================================================================
    -- WS GENERATION: Count 32 BCLK cycles to get 48kHz
    -- ========================================================================
    -- For 16-bit I2S: 16 BCLK cycles per channel, 32 total per sample period
    -- WS = 0 for left channel (counts 0-15), WS = 1 for right channel (counts 16-31)
    process (i2s_mclk, reset_n)
    begin
        if reset_n = '0' then
            ws_counter <= "00000";
        elsif rising_edge(i2s_mclk) then
            if bclk_edge = '1' then  -- Count on BCLK rising edges
                ws_counter <= ws_counter + 1;
                -- Counter automatically wraps from 31 back to 0 (5-bit counter)
            end if;
        end if;
    end process;

    -- ========================================================================
    -- CONNECT SIGNALS TO OUTPUTS
    -- ========================================================================
    i2s_bclk <= bclk_signal;
    i2s_ws <= ws_counter(4);

end architecture rtl;

-- ============================================================================
-- 2. I2S SERIAL TRANSMITTER (DAC DATA)
-- ============================================================================
-- To transmit data to the DAC we must:
--      1. Convert the internal parallel audio data to I2S serial format
--      2. Serial multiplex the left and right channel data

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

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
        audio_valid : out std_logic                     -- RX Ready Flag
    );
end entity i2s_rx;

architecture rtl of i2s_rx is

    -- Create a state machine for I2S data in
    type i2s_rx_state_t is (IDLE, LEFT_CHANNEL, RIGHT_CHANNEL);
    signal rx_state : i2s_rx_state_t := IDLE;

    -- Create a shift register for serial reception
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
    -- Word-select Edge Detector (FIXED)
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
    -- I2S RECEIVER STATE MACHINE (FIXED)
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
            -- Default valid_output to '0' unless we complete right channel
            valid_output <= '0';

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
                        else
                            rx_state <= IDLE;
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
                        valid_output <= '1';  -- Both channels received
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
    audio_valid <= valid_output;

end architecture rtl;

-- ========================================================================
-- 4. AUDIO PLL
-- ========================================================================


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
            audio_valid => audio_out_valid,
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
            audio_valid => audio_in_valid
        );

    -- ========================================================================
    -- CONNECT SIGNALS TO OUTPUTS
    -- ========================================================================
    i2s_bclk <= bclk_signal;       -- Connect internal BCLK to output
    i2s_ws <= ws_signal;         -- Connect internal WS to output

end architecture rtl;