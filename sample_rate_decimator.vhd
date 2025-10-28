library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- ============================================================================
-- Sample Rate Decimator
-- ============================================================================
-- Purpose:
--   Reduces the effective sample rate by holding samples and only updating
--   the output every Nth valid input sample.
--
-- Operation:
--   - When a sample_valid pulse arrives, the internal counter is decremented
--   - When the counter reaches 0, the input sample is latched to the output
--     and the counter reloads to (decimation_factor - 1)
--   - All other samples are discarded (output remains unchanged)
--
-- Examples:
--   decimation_factor = 1  →  bypass mode (every sample passes through)
--   decimation_factor = 2  →  output updates every 2nd sample (half rate)
--   decimation_factor = 4  →  output updates every 4th sample (quarter rate)
--
-- Use Case:
--   Audio bitcrushing effect - reducing sample rate creates aliasing artifacts
--   and a characteristic "lo-fi" sound quality.
-- ============================================================================
entity sample_rate_decimator is
    generic (
        IN_WIDTH      : integer := 16;  -- bit width of audio samples
        COUNTER_WIDTH : integer := 6    -- supports decimation factors up to 2^6 = 64
    );
    port (
        clk               : in  std_logic;                           -- system clock
        reset_n           : in  std_logic;                           -- active-low reset
        sample_in         : in  std_logic_vector(IN_WIDTH - 1 downto 0);  -- incoming audio sample
        sample_valid      : in  std_logic;                           -- strobe indicating valid input sample
        decimation_factor : in  unsigned(6 downto 0);                -- 1..64: output updates every Nth sample
        sample_out        : out std_logic_vector(IN_WIDTH - 1 downto 0)   -- held/decimated output sample
    );
end entity sample_rate_decimator;

architecture rtl of sample_rate_decimator is
    constant FACTOR_MIN : integer := 1;   -- minimum decimation (bypass)
    constant FACTOR_MAX : integer := 64;  -- maximum decimation factor

    -- Output register: holds the last accepted sample
    signal hold_reg : signed(IN_WIDTH - 1 downto 0) := (others => '0');
    
    -- Downcounter: tracks when to accept the next sample
    signal counter  : unsigned(COUNTER_WIDTH - 1 downto 0) := (others => '0');
begin
    -- ========================================================================
    -- Main decimation logic
    -- ========================================================================
    process(clk, reset_n)
        variable factor_int   : integer;
        variable reload_value : unsigned(COUNTER_WIDTH - 1 downto 0);
    begin
        if reset_n = '0' then
            hold_reg <= (others => '0');
            counter  <= (others => '0');
            
        elsif rising_edge(clk) then
            if sample_valid = '1' then
                -- Clamp decimation factor to valid range
                factor_int := to_integer(decimation_factor);
                if factor_int < FACTOR_MIN then
                    factor_int := FACTOR_MIN;
                elsif factor_int > FACTOR_MAX then
                    factor_int := FACTOR_MAX;
                end if;

                if factor_int = 1 then
                    -- Bypass mode: every sample passes through immediately
                    hold_reg <= signed(sample_in);
                    counter  <= (others => '0');
                else
                    -- Decimation mode: use counter to determine when to update
                    reload_value := to_unsigned(factor_int - 1, counter'length);

                    -- Accept sample when counter reaches 0, otherwise decrement
                    if counter = to_unsigned(0, counter'length) or counter > reload_value then
                        hold_reg <= signed(sample_in);  -- latch new sample
                        counter  <= reload_value;       -- reload counter for next cycle
                    else
                        -- Reject this sample, just decrement counter
                        counter <= counter - 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Output is always the held register value
    sample_out <= std_logic_vector(hold_reg);
end architecture rtl;
