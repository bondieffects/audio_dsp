library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- ============================================================================
-- Sample rate decimator: holds input sample and only updates every Nth valid
-- sample. Designed for streaming audio paths where new samples arrive with a
-- "sample_valid" strobe.
-- ============================================================================
entity sample_rate_decimator is
    generic (
        IN_WIDTH          : integer := 16;
        DECIMATION_FACTOR : integer := 2
    );
    port (
        clk          : in  std_logic;
        reset_n      : in  std_logic;
        sample_in    : in  std_logic_vector(IN_WIDTH - 1 downto 0);
        sample_valid : in  std_logic;
        sample_out   : out std_logic_vector(IN_WIDTH - 1 downto 0)
    );
end entity sample_rate_decimator;

architecture rtl of sample_rate_decimator is
    function counter_reload(factor : integer) return integer is
    begin
        if factor <= 1 then
            return 0;
        else
            return factor - 1;
        end if;
    end function;

    constant COUNTER_RESET_VALUE : integer := counter_reload(DECIMATION_FACTOR);
    signal hold_reg             : signed(IN_WIDTH - 1 downto 0) := (others => '0');
    signal counter              : integer range 0 to COUNTER_RESET_VALUE := 0;
begin
    process(clk, reset_n)
    begin
        if reset_n = '0' then
            hold_reg <= (others => '0');
            counter  <= 0;
        elsif rising_edge(clk) then
            if sample_valid = '1' then
                if DECIMATION_FACTOR <= 1 then
                    hold_reg <= signed(sample_in);
                    counter  <= 0;
                else
                    if counter = 0 then
                        hold_reg <= signed(sample_in);
                        counter  <= COUNTER_RESET_VALUE;
                    else
                        counter <= counter - 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    sample_out <= std_logic_vector(hold_reg);
end architecture rtl;
