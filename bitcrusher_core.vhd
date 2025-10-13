library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- ============================================================================
-- Bitcrusher core: quantizes signed samples down to a target bit depth
-- ============================================================================
entity bitcrusher_core is
    generic (
        IN_WIDTH    : integer := 16;
        TARGET_BITS : integer := 8
    );
    port (
        sample_in  : in  std_logic_vector(IN_WIDTH - 1 downto 0);
        sample_out : out std_logic_vector(IN_WIDTH - 1 downto 0)
    );
end entity bitcrusher_core;

architecture rtl of bitcrusher_core is
    signal quantized : signed(IN_WIDTH - 1 downto 0);
begin
    -- Mask out the lower bits by arithmetic shifting to maintain sign
    process(sample_in)
        variable working_sample : signed(IN_WIDTH - 1 downto 0);
        variable shift_amt      : integer;
    begin
        working_sample := signed(sample_in);
        shift_amt      := IN_WIDTH - TARGET_BITS;

        if TARGET_BITS >= IN_WIDTH then
            quantized <= working_sample;
        elsif TARGET_BITS <= 0 then
            quantized <= (others => '0');
        else
            quantized <= shift_left(shift_right(working_sample, shift_amt), shift_amt);
        end if;
    end process;

    sample_out <= std_logic_vector(quantized);
end architecture rtl;
