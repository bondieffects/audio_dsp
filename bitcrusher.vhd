library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- ============================================================================
-- Runtime-configurable bitcrusher
-- ============================================================================
-- Quantises the input sample to the number of bits specified on 'bit_depth'.
-- bit_depth values outside the range 1..IN_WIDTH are clamped.
-- ============================================================================
entity bitcrusher is
    generic (
        IN_WIDTH : integer := 16
    );
    port (
        sample_in  : in  std_logic_vector(IN_WIDTH - 1 downto 0);
        bit_depth  : in  unsigned(4 downto 0);  -- supports up to 31 bits, clamp to IN_WIDTH
        sample_out : out std_logic_vector(IN_WIDTH - 1 downto 0)
    );
end entity bitcrusher;

architecture rtl of bitcrusher is
begin
    process(sample_in, bit_depth)
        variable working_sample : signed(IN_WIDTH - 1 downto 0);
        variable target_bits    : integer;
        variable shift_amt      : integer;
        variable quantised      : signed(IN_WIDTH - 1 downto 0);
    begin
        working_sample := signed(sample_in);
        target_bits    := to_integer(bit_depth);

        if target_bits > IN_WIDTH then
            target_bits := IN_WIDTH;
        elsif target_bits < 1 then
            target_bits := 1;
        end if;

        shift_amt := IN_WIDTH - target_bits;

        if shift_amt <= 0 then
            quantised := working_sample;
        else
            quantised := shift_left(shift_right(working_sample, shift_amt), shift_amt);
        end if;

        sample_out <= std_logic_vector(quantised);
    end process;
end architecture rtl;
