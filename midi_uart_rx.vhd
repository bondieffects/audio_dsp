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
    -- ========================================================================
    -- Baud Rate Constants
    -- ========================================================================
    -- MIDI standard baud rate: 31.25 kBd
    -- Clock cycles per bit: 50 MHz / 31.25 kBd = 1600 clock full period
    -- Sample at the half-bit for more reliable sampling: 800 clock half period
    constant BIT_TICKS      : integer := 1600;
    constant HALF_BIT_TICKS : integer := BIT_TICKS / 2;

    -- ========================================================================
    -- State Machine Definition
    -- ========================================================================
    -- IDLE  : Waiting for start bit (falling edge on midi_sync)
    -- START : Sampling mid-point of start bit to confirm valid transmission
    -- DATA  : Receiving 8 data bits (LSB first per UART protocol)
    -- STOP  : Sampling stop bit to validate frame completion
    type rx_state_t is (IDLE, START, DATA, STOP);
    
    -- ========================================================================
    -- Internal Signals
    -- ========================================================================
    signal state       : rx_state_t := IDLE;              -- Current state of RX FSM
    signal baud_count  : integer range 0 to BIT_TICKS := 0; -- Clock divider for bit timing
    signal bit_index   : integer range 0 to 7 := 0;       -- Tracks which bit (0-7) is being received
    signal shift_reg   : std_logic_vector(7 downto 0) := (others => '0'); -- Accumulates incoming bits
    signal data_valid_i: std_logic := '0';                -- Internal data valid flag
    signal data_byte_i : std_logic_vector(7 downto 0) := (others => '0'); -- Internal received byte
    signal midi_sync   : std_logic := '1';                -- Synchronized MIDI input (safe to use)
    signal midi_meta   : std_logic := '1';                -- Metastability buffer stage
begin

    -- ========================================================================
    -- Input Synchronizer Process
    -- ========================================================================
    -- Two-stage flip-flop synchronizer to safely cross clock domains.
    -- MIDI input is asynchronous to the 50 MHz system clock, so direct use
    -- could cause metastability. This chain gives any metastable state time
    -- to resolve before being used by the receiver state machine.
    -- Default idle state is '1' (UART idle high).
    process(clk, reset_n)
    begin
        if reset_n = '0' then
            midi_meta <= '1';  -- First stage: capture async input
            midi_sync <= '1';  -- Second stage: stable synchronized output
        elsif rising_edge(clk) then
            midi_meta <= midi_in;      -- Stage 1: may be metastable
            midi_sync <= midi_meta;    -- Stage 2: metastability resolved
        end if;
    end process;

    -- ========================================================================
    -- UART Receiver State Machine
    -- ========================================================================
    -- Implements a standard 8-N-1 UART receiver (8 data bits, no parity, 1 stop bit)
    -- optimized for the MIDI protocol (31.25 kbps).
    -- 
    -- Timing strategy:
    --   - Start bit: Sample at mid-point (800 clocks) to confirm valid '0'
    --   - Data bits: Sample at center of each bit period (every 1600 clocks)
    --   - Stop bit: Sample at center to validate frame with expected '1'
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
            -- Clear data_valid by default (only high for 1 cycle when byte received)
            data_valid_i <= '0';

            case state is
                -- ============================================================
                -- IDLE: Wait for start bit
                -- ============================================================
                -- UART idle state is high ('1'). A falling edge to '0' 
                -- indicates the start bit of a new frame.
                when IDLE =>
                    if midi_sync = '0' then
                        state      <= START;
                        baud_count <= HALF_BIT_TICKS;  -- Wait half a bit period to sample mid-point
                    end if;

                -- ============================================================
                -- START: Validate start bit
                -- ============================================================
                -- Sample the start bit at its center to confirm it's still low.
                -- This helps reject glitches or noise that might look like a start bit.
                when START =>
                    if baud_count = 0 then
                        if midi_sync = '0' then
                            -- Valid start bit confirmed, begin receiving data
                            state      <= DATA;
                            baud_count <= BIT_TICKS - 1;  -- Full bit period for data bits
                            bit_index  <= 0;              -- Start with LSB (bit 0)
                        else
                            -- False start detected (glitch), return to idle
                            state <= IDLE;
                        end if;
                    else
                        baud_count <= baud_count - 1;
                    end if;

                -- ============================================================
                -- DATA: Receive 8 data bits (LSB first)
                -- ============================================================
                -- Sample each bit at its center, storing into shift register.
                -- UART protocol transmits LSB first, so bit 0 arrives before bit 7.
                when DATA =>
                    if baud_count = 0 then
                        -- Sample current bit at center of bit period
                        shift_reg(bit_index) <= midi_sync;
                        baud_count <= BIT_TICKS - 1;  -- Reset counter for next bit

                        if bit_index = 7 then
                            -- All 8 bits received, move to stop bit
                            state <= STOP;
                        else
                            -- More bits to receive
                            bit_index <= bit_index + 1;
                        end if;
                    else
                        baud_count <= baud_count - 1;
                    end if;

                -- ============================================================
                -- STOP: Validate stop bit and output byte
                -- ============================================================
                -- Stop bit should be high ('1'). If valid, output the received
                -- byte with a one-cycle strobe on data_valid.
                when STOP =>
                    if baud_count = 0 then
                        if midi_sync = '1' then
                            -- Valid stop bit: frame successfully received
                            data_byte_i  <= shift_reg;
                            data_valid_i <= '1';  -- Pulse for one clock cycle
                        end if;
                        -- Invalid stop bit is silently discarded (no error flag)
                        -- Return to idle to await next frame
                        state <= IDLE;
                    else
                        baud_count <= baud_count - 1;
                    end if;
            end case;
        end if;
    end process;

    -- ========================================================================
    -- Output Assignment
    -- ========================================================================
    -- Drive external ports with internal signals
    data_byte  <= data_byte_i;   -- 8-bit received byte
    data_valid <= data_valid_i;  -- Single-cycle strobe when new byte available

end architecture rtl;
