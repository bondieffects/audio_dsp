library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- Create a simple counter with different bit widths
entity week1 is
    port (
        clk_50mhz : in std_logic;
        reset_n   : in std_logic;
        count_8   : out std_logic_vector(7 downto 0);
        count_16  : out std_logic_vector(15 downto 0);
        count_24  : out std_logic_vector(23 downto 0)
    );
end entity;

architecture behavioral of week1 is
    -- Use unsigned for internal signals to enable arithmetic operations
    signal counter_8  : unsigned(7 downto 0);
    signal counter_16 : unsigned(15 downto 0);
    signal counter_24 : unsigned(23 downto 0);
begin

    process(clk_50mhz, reset_n)
    begin
        if reset_n = '0' then
            counter_8  <= (others => '0');
            counter_16 <= (others => '0');
            counter_24 <= (others => '0');
        elsif rising_edge(clk_50mhz) then
            -- Arithmetic operations work directly with unsigned
            counter_8  <= counter_8 + 1;
            counter_16 <= counter_16 + 1;
            counter_24 <= counter_24 + 1;
        end if;
    end process;

    -- Type conversion: unsigned internal signals to std_logic_vector outputs
    count_8  <= std_logic_vector(counter_8);
    count_16 <= std_logic_vector(counter_16);
    count_24 <= std_logic_vector(counter_24);

end architecture;

-- Learning Tasks:
-- Implement counters of different widths (8, 16, 24 bits)
-- Compile and analyze timing reports
-- Identify which counter creates the longest critical path
-- Document relationship between logic depth and timing
-- Key Observations to Make:
-- How does counter width affect maximum frequency (Fmax)?
-- Which paths appear in the "Slow 1200mV 85C Model" timing report?
-- What's the difference between setup and hold slack?
