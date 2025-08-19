-- ============================================================================
-- I2S MODULE
-- ============================================================================

-- LIBRARIES and PACKAGES
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- For Altera PLL component
library altera_mf;
use altera_mf.all;

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
            bclk_counter <= bclk_counter + 1;
            -- Toggle BCLK every 4 MCLK cycles (divide by 8 total)
            if bclk_counter = "011" then  -- 3 in decimal
                bclk_signal <= not bclk_signal;
                bclk_counter <= "000";    -- Reset counter after toggle
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

-- LIBRARIES and PACKAGES for i2s_tx
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity i2s_tx is 
    port (
        -- Clocks and Reset
        i2s_bclk : in std_logic;
        i2s_ws : in std_logic;
        reset_n : in std_logic;

        -- Parallel audio data inputs (16-bit samples)
        audio_left : in std_logic_vector(15 downto 0);      -- Left channel audio data
        audio_right : in std_logic_vector(15 downto 0);     -- Right channel audio data
        audio_valid : in std_logic;                         -- are these used/necessary? TX Ready Flag

        -- I2S Serial Data Outputs
        i2s_sdata : out std_logic;                          -- Serial data output (DAC_DATA)
        sample_request : out std_logic                      -- are these used/necessary? Sample request signal
    );
end entity i2s_tx;

architecture rtl of i2s_tx is

    -- Create a state machine for I2S data out
    type i2s_tx_state_t is (IDLE, LEFT_CHANNEL, RIGHT_CHANNEL);
    signal tx_state : i2s_tx_state_t := IDLE; -- Create a signal for the the TX state, initialised to IDLE

    -- Create a shift register for serial transmission
    signal tx_shift_register : std_logic_vector(15 downto 0) := (others => '0');    -- Create a 16-bit signal bus "tx_shift_register"
    signal bit_counter : unsigned(4 downto 0) := "00000";                           -- Create a 5-bit counter to track the bit position

    -- Word-select Edge Detector
    signal ws_prev : std_logic := '0';
    signal ws_edge : std_logic := '0';

    -- Sample request generation
    signal request_sample : std_logic := '0'; -- Again ensure this is requrired

begin

    -- ============================================================================
    -- Word-select Edge Detector
    -- ============================================================================
    process(i2s_bclk, reset_n)
    begin
        if reset_n = '0' then
            ws_prev <= '0';     -- hold previous WS edge low
            ws_edge <= '0';     -- hold WS edge low
        elsif rising_edge(i2s_bclk) then
            ws_prev <= i2s_ws;
            ws_edge <= i2s_ws xor ws_prev;      -- true if i2s_ws is different from ws_prev
        end if;
    end process;

    -- ============================================================================
    -- I2S TRANSMITTER STATE MACHINE
    -- ============================================================================
    -- I2S Format: MSB first, left-justified
    -- WS = 0: Left channel, WS = 1: Right channel

    process(i2s_bclk, reset_n)
    begin
        if reset_n = '0' then
            tx_state <= IDLE;                       -- Reset state machine to IDLE
            tx_shift_register <= (others => '0');   -- Clear shift register
            bit_counter <= "00000";                 -- Reset bit counter
            i2s_sdata <= '0';                       -- Hold serial data low
            request_sample <= '0';                  -- Reset sample request signal

        elsif falling_edge(i2s_bclk) then           -- I2S transmit on the falling edge

            case tx_state is

                when IDLE =>
                    i2s_sdata <= '0';
                    if ws_edge = '1' then
                        request_sample <= '1';      -- Request a new sample (LR pair)
                        bit_counter <= "00000";

                        if i2s_ws = '0' then
                            -- Transmit left channel data
                            tx_state <= LEFT_CHANNEL;
                            if audio_valid = '1' then
                                tx_shift_register <= audio_left;        -- Load left channel data into shift register
                            else
                                tx_shift_register <= (others => '0');   -- Silence (send zeros)
                            end if;
                        else
                            -- Transmit right channel data
                            tx_state <= RIGHT_CHANNEL;
                            if audio_valid = '1' then
                                tx_shift_register <= audio_right;       -- Load right channel data into shift register
                            else
                                tx_shift_register <= (others => '0');   -- Silence (send zeros)
                            end if;
                        end if;
                    end if;

                when LEFT_CHANNEL =>
                    request_sample <= '0';
                    i2s_sdata <= tx_shift_register(15);                             -- Transmit MSB
                    tx_shift_register <= tx_shift_register(14 downto 0) & '0';      -- Transmit remaining bits
                    bit_counter <= bit_counter + 1;                                 -- Increment bit counter

                    -- Verify that all 16 bits have been transmitted
                    if bit_counter = "01111" then
                        tx_state <= IDLE;                                               -- Return to IDLE state
                    end if;

                when RIGHT_CHANNEL =>
                    request_sample <= '0';
                    i2s_sdata <= tx_shift_register(15);                             -- Transmit MSB
                    tx_shift_register <= tx_shift_register(14 downto 0) & '0';      -- Transmit remaining bits
                    bit_counter <= bit_counter + 1;                                 -- Increment bit counter

                    -- Verify that all 16 bits have been transmitted
                    if bit_counter = "01111" then
                        tx_state <= IDLE;                                               -- Return to IDLE state
                    end if;
    
            end case;
        end if;
    end process;

    sample_request <= request_sample;

end architecture rtl;

-- ============================================================================
-- 3. I2S SERIAL RECEIVER (ADC DATA)
-- ============================================================================
-- To receive data from the ADC we must:
--      1. Convert the I2S serial data to internal parallel audio format
--      2. Serial multiplex the left and right channel data

-- LIBRARIES and PACKAGES for i2s_rx
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
    signal ws_edge : std_logic := '0';

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
            ws_edge <= '0';
        elsif rising_edge(i2s_bclk) then
            ws_prev <= i2s_ws;
            ws_edge <= i2s_ws xor ws_prev;
        end if;
    end process;

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

            case rx_state is

            when IDLE =>
                valid_output <= '0';
                if ws_edge = '1' then
                    bit_counter <= "00000";
                    rx_shift_register <= (others => '0');

                    if i2s_ws = '0' then
                        -- Start receiving left channel data
                        rx_state <= LEFT_CHANNEL;
                    else
                        -- Start receiving right channel data
                        rx_state <= RIGHT_CHANNEL;
                    end if;
                end if;

            when LEFT_CHANNEL =>
                rx_shift_register <= rx_shift_register(14 downto 0) & i2s_sdata;
                bit_counter <= bit_counter + 1;

                if bit_counter = "01111" then
                    left_sample <= rx_shift_register(14 downto 0) & i2s_sdata;
                    rx_state <= IDLE;
                end if;

            when RIGHT_CHANNEL =>
                rx_shift_register <= rx_shift_register(14 downto 0) & i2s_sdata;
                bit_counter <= bit_counter + 1;

                if bit_counter = "01111" then
                    right_sample <= rx_shift_register(14 downto 0) & i2s_sdata;
                    valid_output <= '1';
                    rx_state <= IDLE;
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