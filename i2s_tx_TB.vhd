-- LIBRARIES and PACKAGES for i2s_tx_TB
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity i2s_tx_TB is
end entity;

-- Test bench for I2S Transmitter module
architecture i2s_tx_TB_arch of i2s_tx_TB is

    -- Clock timing constants
    constant BCLK_HALF_PERIOD : time := 325 ns;  -- 1.536 MHz BCLK (period = 650ns)
    constant WS_HALF_PERIOD : time := 10416 ns;  -- 48 kHz WS (period = 20.833us)

    -- Component declaration for DUT
    component i2s_tx
        port (
            -- Clocks and Reset
            i2s_bclk : in std_logic;
            i2s_ws   : in std_logic;
            reset_n  : in std_logic;

            -- Parallel audio data inputs (16-bit samples)
            audio_left  : in std_logic_vector(15 downto 0);
            audio_right : in std_logic_vector(15 downto 0);
            audio_valid : in std_logic;

            -- I2S Serial Data Output
            i2s_sdata : out std_logic;
            sample_request : out std_logic
        );
    end component;

    -- Signal declarations
    signal i2s_bclk_TB : std_logic := '0';
    signal i2s_ws_TB : std_logic := '0';
    signal reset_n_TB : std_logic := '0';
    signal audio_left_TB : std_logic_vector(15 downto 0) := (others => '0');
    signal audio_right_TB : std_logic_vector(15 downto 0) := (others => '0');
    signal audio_valid_TB : std_logic := '0';
    signal i2s_sdata_TB : std_logic;
    signal sample_request_TB : std_logic;

    -- Test data arrays for multiple samples
    type test_data_array is array (0 to 9) of std_logic_vector(15 downto 0);
    constant LEFT_TEST_DATA : test_data_array := (
        "0000000000000001",  -- Sample 0: 0x0001
        "0000000000000010",  -- Sample 1: 0x0002
        "0000000000000100",  -- Sample 2: 0x0004
        "0000000000001000",  -- Sample 3: 0x0008
        "0000000000010000",  -- Sample 4: 0x0010
        "1010101010101010",  -- Sample 5: 0xAAAA
        "1111111111111111",  -- Sample 6: 0xFFFF
        "1000000000000000",  -- Sample 7: 0x8000
        "0111111111111111",  -- Sample 8: 0x7FFF
        "0101010101010101"   -- Sample 9: 0x5555
    );
    
    constant RIGHT_TEST_DATA : test_data_array := (
        "1111111111111110",  -- Sample 0: 0xFFFE
        "1111111111111101",  -- Sample 1: 0xFFFD
        "1111111111111011",  -- Sample 2: 0xFFFB
        "1111111111110111",  -- Sample 3: 0xFFF7
        "1111111111101111",  -- Sample 4: 0xFFEF
        "0101010101010101",  -- Sample 5: 0x5555
        "0000000000000000",  -- Sample 6: 0x0000
        "0111111111111111",  -- Sample 7: 0x7FFF
        "1000000000000000",  -- Sample 8: 0x8000
        "1010101010101010"   -- Sample 9: 0xAAAA
    );

    -- Test control signals
    signal sample_index : integer := 0;
    signal test_complete : boolean := false;

