library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity midi_control_tb is
end entity midi_control_tb;

architecture tb of midi_control_tb is
    constant CLK_PERIOD : time := 20 ns; -- 50 MHz

    signal clk              : std_logic := '0';
    signal reset_n          : std_logic := '0';

    -- MIDI parser interface
    signal data_byte        : std_logic_vector(7 downto 0) := (others => '0');
    signal data_valid       : std_logic := '0';
    signal bit_depth_value  : unsigned(4 downto 0);
    signal decimation_value : unsigned(6 downto 0);

    -- Audio processing path
    signal sample_in        : std_logic_vector(15 downto 0) := (others => '0');
    signal sample_valid     : std_logic := '0';
    signal crushed_sample   : std_logic_vector(15 downto 0);
    signal decimated_sample : std_logic_vector(15 downto 0);

    constant SAMPLE_PASSTHROUGH : signed(15 downto 0) := to_signed(16#7A5C#, 16);
    constant SAMPLE_QUANTIZE    : signed(15 downto 0) := to_signed(16#1234#, 16);

begin
    -- Generate 50 MHz clock
    clk <= not clk after CLK_PERIOD / 2;

    -- DUT instantiations
    u_parser : entity work.midi_parser
        port map (
            clk              => clk,
            reset_n          => reset_n,
            data_byte        => data_byte,
            data_valid       => data_valid,
            bit_depth_value  => bit_depth_value,
            decimation_value => decimation_value
        );

    u_bitcrusher : entity work.bitcrusher
        generic map (
            IN_WIDTH => 16
        )
        port map (
            sample_in  => sample_in,
            bit_depth  => bit_depth_value,
            sample_out => crushed_sample
        );

    u_decimator : entity work.sample_rate_decimator
        generic map (
            IN_WIDTH      => 16,
            COUNTER_WIDTH => 6
        )
        port map (
            clk               => clk,
            reset_n           => reset_n,
            sample_in         => crushed_sample,
            sample_valid      => sample_valid,
            decimation_factor => decimation_value,
            sample_out        => decimated_sample
        );

    stimulus : process
        procedure send_byte(constant b : in std_logic_vector(7 downto 0)) is
        begin
            data_byte  <= b;
            data_valid <= '1';
            wait for CLK_PERIOD;
            data_valid <= '0';
            wait for CLK_PERIOD;
        end procedure;

        variable expected_hold : signed(15 downto 0) := (others => '0');
        variable expected_crushed : signed(15 downto 0);
    begin
        -- Apply reset
        reset_n <= '0';
        wait for 5 * CLK_PERIOD;
        reset_n <= '1';
        wait for 5 * CLK_PERIOD;

        -- Control Change #20 value 0 -> expect bit depth = 1
        send_byte(x"B0");
        send_byte(std_logic_vector(to_unsigned(20, 8)));
        send_byte(std_logic_vector(to_unsigned(0, 8)));
        wait for 4 * CLK_PERIOD;
        assert bit_depth_value = to_unsigned(1, bit_depth_value'length)
            report "Bit depth mapping for value 0 failed" severity error;

        -- CC #20 value 127 -> expect bit depth = 16
        send_byte(std_logic_vector(to_unsigned(20, 8)));
        send_byte(std_logic_vector(to_unsigned(127, 8)));
        wait for 4 * CLK_PERIOD;
        assert bit_depth_value = to_unsigned(16, bit_depth_value'length)
            report "Bit depth mapping for value 127 failed" severity error;

        -- CC #21 value 127 -> expect decimation = 64
        send_byte(std_logic_vector(to_unsigned(21, 8)));
        send_byte(std_logic_vector(to_unsigned(127, 8)));
        wait for 4 * CLK_PERIOD;
        assert decimation_value = to_unsigned(64, decimation_value'length)
            report "Decimation mapping for value 127 failed" severity error;

        -- CC #21 value 1 -> expect decimation = 1 (bypass)
        send_byte(std_logic_vector(to_unsigned(21, 8)));
        send_byte(std_logic_vector(to_unsigned(1, 8)));
        wait for 4 * CLK_PERIOD;
        assert decimation_value = to_unsigned(1, decimation_value'length)
            report "Decimation mapping for value 1 failed" severity error;

        -- Verify bitcrusher operates as passthrough when depth = 16
        sample_in <= std_logic_vector(SAMPLE_PASSTHROUGH);
        wait for CLK_PERIOD;
        assert signed(crushed_sample) = SAMPLE_PASSTHROUGH
            report "Bitcrusher failed to passthrough at 16-bit depth" severity error;

        -- Reduce bit depth: CC #20 value 30 -> expect bit depth = 4
        send_byte(std_logic_vector(to_unsigned(20, 8)));
        send_byte(std_logic_vector(to_unsigned(30, 8)));
        wait for 4 * CLK_PERIOD;
        assert bit_depth_value = to_unsigned(4, bit_depth_value'length)
            report "Bit depth mapping for value 30 failed" severity error;

    sample_in <= std_logic_vector(SAMPLE_QUANTIZE);
        wait for CLK_PERIOD;
    expected_crushed := shift_left(shift_right(SAMPLE_QUANTIZE, 12), 12);
        assert signed(crushed_sample) = expected_crushed
            report "Bitcrusher quantisation mismatch at 4-bit depth" severity error;

        -- Restore full resolution so the decimator ramp can check pass-through behaviour
        send_byte(std_logic_vector(to_unsigned(20, 8)));
        send_byte(std_logic_vector(to_unsigned(127, 8)));
        wait for 4 * CLK_PERIOD;

        -- Configure decimator for factor = 4 (CC #21 value 7)
        send_byte(std_logic_vector(to_unsigned(21, 8)));
        send_byte(std_logic_vector(to_unsigned(7, 8)));
        wait for 4 * CLK_PERIOD;
        assert decimation_value = to_unsigned(4, decimation_value'length)
            report "Decimation mapping for value 7 failed" severity error;

        -- Feed a ramp and check the decimator output updates every fourth sample
        expected_hold := (others => '0');
        for i in 0 to 7 loop
            sample_in    <= std_logic_vector(to_signed(i, sample_in'length));
            sample_valid <= '1';
            wait for CLK_PERIOD;
            sample_valid <= '0';
            wait for CLK_PERIOD;

            if (i mod 4) = 0 then
                expected_hold := to_signed(i, expected_hold'length);
            end if;
            wait for CLK_PERIOD;
            assert signed(decimated_sample) = expected_hold
                report "Decimator output unexpected at sample " & integer'image(i)
                severity error;
        end loop;

    report "midi_control_tb completed successfully" severity note;
    wait;
    end process;

end architecture tb;
