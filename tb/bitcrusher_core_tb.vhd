library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity bitcrusher_core_tb is
end entity bitcrusher_core_tb;

architecture sim of bitcrusher_core_tb is
    constant IN_WIDTH    : integer := 16;
    constant TARGET_BITS : integer := 6;
    signal sample_in     : std_logic_vector(IN_WIDTH - 1 downto 0) := (others => '0');
    signal sample_out    : std_logic_vector(IN_WIDTH - 1 downto 0);

    constant SHIFT : integer := IN_WIDTH - TARGET_BITS;
begin
    dut : entity work.bitcrusher_core
        generic map (
            IN_WIDTH    => IN_WIDTH,
            TARGET_BITS => TARGET_BITS
        )
        port map (
            sample_in  => sample_in,
            sample_out => sample_out
        );

    stimulus : process
        variable src      : signed(IN_WIDTH - 1 downto 0);
        variable expected : signed(IN_WIDTH - 1 downto 0);
    begin
        -- Sweep representative values across the full dynamic range
        for idx in 0 to 255 loop
            src := to_signed(-32768 + idx * 256, IN_WIDTH);
            sample_in <= std_logic_vector(src);
            wait for 10 ns;

            if TARGET_BITS >= IN_WIDTH then
                expected := src;
            elsif TARGET_BITS <= 0 then
                expected := (others => '0');
            else
                expected := shift_left(shift_right(src, SHIFT), SHIFT);
            end if;

            assert sample_out = std_logic_vector(expected)
                report "Quantization mismatch for input " & integer'image(to_integer(src))
                severity error;
        end loop;

        -- Focused checks around zero to catch sign handling
        for val in -16 to 16 loop
            src := to_signed(val, IN_WIDTH);
            sample_in <= std_logic_vector(src);
            wait for 10 ns;

            if TARGET_BITS >= IN_WIDTH then
                expected := src;
            elsif TARGET_BITS <= 0 then
                expected := (others => '0');
            else
                expected := shift_left(shift_right(src, SHIFT), SHIFT);
            end if;

            assert sample_out = std_logic_vector(expected)
                report "Quantization mismatch near zero for input " & integer'image(val)
                severity error;
        end loop;

        report "Bitcrusher core test complete" severity note;
        wait;
    end process;
end architecture sim;