begin

    -- DUT instantiation
    DUT1: i2s_tx
        port map (
            i2s_bclk => i2s_bclk_TB,
            i2s_ws => i2s_ws_TB,
            reset_n => reset_n_TB,
            audio_left => audio_left_TB,
            audio_right => audio_right_TB,
            audio_valid => audio_valid_TB,
            i2s_sdata => i2s_sdata_TB,
            sample_request => sample_request_TB
        );

    -- BCLK Generation Process
    BCLK_GEN: process
    begin
        -- Wait for reset release
        wait until reset_n_TB = '1';
        wait for 50 ns;  -- Small delay after reset
        
        -- Generate continuous BCLK
        while not test_complete loop
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
        while not test_complete loop
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

    -- Audio Data Provider Process (responds to sample_request)
    DATA_PROVIDER: process
    begin
        -- Initialize
        audio_left_TB <= (others => '0');
        audio_right_TB <= (others => '0');
        audio_valid_TB <= '0';
        sample_index <= 0;
        
        -- Wait for reset release
        wait until reset_n_TB = '1';
        wait for 150 ns;  -- Allow clocks to start
        
        -- Provide data when requested
        while sample_index < LEFT_TEST_DATA'length loop
            -- Wait for sample request
            wait until rising_edge(sample_request_TB);
            
            -- Provide new sample data
            audio_left_TB <= LEFT_TEST_DATA(sample_index);
            audio_right_TB <= RIGHT_TEST_DATA(sample_index);
            audio_valid_TB <= '1';
            
            report "Providing sample " & integer'image(sample_index) & 
                   " - Left: 0x" & to_hstring(LEFT_TEST_DATA(sample_index)) &
                   ", Right: 0x" & to_hstring(RIGHT_TEST_DATA(sample_index)) 
                   severity note;
            
            -- Keep data valid for a few clock cycles
            wait for 500 ns;
            audio_valid_TB <= '0';
            
            sample_index <= sample_index + 1;
            
            -- Small delay before next sample
            wait for 1 us;
        end loop;
        
        -- Signal test completion
        wait for 2 ms;  -- Allow current transmission to complete
        test_complete <= true;
        
        report "Data provider complete" severity note;
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

        -- Wait for test completion
        wait until test_complete = true;
        wait for 1 ms;  -- Extra time for final transmissions
        
        report "Test stimulus complete" severity note;
        wait;
    end process;

    -- Serial Output Monitor Process (Captures and verifies transmitted data)
    SDATA_MONITOR: process
        variable captured_left : std_logic_vector(15 downto 0);
        variable captured_right : std_logic_vector(15 downto 0);
        variable bit_index : integer;
        variable sample_count : integer := 0;
    begin
        -- Wait for reset release and clocks to start
        wait until reset_n_TB = '1';
        wait for 300 ns;
        
        -- Monitor transmitted serial data
        while sample_count < 5 loop  -- Monitor first 5 samples
            -- Wait for start of left channel (WS falling edge)
            wait until falling_edge(i2s_ws_TB);
            wait until falling_edge(i2s_bclk_TB);  -- Data changes on falling edge
            
            -- Capture left channel data (16 bits, MSB first)
            for bit_index in 15 downto 0 loop
                captured_left(bit_index) := i2s_sdata_TB;
                wait until falling_edge(i2s_bclk_TB);
            end loop;
            
            -- Wait for start of right channel (WS rising edge)
            wait until rising_edge(i2s_ws_TB);
            wait until falling_edge(i2s_bclk_TB);  -- Data changes on falling edge
            
            -- Capture right channel data (16 bits, MSB first)
            for bit_index in 15 downto 0 loop
                captured_right(bit_index) := i2s_sdata_TB;
                wait until falling_edge(i2s_bclk_TB);
            end loop;
            
            -- Verify captured data against expected
            if sample_count < LEFT_TEST_DATA'length then
                if captured_left = LEFT_TEST_DATA(sample_count) and 
                   captured_right = RIGHT_TEST_DATA(sample_count) then
                    report "Sample " & integer'image(sample_count) & " PASS - " &
                           "Left: 0x" & to_hstring(captured_left) & 
                           ", Right: 0x" & to_hstring(captured_right) 
                           severity note;
                else
                    report "Sample " & integer'image(sample_count) & " FAIL - " &
                           "Expected Left: 0x" & to_hstring(LEFT_TEST_DATA(sample_count)) & 
                           ", Got: 0x" & to_hstring(captured_left) &
                           ", Expected Right: 0x" & to_hstring(RIGHT_TEST_DATA(sample_count)) & 
                           ", Got: 0x" & to_hstring(captured_right) 
                           severity error;
                end if;
            end if;
            
            sample_count := sample_count + 1;
        end loop;
        
        report "Serial data monitoring complete" severity note;
        wait;
    end process;

    -- General Monitoring Process
    MONITOR: process
    begin
        -- Wait for reset release
        wait until reset_n_TB = '1';
        report "Reset released - monitoring started" severity note;
        
        -- Monitor sample_request signal
        while not test_complete loop
            wait until rising_edge(sample_request_TB);
            report "Sample request detected at time " & time'image(now) severity note;
            wait for 100 ns;
        end loop;
        
        report "General monitoring complete - check waveforms for detailed analysis" severity note;
        wait;
    end process;

end architecture i2s_tx_TB_arch;
