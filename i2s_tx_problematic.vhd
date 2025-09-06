-- ============================================================================
-- I2S Transmitter (PROBLEMATIC VERSION - FOR DOCUMENTATION)
-- ============================================================================
-- This version demonstrates common timing and synchronization issues
-- that can occur in I2S transmitter implementations.
--
-- KNOWN ISSUES IN THIS VERSION:
-- 1. Edge detection logic creates timing complexity
-- 2. Data latching race conditions
-- 3. Bit counter off-by-one errors
-- 4. State machine synchronization problems
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity i2s_tx_problematic is
    Port (
        -- Clock and Reset
        i2s_bclk     : in  std_logic;  -- I2S Bit Clock
        reset_n      : in  std_logic;  -- Active low reset
        
        -- Audio Data Input
        audio_left   : in  std_logic_vector(15 downto 0);
        audio_right  : in  std_logic_vector(15 downto 0);
        tx_ready     : in  std_logic;  -- Data ready signal
        
        -- I2S Interface
        i2s_ws       : in  std_logic;  -- Word Select (0=Left, 1=Right)
        i2s_sdata    : out std_logic;  -- Serial Data Output
        
        -- Control Signals
        request_sample : out std_logic  -- Request new sample
    );
end i2s_tx_problematic;

architecture rtl of i2s_tx_problematic is
    -- State machine definition
    type tx_state_type is (IDLE, WAIT_NEXT, LEFT_CHANNEL, RIGHT_CHANNEL);
    signal tx_state : tx_state_type := IDLE;
    
    -- Internal registers
    signal tx_shift_register : std_logic_vector(15 downto 0) := (others => '0');
    signal bit_counter : unsigned(4 downto 0) := (others => '0');
    
    -- Data latching
    signal left_data_latched  : std_logic_vector(15 downto 0) := (others => '0');
    signal right_data_latched : std_logic_vector(15 downto 0) := (others => '0');
    
    -- PROBLEMATIC: Edge detection signals (adds complexity)
    signal ws_prev : std_logic := '0';
    signal ws_edge_detected : std_logic := '0';
    signal ws_rising_edge : std_logic := '0';
    signal ws_falling_edge : std_logic := '0';

begin

    -- PROBLEMATIC: Complex edge detection logic
    edge_detection : process(i2s_bclk, reset_n)
    begin
        if reset_n = '0' then
            ws_prev <= '0';
            ws_edge_detected <= '0';
            ws_rising_edge <= '0';
            ws_falling_edge <= '0';
        elsif rising_edge(i2s_bclk) then
            ws_prev <= i2s_ws;
            ws_edge_detected <= ws_prev xor i2s_ws;
            ws_rising_edge <= (not ws_prev) and i2s_ws;
            ws_falling_edge <= ws_prev and (not i2s_ws);
        end if;
    end process;

    -- Sample Request Generation (has timing issues)
    process(i2s_bclk, reset_n)
    begin
        if reset_n = '0' then
            request_sample <= '0';
        elsif rising_edge(i2s_bclk) then
            -- PROBLEMATIC: Request generation based on complex edge logic
            if ws_falling_edge = '1' and tx_state = IDLE then
                request_sample <= '1';
            else
                request_sample <= '0';
            end if;
        end if;
    end process;

    -- PROBLEMATIC: Data Latching with race conditions
    process(i2s_bclk, reset_n)
    begin
        if reset_n = '0' then
            left_data_latched  <= (others => '0');
            right_data_latched <= (others => '0');
        elsif falling_edge(i2s_bclk) then  -- ISSUE: Wrong clock edge for latching
            -- PROBLEMATIC: Data latching on wrong edge can cause race conditions
            if tx_ready = '1' and ws_edge_detected = '1' then
                left_data_latched  <= audio_left;
                right_data_latched <= audio_right;
            end if;
        end if;
    end process;

    -- PROBLEMATIC: I2S TRANSMITTER STATE MACHINE
    process(i2s_bclk, reset_n)
    begin
        if reset_n = '0' then
            tx_state <= IDLE;
            tx_shift_register <= (others => '0');
            bit_counter <= (others => '0');  -- ISSUE: Should start at 1
            i2s_sdata <= '0';

        elsif falling_edge(i2s_bclk) then

            case tx_state is

                when IDLE =>
                    i2s_sdata <= '0';
                    if ws_falling_edge = '1' then  -- PROBLEMATIC: Dependency on edge detection
                        -- Start left channel
                        tx_shift_register <= left_data_latched;
                        bit_counter <= (others => '0');  -- ISSUE: Bit counter starts at 0
                        tx_state <= WAIT_NEXT;  -- PROBLEMATIC: Unnecessary state
                        i2s_sdata <= left_data_latched(15);  -- Output MSB
                    elsif ws_rising_edge = '1' then
                        -- Start right channel  
                        tx_shift_register <= right_data_latched;
                        bit_counter <= (others => '0');  -- ISSUE: Bit counter starts at 0
                        tx_state <= WAIT_NEXT;  -- PROBLEMATIC: Unnecessary state
                        i2s_sdata <= right_data_latched(15);  -- Output MSB
                    end if;

                when WAIT_NEXT =>  -- PROBLEMATIC: Unnecessary state adds complexity
                    if i2s_ws = '0' then
                        tx_state <= LEFT_CHANNEL;
                    else
                        tx_state <= RIGHT_CHANNEL;
                    end if;

                when LEFT_CHANNEL =>
                    if i2s_ws = '0' then
                        -- Continue left channel transmission
                        bit_counter <= bit_counter + 1;
                        tx_shift_register <= tx_shift_register(14 downto 0) & '0';
                        i2s_sdata <= tx_shift_register(14);  -- ISSUE: Should be (15)
                        
                        -- PROBLEMATIC: Incorrect bit counting (should count to 16, not 15)
                        if bit_counter = 14 then  
                            tx_state <= IDLE;
                        end if;
                    else
                        tx_state <= IDLE;  -- WS changed, abort
                    end if;

                when RIGHT_CHANNEL =>
                    if i2s_ws = '1' then
                        -- Continue right channel transmission
                        bit_counter <= bit_counter + 1;
                        tx_shift_register <= tx_shift_register(14 downto 0) & '0';
                        i2s_sdata <= tx_shift_register(14);  -- ISSUE: Should be (15)
                        
                        -- PROBLEMATIC: Incorrect bit counting (should count to 16, not 15)
                        if bit_counter = 14 then
                            tx_state <= IDLE;
                        end if;
                    else
                        tx_state <= IDLE;  -- WS changed, abort
                    end if;

                when others =>
                    tx_state <= IDLE;

            end case;
        end if;
    end process;

end rtl;
