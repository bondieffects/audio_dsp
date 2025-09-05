-- LIBRARIES and PACKAGES for i2s_TB
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity i2s_TB is
end entity;

-- Test bench for top-level I2S module (integrates clocks, tx, and rx)
architecture i2s_TB_arch of i2s_TB is

    -- Clock timing constants
    constant MCLK_HALF_PERIOD : time := 41 ns;  -- 12.195 MHz MCLK (period = 82ns)
    
    -- Component declaration for DUT
    component i2s
        port (
            -- System interface
            i2s_mclk : in std_logic;
            reset_n : in std_logic;

            -- I2S external signals
            i2s_bclk : out std_logic;       -- Bit clock
            i2s_ws : out std_logic;         -- Word select
            i2s_dac : out std_logic;       -- Serial data to DAC
            i2s_adc : in std_logic;        -- Serial data from ADC

            -- Internal Parallel Audio Busses
            -- Playback Path (FPGA -> CODEC)
            audio_out_left : in std_logic_vector(15 downto 0);      -- Left channel audio output
            audio_out_right : in std_logic_vector(15 downto 0);     -- Right channel audio output
            audio_out_valid : in std_logic;                         -- Output valid signal
            sample_request : out std_logic;                         -- Sample request signal

            -- Record Path (CODEC->FPGA)
            audio_in_left : out std_logic_vector(15 downto 0);      -- Left channel audio input
            audio_in_right : out std_logic_vector(15 downto 0);     -- Right channel audio input
            audio_in_valid : out std_logic                          -- Input valid signal
        );
    end component;

    -- Signal declarations
    signal i2s_mclk_TB : std_logic := '0';
    signal reset_n_TB : std_logic := '0';
    signal i2s_bclk_TB : std_logic;
    signal i2s_ws_TB : std_logic;
    signal i2s_dac_TB : std_logic;
    signal i2s_adc_TB : std_logic := '0';
    
    -- Playback path signals
    signal audio_out_left_TB : std_logic_vector(15 downto 0) := (others => '0');
    signal audio_out_right_TB : std_logic_vector(15 downto 0) := (others => '0');
    signal audio_out_valid_TB : std_logic := '0';
    signal sample_request_TB : std_logic;
    
    -- Record path signals
    signal audio_in_left_TB : std_logic_vector(15 downto 0);
    signal audio_in_right_TB : std_logic_vector(15 downto 0);
    signal audio_in_valid_TB : std_logic;

    -- Test data for playback (TX test)
    type test_data_array is array (0 to 7) of std_logic_vector(15 downto 0);
    constant PLAYBACK_LEFT_DATA : test_data_array := (
        "0001001000110100",  -- 0x1234
        "0101011001111000",  -- 0x5678
        "1001101010111100",  -- 0x9ABC
        "1101111011101111",  -- 0xDEEF
        "1010101010101010",  -- 0xAAAA
        "0101010101010101",  -- 0x5555
        "1111111111111111",  -- 0xFFFF
        "0000000000000000"   -- 0x0000
    );
    
    constant PLAYBACK_RIGHT_DATA : test_data_array := (
        "1111111011101100",  -- 0xFEDC
        "1011101010011000",  -- 0xBA98
        "0110110101000100",  -- 0x6D44
        "0010001000010001",  -- 0x2211
        "0101010101010101",  -- 0x5555
        "1010101010101010",  -- 0xAAAA
        "0000000000000000",  -- 0x0000
        "1111111111111111"   -- 0xFFFF
    );

    -- Test data for record (RX test)
    constant RECORD_LEFT_DATA : test_data_array := (
        "1100110011001100",  -- 0xCCCC
        "0011001100110011",  -- 0x3333
        "1111000011110000",  -- 0xF0F0
        "0000111100001111",  -- 0x0F0F
        "1000000000000001",  -- 0x8001
        "0111111111111110",  -- 0x7FFE
        "1010010101001010",  -- 0xA54A
        "0101101010110101"   -- 0x5AB5
    );
    
    constant RECORD_RIGHT_DATA : test_data_array := (
        "0010001000100010",  -- 0x2222
        "1101110111011101",  -- 0xDDDD
        "0110011001100110",  -- 0x6666
        "1001100110011001",  -- 0x9999
        "0111111111111111",  -- 0x7FFF
        "1000000000000000",  -- 0x8000
        "0101101010110101",  -- 0x5AB5
        "1010010101001010"   -- 0xA54A
    );

    -- Test control
    signal playback_sample_index : integer := 0;
    signal record_sample_index : integer := 0;
    signal test_complete : boolean := false;

