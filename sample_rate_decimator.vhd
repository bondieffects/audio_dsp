library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- ============================================================================
-- Runtime-configurable sample rate decimator
-- ============================================================================
-- Holds incoming samples and only updates the output every Nth valid input
-- sample, where N is provided on the decimation_factor input. A value of 1
-- bypasses the decimation (every sample passes through).
-- ============================================================================
entity sample_rate_decimator is
    generic (
        IN_WIDTH      : integer := 16;
        COUNTER_WIDTH : integer := 6  -- supports factors up to 64 (2^6)
    );
    port (
        clk               : in  std_logic;
        reset_n           : in  std_logic;
        sample_in         : in  std_logic_vector(IN_WIDTH - 1 downto 0);
        sample_valid      : in  std_logic;
        decimation_factor : in  unsigned(6 downto 0);  -- expected 1..64
        sample_out        : out std_logic_vector(IN_WIDTH - 1 downto 0)
    );
end entity sample_rate_decimator;

architecture rtl of sample_rate_decimator is
    constant FACTOR_MIN : integer := 1;
    constant FACTOR_MAX : integer := 64;

    signal hold_reg : signed(IN_WIDTH - 1 downto 0) := (others => '0');
    signal counter  : unsigned(COUNTER_WIDTH - 1 downto 0) := (others => '0');
begin
    process(clk, reset_n)
        variable factor_int   : integer;
        variable reload_value : unsigned(COUNTER_WIDTH - 1 downto 0);
    begin
        if reset_n = '0' then
            hold_reg <= (others => '0');
            counter  <= (others => '0');
        elsif rising_edge(clk) then
            if sample_valid = '1' then
                factor_int := to_integer(decimation_factor);
                if factor_int < FACTOR_MIN then
                    factor_int := FACTOR_MIN;
                elsif factor_int > FACTOR_MAX then
                    factor_int := FACTOR_MAX;
                end if;

                if factor_int = 1 then
                    hold_reg <= signed(sample_in);
                    counter  <= (others => '0');
                else
                    reload_value := to_unsigned(factor_int - 1, counter'length);

                    if counter = to_unsigned(0, counter'length) or counter > reload_value then
                        hold_reg <= signed(sample_in);
                        counter  <= reload_value;
                    else
                        counter <= counter - 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    sample_out <= std_logic_vector(hold_reg);
end architecture rtl;
