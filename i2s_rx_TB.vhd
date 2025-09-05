-- LIBRARIES and PACKAGES for i2s_rx_TB
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity i2s_rx_TB is
end entity;

-- Test bench for I2S Receiver module
architecture i2s_rx_TB_arch of i2s_rx_TB is

    -- Clock timing constants
    constant BCLK_HALF_PERIOD : time := 325 ns;  -- 1.536 MHz BCLK (period = 650ns)
    constant WS_HALF_PERIOD : time := 10416 ns;  -- 48 kHz WS (period = 20.833us)

    -- Component declaration for DUT
    component i2s_rx
        port (
            -- Clock and reset
            i2s_bclk : in std_logic;
            i2s_ws   : in std_logic;
            reset_n  : in std_logic;

            -- I2S Serial Input (ADC DATA)
            i2s_sdata : in std_logic;

            -- Parallel Audio Output (16-bit samples)
            audio_left  : out std_logic_vector(15 downto 0);
            audio_right : out std_logic_vector(15 downto 0);
            audio_valid : out std_logic
        );
    end component;

    -- Signal declarations
    signal i2s_bclk_TB : std_logic := '0';
    signal i2s_ws_TB : std_logic := '0';
    signal reset_n_TB : std_logic := '0';
    signal i2s_sdata_TB : std_logic := '0';
    signal audio_left_TB : std_logic_vector(15 downto 0);
    signal audio_right_TB : std_logic_vector(15 downto 0);
    signal audio_valid_TB : std_logic;

    -- Test data
    constant TEST_LEFT_DATA : std_logic_vector(15 downto 0) := "1010101010101010";   -- 0xAAAA
    constant TEST_RIGHT_DATA : std_logic_vector(15 downto 0) := "0101010101010101";  -- 0x5555

begin

    -- DUT instantiation
    DUT1: i2s_rx
        port map (
            i2s_bclk => i2s_bclk_TB,
            i2s_ws => i2s_ws_TB,
            reset_n => reset_n_TB,
            i2s_sdata => i2s_sdata_TB,
            audio_left => audio_left_TB,
            audio_right => audio_right_TB,
            audio_valid => audio_valid_TB
        );

    -- BCLK Generation Process
    BCLK_GEN: process
    begin
        -- Wait for reset release
        wait until reset_n_TB = '1';
        wait for 50 ns;  -- Small delay after reset
        
        -- Generate continuous BCLK
        for i in 0 to 10000 loop  -- Generate enough clocks for multiple samples
            i2s_bclk_TB <= '1';
            wait for BCLK_HALF_PERIOD;
            i2s_bclk_TB <= '0';
            wait for BCLK_HALF_PERIOD;
        end loop;
        
        report "BCLK generation complete" severity note;
        wait;
    end process;

    -- Word Select (WS) Generation Process
    WS_GEN: process
    begin
        -- Wait for reset release
        wait until reset_n_TB = '1';
        wait for 100 ns;  -- Small delay after reset
        
        -- Generate WS signal (48kHz)
        for i in 0 to 20 loop  -- Generate multiple WS cycles
            -- Left channel (WS = '0')
            i2s_ws_TB <= '0';
            wait for WS_HALF_PERIOD;
            
            -- Right channel (WS = '1')
            i2s_ws_TB <= '1';
            wait for WS_HALF_PERIOD;
        end loop;
        
        report "WS generation complete" severity note;
        wait;
    end process;

    -- I2S Serial Data Generation Process
    SDATA_GEN: process
        variable bit_index : integer;
        variable current_data : std_logic_vector(15 downto 0);
    begin
        -- Initialize
        i2s_sdata_TB <= '0';
        
        -- Wait for reset release and clocks to start
        wait until reset_n_TB = '1';
        wait for 200 ns;
        
        -- Generate test data for multiple samples
        for sample in 0 to 10 loop
            -- Wait for WS falling edge (start of left channel)
            wait until falling_edge(i2s_ws_TB);
            wait until rising_edge(i2s_bclk_TB);  -- Sync to BCLK
            
            -- Send left channel data (MSB first)
            current_data := TEST_LEFT_DATA;
            for bit_index in 15 downto 0 loop
                i2s_sdata_TB <= current_data(bit_index);
                wait until rising_edge(i2s_bclk_TB);
            end loop;
            
            -- Wait for WS rising edge (start of right channel)
            wait until rising_edge(i2s_ws_TB);
            wait until rising_edge(i2s_bclk_TB);  -- Sync to BCLK
            
            -- Send right channel data (MSB first)
            current_data := TEST_RIGHT_DATA;
            for bit_index in 15 downto 0 loop
                i2s_sdata_TB <= current_data(bit_index);
                wait until rising_edge(i2s_bclk_TB);
            end loop;
        end loop;
        
        report "Serial data generation complete" severity note;
        wait;
    end process;

    -- Reset and Stimulus Control Process
    STIMULUS: process
    begin
        -- Initialize signals
        reset_n_TB <= '0';
        wait for 200 ns;    -- Hold reset for 200 ns

        reset_n_TB <= '1';  -- Release reset
        report "Reset released - test starting" severity note;

        -- Let the test run
        wait for 5 ms;      -- Run for 5ms to capture multiple samples
        
        report "Test stimulus complete" severity note;
        wait;
    end process;

    -- Output Monitoring Process
    MONITOR: process
        variable left_received : std_logic_vector(15 downto 0);
        variable right_received : std_logic_vector(15 downto 0);
        variable sample_count : integer := 0;
    begin
        -- Wait for reset release
        wait until reset_n_TB = '1';
        report "Reset released - monitoring started" severity note;

        -- Monitor audio_valid and check received data
        while sample_count < 5 loop  -- Monitor first 5 complete samples
            wait until rising_edge(audio_valid_TB);
            
            left_received := audio_left_TB;
            right_received := audio_right_TB;
            sample_count := sample_count + 1;
            
            -- Check if received data matches expected
            if left_received = TEST_LEFT_DATA and right_received = TEST_RIGHT_DATA then
                report "Sample " & integer'image(sample_count) & " PASS - Left: 0x" & 
                       to_hstring(left_received) & ", Right: 0x" & to_hstring(right_received) 
                       severity note;
            else
                report "Sample " & integer'image(sample_count) & " FAIL - Expected Left: 0x" & 
                       to_hstring(TEST_LEFT_DATA) & ", Got: 0x" & to_hstring(left_received) & 
                       ", Expected Right: 0x" & to_hstring(TEST_RIGHT_DATA) & 
                       ", Got: 0x" & to_hstring(right_received) severity error;
            end if;
            
            wait for 100 ns;  -- Small delay between checks
        end loop;
        
        report "Monitoring complete - check waveforms for detailed analysis" severity note;
        wait;
    end process;

end architecture i2s_rx_TB_arch;
