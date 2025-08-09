-- MIDI UART Receiver
-- Receives MIDI data at 31250 baud (8-N-1)
-- Author: Group 10
-- Device: EP4CE6E22C8N

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity midi_uart_rx is
    port (
        clk         : in  std_logic;  -- System clock (50MHz)
        reset_n     : in  std_logic;  -- Active low reset
        midi_rx     : in  std_logic;  -- MIDI RX line
        
        -- Output interface
        data_out    : out std_logic_vector(7 downto 0);  -- Received byte
        data_valid  : out std_logic;  -- Data valid pulse
        error       : out std_logic   -- Frame error
    );
end entity midi_uart_rx;

architecture rtl of midi_uart_rx is
    
    -- MIDI baud rate: 31250 bps
    -- Clock cycles per bit at 50MHz: 50,000,000 / 31,250 = 1600
    constant CLKS_PER_BIT : integer := 1600;
    constant CLKS_HALF_BIT : integer := CLKS_PER_BIT / 2;
    
    -- State machine for UART reception
    type uart_state_t is (IDLE, START_BIT, DATA_BITS, STOP_BIT);
    signal state : uart_state_t := IDLE;
    
    -- Internal signals
    signal bit_counter    : unsigned(2 downto 0) := (others => '0');
    signal clk_counter    : unsigned(10 downto 0) := (others => '0');
    signal rx_data_reg    : std_logic_vector(7 downto 0) := (others => '0');
    signal midi_rx_sync   : std_logic_vector(2 downto 0) := (others => '1');
    
begin
    
    -- Synchronize MIDI RX input to prevent metastability
    sync_process : process(clk, reset_n)
    begin
        if reset_n = '0' then
            midi_rx_sync <= (others => '1');
        elsif rising_edge(clk) then
            midi_rx_sync <= midi_rx_sync(1 downto 0) & midi_rx;
        end if;
    end process;
    
    -- UART receiver state machine
    uart_rx_process : process(clk, reset_n)
    begin
        if reset_n = '0' then
            state <= IDLE;
            bit_counter <= (others => '0');
            clk_counter <= (others => '0');
            rx_data_reg <= (others => '0');
            data_out <= (others => '0');
            data_valid <= '0';
            error <= '0';
            
        elsif rising_edge(clk) then
            data_valid <= '0';  -- Default
            error <= '0';       -- Default
            
            case state is
                when IDLE =>
                    bit_counter <= (others => '0');
                    clk_counter <= (others => '0');
                    
                    -- Look for start bit (falling edge)
                    if midi_rx_sync(2 downto 1) = "10" then
                        state <= START_BIT;
                        clk_counter <= to_unsigned(CLKS_HALF_BIT, clk_counter'length);
                    end if;
                
                when START_BIT =>
                    if clk_counter = 0 then
                        -- Sample in middle of start bit
                        if midi_rx_sync(2) = '0' then  -- Valid start bit
                            state <= DATA_BITS;
                            clk_counter <= to_unsigned(CLKS_PER_BIT - 1, clk_counter'length);
                            bit_counter <= (others => '0');
                        else  -- False start bit
                            state <= IDLE;
                        end if;
                    else
                        clk_counter <= clk_counter - 1;
                    end if;
                
                when DATA_BITS =>
                    if clk_counter = 0 then
                        -- Sample data bit (LSB first)
                        rx_data_reg(to_integer(bit_counter)) <= midi_rx_sync(2);
                        
                        if bit_counter = 7 then
                            state <= STOP_BIT;
                            clk_counter <= to_unsigned(CLKS_PER_BIT - 1, clk_counter'length);
                        else
                            bit_counter <= bit_counter + 1;
                            clk_counter <= to_unsigned(CLKS_PER_BIT - 1, clk_counter'length);
                        end if;
                    else
                        clk_counter <= clk_counter - 1;
                    end if;
                
                when STOP_BIT =>
                    if clk_counter = 0 then
                        if midi_rx_sync(2) = '1' then  -- Valid stop bit
                            data_out <= rx_data_reg;
                            data_valid <= '1';
                        else  -- Frame error
                            error <= '1';
                        end if;
                        state <= IDLE;
                    else
                        clk_counter <= clk_counter - 1;
                    end if;
            end case;
        end if;
    end process;
    
end architecture rtl;