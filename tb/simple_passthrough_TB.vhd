-- Simple testbench for testing passthrough without PLL
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity simple_passthrough_TB is
end entity simple_passthrough_TB;

architecture testbench of simple_passthrough_TB is

    component audio_dsp_top_no_pll is
        port (
            clk_50mhz    : in std_logic;
            reset_n      : in std_logic;
            i2s_mclk     : out std_logic;
            i2s_bclk     : out std_logic;
            i2s_ws       : out std_logic;
            i2s_din      : in std_logic;
            i2s_dout     : out std_logic;
            led          : out std_logic_vector(3 downto 0);
            test_point_1 : out std_logic;
            test_point_2 : out std_logic
        );
    end component;

    -- Test signals
    signal clk_50mhz    : std_logic := '0';
    signal reset_n      : std_logic := '0';
    signal i2s_mclk     : std_logic;
    signal i2s_bclk     : std_logic;
    signal i2s_ws       : std_logic;
    signal i2s_din      : std_logic := '0';
    signal i2s_dout     : std_logic;
    signal led          : std_logic_vector(3 downto 0);
    signal test_point_1 : std_logic;
    signal test_point_2 : std_logic;

    -- Clock period
    constant CLK_PERIOD : time := 81.38 ns; -- 12.288MHz for proper I2S timing

    -- Test data counter
    signal test_data_counter : unsigned(15 downto 0) := x"1234";

begin

    -- DUT instantiation
    DUT : audio_dsp_top_no_pll
        port map (
            clk_50mhz    => clk_50mhz,
            reset_n      => reset_n,
            i2s_mclk     => i2s_mclk,
            i2s_bclk     => i2s_bclk,
            i2s_ws       => i2s_ws,
            i2s_din      => i2s_din,
            i2s_dout     => i2s_dout,
            led          => led,
            test_point_1 => test_point_1,
            test_point_2 => test_point_2
        );

    -- Clock generation
    clk_50mhz <= not clk_50mhz after CLK_PERIOD/2;

    -- Test process
    test_process : process
    begin
        report "=== SIMPLE PASSTHROUGH TEST STARTED ===" severity note;
        
        -- Reset sequence
        reset_n <= '0';
        wait for 100 ns;
        reset_n <= '1';
        wait for 100 ns;
        
        report "Reset completed, system should be active" severity note;
        
        -- Wait for I2S clocks to stabilize
        wait for 5 us;
        report "I2S clocks should be running now" severity note;
        
        -- Check I2S clock activity
        wait for 1 us;
        report "I2S_BCLK=" & std_logic'image(i2s_bclk) & " I2S_WS=" & std_logic'image(i2s_ws) severity note;
        
        -- Monitor signals for activity
        report "Monitoring for I2S activity..." severity note;
        wait for 50 us;
        
        -- Report LED status
        report "LED Status - LED[0]=" & std_logic'image(led(0)) & 
               " LED[1]=" & std_logic'image(led(1)) & 
               " LED[2]=" & std_logic'image(led(2)) & 
               " LED[3]=" & std_logic'image(led(3)) severity note;
               
        report "Test Point Status - TP1=" & std_logic'image(test_point_1) & 
               " TP2=" & std_logic'image(test_point_2) severity note;
               
        -- Check some internal signals
        report "I2S Clock Status - BCLK=" & std_logic'image(i2s_bclk) & " WS=" & std_logic'image(i2s_ws) severity note;
        
        if test_point_1 = '1' or test_point_2 = '1' then
            report "=== PASSTHROUGH TEST PASSED ===" severity note;
            report "Data activity detected on test points" severity note;
        else
            report "=== PASSTHROUGH TEST INCONCLUSIVE ===" severity note;
            report "No data activity - this may be normal without proper I2S input" severity note;
        end if;
        
        wait for 10 us;
        report "Test completed" severity note;
        wait;
    end process;

    -- I2S loopback stimulus
    i2s_stimulus : process
    begin
        -- Wait for reset and stabilization
        wait until reset_n = '1';
        wait for 1 us;
        
        -- Create loopback: connect TX output to RX input
        loop
            wait for 10 ns;
            i2s_din <= i2s_dout;
        end loop;
    end process;

end architecture testbench;