begin

    -- DUT instantiation
    DUT1: i2s
        port map (
            i2s_mclk => i2s_mclk_TB,
            reset_n => reset_n_TB,
            i2s_bclk => i2s_bclk_TB,
            i2s_ws => i2s_ws_TB,
            i2s_dac => i2s_dac_TB,
            i2s_adc => i2s_adc_TB,
            audio_out_left => audio_out_left_TB,
            audio_out_right => audio_out_right_TB,
            audio_out_valid => audio_out_valid_TB,
            sample_request => sample_request_TB,
            audio_in_left => audio_in_left_TB,
            audio_in_right => audio_in_right_TB,
            audio_in_valid => audio_in_valid_TB
        );

    -- Master Clock Generation Process
    MCLK_GEN: process
    begin
        -- Wait for reset release
        wait until reset_n_TB = '1';
        wait for 50 ns;  -- Small delay after reset
        
        -- Generate continuous MCLK
        while not test_complete loop
            i2s_mclk_TB <= '1';
            wait for MCLK_HALF_PERIOD;
            i2s_mclk_TB <= '0';
            wait for MCLK_HALF_PERIOD;
        end loop;
        
        report "MCLK generation complete" severity note;
        wait;
    end process;

    -- Playback Data Provider (responds to sample_request)
    PLAYBACK_DATA_PROVIDER: process
    begin
        -- Initialize
        audio_out_left_TB <= (others => '0');
        audio_out_right_TB <= (others => '0');
        audio_out_valid_TB <= '0';
        playback_sample_index <= 0;
        
        -- Wait for reset release
        wait until reset_n_TB = '1';
        wait for 200 ns;  -- Allow clocks to stabilize
        
        -- Provide playback data when requested
        while playback_sample_index < PLAYBACK_LEFT_DATA'length loop
            -- Wait for sample request
            wait until rising_edge(sample_request_TB);
            
            -- Provide new sample data
            audio_out_left_TB <= PLAYBACK_LEFT_DATA(playback_sample_index);
            audio_out_right_TB <= PLAYBACK_RIGHT_DATA(playback_sample_index);
            audio_out_valid_TB <= '1';
            
            report "Playback sample " & integer'image(playback_sample_index) & 
                   " - Left: 0x" & to_hstring(PLAYBACK_LEFT_DATA(playback_sample_index)) &
                   ", Right: 0x" & to_hstring(PLAYBACK_RIGHT_DATA(playback_sample_index)) 
                   severity note;
            
            -- Keep data valid for several clock cycles
            wait for 1 us;
            audio_out_valid_TB <= '0';
            
            playback_sample_index <= playback_sample_index + 1;
            
            -- Small delay before next sample
            wait for 500 ns;
        end loop;
        
        report "Playback data provider complete" severity note;
        wait;
    end process;

    -- Record Data Generator (simulates ADC sending data via i2s_adc)
    RECORD_DATA_GENERATOR: process
        variable bit_index : integer;
        variable current_left_data : std_logic_vector(15 downto 0);
        variable current_right_data : std_logic_vector(15 downto 0);
    begin
        -- Initialize
        i2s_adc_TB <= '0';
        record_sample_index <= 0;
        
        -- Wait for reset and clocks to stabilize
        wait until reset_n_TB = '1';
        wait for 500 ns;
        
        -- Generate record data for multiple samples
        while record_sample_index < RECORD_LEFT_DATA'length loop
            -- Wait for start of left channel (WS falling edge)
            wait until falling_edge(i2s_ws_TB);
            wait until rising_edge(i2s_bclk_TB);  -- Data sampled on rising edge
            
            -- Send left channel data (MSB first)
            current_left_data := RECORD_LEFT_DATA(record_sample_index);
            for bit_index in 15 downto 0 loop
                i2s_adc_TB <= current_left_data(bit_index);
                wait until rising_edge(i2s_bclk_TB);
            end loop;
            
            -- Wait for start of right channel (WS rising edge)
            wait until rising_edge(i2s_ws_TB);
            wait until rising_edge(i2s_bclk_TB);  -- Data sampled on rising edge
            
            -- Send right channel data (MSB first)
            current_right_data := RECORD_RIGHT_DATA(record_sample_index);
            for bit_index in 15 downto 0 loop
                i2s_adc_TB <= current_right_data(bit_index);
                wait until rising_edge(i2s_bclk_TB);
            end loop;
            
            report "Record sample " & integer'image(record_sample_index) & " sent" &
                   " - Left: 0x" & to_hstring(RECORD_LEFT_DATA(record_sample_index)) &
                   ", Right: 0x" & to_hstring(RECORD_RIGHT_DATA(record_sample_index)) 
                   severity note;
            
            record_sample_index <= record_sample_index + 1;
        end loop;
        
        report "Record data generation complete" severity note;
        wait;
    end process;

    -- Reset and Stimulus Control Process
    STIMULUS: process
    begin
        -- Initialize signals
        reset_n_TB <= '0';
        wait for 300 ns;    -- Hold reset for 300 ns

        reset_n_TB <= '1';  -- Release reset
        report "Reset released - I2S test starting" severity note;

        -- Wait for all test data to be processed
        wait until playback_sample_index >= PLAYBACK_LEFT_DATA'length and 
                   record_sample_index >= RECORD_LEFT_DATA'length;
        wait for 5 ms;  -- Extra time for final transmissions
        
        test_complete <= true;
        report "Test stimulus complete" severity note;
        wait;
    end process;

    -- Playback (TX) Output Monitor
    PLAYBACK_MONITOR: process
        variable captured_left : std_logic_vector(15 downto 0);
        variable captured_right : std_logic_vector(15 downto 0);
        variable bit_index : integer;
        variable sample_count : integer := 0;
    begin
        -- Wait for reset and clocks to start
        wait until reset_n_TB = '1';
        wait for 1 us;
        
        -- Monitor transmitted playback data
        while sample_count < 4 loop  -- Monitor first 4 playback samples
            -- Wait for start of left channel transmission
            wait until falling_edge(i2s_ws_TB);
            wait until falling_edge(i2s_bclk_TB);  -- TX data changes on falling edge
            
            -- Capture left channel data from i2s_dac
            for bit_index in 15 downto 0 loop
                captured_left(bit_index) := i2s_dac_TB;
                wait until falling_edge(i2s_bclk_TB);
            end loop;
            
            -- Wait for start of right channel transmission
            wait until rising_edge(i2s_ws_TB);
            wait until falling_edge(i2s_bclk_TB);  -- TX data changes on falling edge
            
            -- Capture right channel data from i2s_dac
            for bit_index in 15 downto 0 loop
                captured_right(bit_index) := i2s_dac_TB;
                wait until falling_edge(i2s_bclk_TB);
            end loop;
            
            -- Verify captured playback data
            if sample_count < PLAYBACK_LEFT_DATA'length then
                if captured_left = PLAYBACK_LEFT_DATA(sample_count) and 
                   captured_right = PLAYBACK_RIGHT_DATA(sample_count) then
                    report "Playback sample " & integer'image(sample_count) & " TX PASS - " &
                           "Left: 0x" & to_hstring(captured_left) & 
                           ", Right: 0x" & to_hstring(captured_right) 
                           severity note;
                else
                    report "Playback sample " & integer'image(sample_count) & " TX FAIL - " &
                           "Expected Left: 0x" & to_hstring(PLAYBACK_LEFT_DATA(sample_count)) & 
                           ", Got: 0x" & to_hstring(captured_left) &
                           ", Expected Right: 0x" & to_hstring(PLAYBACK_RIGHT_DATA(sample_count)) & 
                           ", Got: 0x" & to_hstring(captured_right) 
                           severity error;
                end if;
            end if;
            
            sample_count := sample_count + 1;
        end loop;
        
        report "Playback monitoring complete" severity note;
        wait;
    end process;

    -- Record (RX) Input Monitor
    RECORD_MONITOR: process
        variable sample_count : integer := 0;
    begin
        -- Wait for reset and clocks to start
        wait until reset_n_TB = '1';
        wait for 1 us;
        
        -- Monitor received record data
        while sample_count < 4 loop  -- Monitor first 4 record samples
            wait until rising_edge(audio_in_valid_TB);
            
            -- Verify received record data
            if sample_count < RECORD_LEFT_DATA'length then
                if audio_in_left_TB = RECORD_LEFT_DATA(sample_count) and 
                   audio_in_right_TB = RECORD_RIGHT_DATA(sample_count) then
                    report "Record sample " & integer'image(sample_count) & " RX PASS - " &
                           "Left: 0x" & to_hstring(audio_in_left_TB) & 
                           ", Right: 0x" & to_hstring(audio_in_right_TB) 
                           severity note;
                else
                    report "Record sample " & integer'image(sample_count) & " RX FAIL - " &
                           "Expected Left: 0x" & to_hstring(RECORD_LEFT_DATA(sample_count)) & 
                           ", Got: 0x" & to_hstring(audio_in_left_TB) &
                           ", Expected Right: 0x" & to_hstring(RECORD_RIGHT_DATA(sample_count)) & 
                           ", Got: 0x" & to_hstring(audio_in_right_TB) 
                           severity error;
                end if;
            end if;
            
            sample_count := sample_count + 1;
            wait for 100 ns;
        end loop;
        
        report "Record monitoring complete" severity note;
        wait;
    end process;

    -- General System Monitor
    SYSTEM_MONITOR: process
    begin
        -- Wait for reset release
        wait until reset_n_TB = '1';
        report "Reset released - system monitoring started" severity note;
        
        -- Monitor key system events
        while not test_complete loop
            -- Monitor sample request timing
            wait until rising_edge(sample_request_TB);
            report "Sample request at " & time'image(now) severity note;
            wait for 100 ns;
        end loop;
        
        report "System monitoring complete - check waveforms for detailed timing analysis" severity note;
        wait;
    end process;

end architecture i2s_TB_arch;
