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
            -- Default: no sample request
            request_sample <= '0';
            
            -- Sample request on WS falling edge (start of new frame)
            if ws_prev = '1' and i2s_ws = '0' then
                request_sample <= '1';
                if tx_ready = '1' then
                    left_data_reg <= audio_left;
                    right_data_reg <= audio_right;
                end if;
            end if;
            
            -- Detect WS changes and reset bit counter
            if ws_prev /= i2s_ws then
                bclk_count := 0;  -- Reset counter on WS change
                
                -- Load appropriate data for the new channel
                if i2s_ws = '0' then
                    tx_data := left_data_reg;   -- Left channel
                else
                    tx_data := right_data_reg;  -- Right channel
                end if;
            else
                bclk_count := bclk_count + 1;  -- Increment counter
            end if;
            
            -- I2S Data Transmission
            if bclk_count = 0 then
                -- First BCLK after WS change - output 0 (setup time)
                i2s_sdata <= '0';
            elsif bclk_count >= 1 and bclk_count <= 16 then
                -- Transmit 16 bits of data (MSB first)
                i2s_sdata <= tx_data(16 - bclk_count);
            else
                -- Outside data transmission period
                i2s_sdata <= '0';
            end if;
            
            -- Update WS history
            ws_prev <= i2s_ws;
        end if;
    end process;
    
    -- Connect sample request output
    sample_request <= request_sample;

end architecture rtl;
