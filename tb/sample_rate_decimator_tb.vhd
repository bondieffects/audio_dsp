library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use std.env.all;

entity sample_rate_decimator_tb is
end entity sample_rate_decimator_tb;

architecture sim of sample_rate_decimator_tb is
    constant IN_WIDTH          : integer := 16;
    constant DECIMATION_FACTOR : integer := 3;

    signal clk          : std_logic := '0';
    signal reset_n      : std_logic := '0';
    signal sample_in    : std_logic_vector(IN_WIDTH - 1 downto 0) := (others => '0');
    signal sample_valid : std_logic := '0';
    signal sample_out   : std_logic_vector(IN_WIDTH - 1 downto 0);

    constant CLK_PERIOD : time := 10 ns;
begin
    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.sample_rate_decimator
        generic map (
            IN_WIDTH          => IN_WIDTH,
            DECIMATION_FACTOR => DECIMATION_FACTOR
        )
        port map (
            clk          => clk,
            reset_n      => reset_n,
            sample_in    => sample_in,
            sample_valid => sample_valid,
            sample_out   => sample_out
        );

    stimulus : process
        variable expected_value : signed(IN_WIDTH - 1 downto 0) := (others => '0');
        variable last_value     : signed(IN_WIDTH - 1 downto 0) := (others => '0');
    begin
        reset_n <= '0';
        wait for 3 * CLK_PERIOD;
        reset_n <= '1';
        wait for CLK_PERIOD;

        for idx in 0 to 11 loop
            sample_in <= std_logic_vector(to_signed(idx * 512 - 4096, IN_WIDTH));
            sample_valid <= '1';
            wait until rising_edge(clk);
            sample_valid <= '0';
            wait for CLK_PERIOD / 4; -- allow combinational settle

            if (idx mod DECIMATION_FACTOR) = 0 then
                expected_value := to_signed(idx * 512 - 4096, IN_WIDTH);
                last_value := expected_value;
            end if;

            assert sample_out = std_logic_vector(last_value)
                report "Decimation output mismatch at sample " & integer'image(idx)
                severity error;

            wait for CLK_PERIOD / 2;
        end loop;

    report "Sample rate decimator test complete" severity note;
    std.env.stop;
    wait;
    end process;
end architecture sim;
