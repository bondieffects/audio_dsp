library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- ============================================================================
-- MIDI UART Receiver
-- ============================================================================
-- Simple 31.25 kbps (MIDI standard) 8-N-1 UART receiver clocked from 50 MHz.
-- Outputs each received byte with a one-cycle 'data_valid' strobe aligned to
-- the system clock domain.
-- ============================================================================
entity midi_uart_rx is
    port (
        clk        : in  std_logic;   -- System clock (50 MHz)
        reset_n    : in  std_logic;   -- Active-low reset
        midi_in    : in  std_logic;   -- MIDI DIN input (after opto / level shift)
        data_byte  : out std_logic_vector(7 downto 0);
        data_valid : out std_logic
    );
end entity midi_uart_rx;

architecture rtl of midi_uart_rx is
    -- MIDI baud rate: 31.25 kBd -> 50 MHz / 31.25 kBd = 1600 clocks per bit
    constant BIT_TICKS      : integer := 1600;
    constant HALF_BIT_TICKS : integer := BIT_TICKS / 2;

    type rx_state_t is (IDLE, START, DATA, STOP);
    signal state       : rx_state_t := IDLE;
    signal baud_count  : integer range 0 to BIT_TICKS := 0;
    signal bit_index   : integer range 0 to 7 := 0;
    signal shift_reg   : std_logic_vector(7 downto 0) := (others => '0');
    signal data_valid_i: std_logic := '0';
    signal data_byte_i : std_logic_vector(7 downto 0) := (others => '0');
    signal midi_sync   : std_logic := '1';
    signal midi_meta   : std_logic := '1';
begin

    -- Two-flop synchroniser to mitigate metastability from asynchronous MIDI input
    process(clk, reset_n)
    begin
        if reset_n = '0' then
            midi_meta <= '1';
            midi_sync <= '1';
        elsif rising_edge(clk) then
            midi_meta <= midi_in;
            midi_sync <= midi_meta;
        end if;
    end process;

    process(clk, reset_n)
    begin
        if reset_n = '0' then
            state       <= IDLE;
            baud_count  <= 0;
            bit_index   <= 0;
            shift_reg   <= (others => '0');
            data_valid_i<= '0';
            data_byte_i <= (others => '0');
        elsif rising_edge(clk) then
            data_valid_i <= '0';  -- default

            case state is
                when IDLE =>
                    -- Wait for start bit (falling edge)
                    if midi_sync = '0' then
                        state      <= START;
                        baud_count <= HALF_BIT_TICKS;  -- sample in middle of start bit
                    end if;

                when START =>
                    if baud_count = 0 then
                        -- Confirm still low; move to data reception
                        if midi_sync = '0' then
                            state      <= DATA;
                            baud_count <= BIT_TICKS - 1;
                            bit_index  <= 0;
                        else
                            state <= IDLE;  -- false start
                        end if;
                    else
                        baud_count <= baud_count - 1;
                    end if;

                when DATA =>
                    if baud_count = 0 then
                        shift_reg(bit_index) <= midi_sync;
                        baud_count <= BIT_TICKS - 1;

                        if bit_index = 7 then
                            state <= STOP;
                        else
                            bit_index <= bit_index + 1;
                        end if;
                    else
                        baud_count <= baud_count - 1;
                    end if;

                when STOP =>
                    if baud_count = 0 then
                        -- Sample stop bit; accept byte only if high
                        if midi_sync = '1' then
                            data_byte_i  <= shift_reg;
                            data_valid_i <= '1';
                        end if;
                        state <= IDLE;
                    else
                        baud_count <= baud_count - 1;
                    end if;
            end case;
        end if;
    end process;

    data_byte  <= data_byte_i;
    data_valid <= data_valid_i;

end architecture rtl;
