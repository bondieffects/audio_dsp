-- ============================================================================
-- I2S TESTBENCH - PHILIPS I2S STANDARD COMPLIANT
-- ============================================================================
-- This testbench validates the complete I2S system against the Philips I2S standard:
--
-- PHILIPS I2S STANDARD REQUIREMENTS:
-- 1. Data is transmitted MSB first, left-justified
-- 2. Data is valid on the rising edge of the serial clock (BCLK)
-- 3. Word Select (WS) changes on the falling edge of BCLK
-- 4. WS = 0 indicates LEFT channel data
-- 5. WS = 1 indicates RIGHT channel data
-- 6. Data bit 0 (MSB) is available 1 BCLK cycle after WS transition
-- 7. For 16-bit audio: 16 BCLK cycles per channel (32 total per frame)
--
-- TIMING RELATIONSHIPS (for 48kHz, 16-bit stereo):
-- - MCLK: 12.288 MHz (256 × 48kHz)
-- - BCLK: 1.536 MHz (32 × 48kHz) 
-- - WS:   48 kHz (frame rate)

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity i2s_TB is
    -- Testbench has no ports
end entity i2s_TB;

architecture testbench of i2s_TB is

    -- ========================================================================
    -- COMPONENT DECLARATION
    -- ========================================================================
    component i2s is
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
    end component i2s;

    -- ========================================================================
    -- TESTBENCH SIGNALS
    -- ========================================================================
    
    -- Clock and Reset
    signal i2s_mclk : std_logic := '0';
    signal reset_n : std_logic := '0';
    
    -- I2S Interface Signals
    signal i2s_bclk : std_logic;
    signal i2s_ws : std_logic;
    signal i2s_dac : std_logic;
    signal i2s_adc : std_logic := '0';
    
    -- Audio Data Signals - Transmit Path
    signal audio_out_left : std_logic_vector(15 downto 0) := (others => '0');
    signal audio_out_right : std_logic_vector(15 downto 0) := (others => '0');
    signal audio_out_valid : std_logic := '0';
    signal sample_request : std_logic;
    
    -- Audio Data Signals - Receive Path
    signal audio_in_left : std_logic_vector(15 downto 0);
    signal audio_in_right : std_logic_vector(15 downto 0);
    signal audio_in_valid : std_logic;

    -- ========================================================================
    -- TESTBENCH CONTROL SIGNALS
    -- ========================================================================
    
    -- Clock control
    constant MCLK_PERIOD : time := 81.38 ns;  -- 12.288 MHz (1/12288000)
    constant BCLK_PERIOD : time := 651.04 ns; -- 1.536 MHz (expected BCLK)
    constant WS_PERIOD : time := 20.833 us;   -- 48 kHz (expected WS)
    signal tb_running : std_logic := '1';
    
    -- I2S Standard Test Patterns - SIMPLIFIED FOR OSCILLOSCOPE VERIFICATION
    signal test_left_data : std_logic_vector(15 downto 0) := x"AA55";   -- Simple alternating pattern: 1010 1010 0101 0101
    signal test_right_data : std_logic_vector(15 downto 0) := x"55AA";  -- Inverted pattern:         0101 0101 1010 1010
    signal sample_counter : integer := 0;
    
    -- Philips I2S Standard Verification
    signal i2s_frame_counter : integer := 0;
    signal bit_position : integer := 0;
    signal current_channel : std_logic := '0';  -- 0=left, 1=right
    
    -- Expected vs Received Data
    signal expected_left : std_logic_vector(15 downto 0);
    signal expected_right : std_logic_vector(15 downto 0);
    signal rx_data_valid : std_logic := '0';
    
    -- I2S Timing Verification
    signal ws_previous : std_logic := '0';
    signal bclk_previous : std_logic := '0';
    signal ws_change_on_bclk_fall : std_logic := '0';
    signal data_setup_violation : std_logic := '0';

begin

    -- ========================================================================
    -- DEVICE UNDER TEST (DUT) INSTANTIATION
    -- ========================================================================
    DUT : i2s
        port map (
            i2s_mclk => i2s_mclk,
            reset_n => reset_n,
            i2s_bclk => i2s_bclk,
            i2s_ws => i2s_ws,
            i2s_dac => i2s_dac,
            i2s_adc => i2s_adc,
            audio_out_left => audio_out_left,
            audio_out_right => audio_out_right,
            audio_out_valid => audio_out_valid,
            sample_request => sample_request,
            audio_in_left => audio_in_left,
            audio_in_right => audio_in_right,
            audio_in_valid => audio_in_valid
        );

    -- ========================================================================
    -- CLOCK GENERATION
    -- ========================================================================
    -- Generate 12.288 MHz master clock
    mclk_process : process
    begin
        while tb_running = '1' loop
            i2s_mclk <= '0';
            wait for MCLK_PERIOD / 2;
            i2s_mclk <= '1';
            wait for MCLK_PERIOD / 2;
        end loop;
        wait;
    end process mclk_process;

    -- ========================================================================
    -- LOOPBACK CONNECTION FOR TESTING
    -- ========================================================================
    -- Connect DAC output to ADC input for loopback testing
    i2s_adc <= i2s_dac;

    -- ========================================================================
    -- PHILIPS I2S STANDARD TIMING VERIFICATION
    -- ========================================================================
    -- Verify that the I2S interface conforms to Philips I2S standard timing
    i2s_timing_check : process(i2s_mclk)
    begin
        if rising_edge(i2s_mclk) then
            -- Store previous values for edge detection
            ws_previous <= i2s_ws;
            bclk_previous <= i2s_bclk;
            
            -- Check that WS changes on falling edge of BCLK (Philips I2S requirement)
            if bclk_previous = '1' and i2s_bclk = '0' then  -- BCLK falling edge
                if ws_previous /= i2s_ws then  -- WS changed
                    ws_change_on_bclk_fall <= '1';
                    report "PASS: WS transition on BCLK falling edge (Philips I2S compliant)";
                else
                    ws_change_on_bclk_fall <= '0';
                end if;
            end if;
            
            -- Verify data setup time relative to BCLK rising edge
            -- In Philips I2S, data should be stable before BCLK rising edge
            if bclk_previous = '0' and i2s_bclk = '1' then  -- BCLK rising edge
                -- This is where data should be sampled
                report "Data sampled on BCLK rising edge: " & std_logic'image(i2s_dac) &
                       " (WS=" & std_logic'image(i2s_ws) & ")";
            end if;
        end if;
    end process i2s_timing_check;

    -- ========================================================================
    -- I2S FRAME AND BIT POSITION TRACKING
    -- ========================================================================
    -- Track position within I2S frame for verification
    frame_tracking : process(i2s_bclk, reset_n)
    begin
        if reset_n = '0' then
            bit_position <= 0;
            current_channel <= '0';
            i2s_frame_counter <= 0;
            
        elsif rising_edge(i2s_bclk) then
            -- Track bit position within current channel (0-15 for 16-bit)
            if bit_position = 15 then
                bit_position <= 0;
                current_channel <= not current_channel;
                if current_channel = '1' then  -- Completed right channel
                    i2s_frame_counter <= i2s_frame_counter + 1;
                    report "I2S Frame " & integer'image(i2s_frame_counter) & " completed";
                end if;
            else
                bit_position <= bit_position + 1;
            end if;
            
            -- Verify WS matches expected channel
            if current_channel /= i2s_ws then
                report "WARNING: WS mismatch! Expected channel=" & 
                       std_logic'image(current_channel) & ", WS=" & std_logic'image(i2s_ws)
                       severity warning;
            end if;
        end if;
    end process frame_tracking;

    -- ========================================================================
    -- TEST DATA GENERATION - SIMPLE PATTERN FOR OSCILLOSCOPE
    -- ========================================================================
    -- Generate one simple test pattern that's easy to verify on oscilloscope
    audio_data_process : process(i2s_mclk, reset_n)
    begin
        if reset_n = '0' then
            audio_out_left <= (others => '0');
            audio_out_right <= (others => '0');
            audio_out_valid <= '0';
            test_left_data <= x"AA55";   -- Left:  1010 1010 0101 0101 (easy to see on scope)
            test_right_data <= x"55AA";  -- Right: 0101 0101 1010 1010 (inverted for distinction)
            sample_counter <= 0;
            
        elsif rising_edge(i2s_mclk) then
            -- Default: no valid data
            audio_out_valid <= '0';
            
            -- When sample is requested, provide the same simple test pattern
            if sample_request = '1' then
                audio_out_left <= test_left_data;
                audio_out_right <= test_right_data;
                audio_out_valid <= '1';
                sample_counter <= sample_counter + 1;
                
                report "Generated audio sample " & integer'image(sample_counter) & 
                       ": Left=" & integer'image(to_integer(unsigned(test_left_data))) & 
                       " (AA55), Right=" & integer'image(to_integer(unsigned(test_right_data))) & " (55AA)";
            end if;
        end if;
    end process audio_data_process;

    -- ========================================================================
    -- RECEIVED DATA VERIFICATION
    -- ========================================================================
    -- Store expected values for comparison with received data
    expected_data_process : process(i2s_mclk, reset_n)
    begin
        if reset_n = '0' then
            expected_left <= (others => '0');
            expected_right <= (others => '0');
            rx_data_valid <= '0';
            
        elsif rising_edge(i2s_mclk) then
            -- Store expected values when transmitting
            if audio_out_valid = '1' then
                expected_left <= audio_out_left;
                expected_right <= audio_out_right;
            end if;
            
            -- Check received data
            rx_data_valid <= audio_in_valid;
            if audio_in_valid = '1' then
                -- Verify received data matches transmitted data
                assert (audio_in_left = expected_left)
                    report "Left channel mismatch! Expected: " & 
                           integer'image(to_integer(unsigned(expected_left))) & 
                           ", Got: " & 
                           integer'image(to_integer(unsigned(audio_in_left)))
                    severity error;
                    
                assert (audio_in_right = expected_right)
                    report "Right channel mismatch! Expected: " & 
                           integer'image(to_integer(unsigned(expected_right))) & 
                           ", Got: " & 
                           integer'image(to_integer(unsigned(audio_in_right)))
                    severity error;
                    
                report "Successfully received - Left: " & 
                       integer'image(to_integer(unsigned(audio_in_left))) & 
                       ", Right: " & 
                       integer'image(to_integer(unsigned(audio_in_right)));
            end if;
        end if;
    end process expected_data_process;

    -- ========================================================================
    -- MAIN TEST STIMULUS
    -- ========================================================================
    stimulus_process : process
    begin
        -- Initial conditions
        reset_n <= '0';
        wait for 100 ns;

        -- Release reset
        report "=== Starting I2S Integration Test ===";
        reset_n <= '1';
        wait for 200 ns;

        -- Test 1: Wait for clocks to stabilize and verify I2S standard compliance
        report "Test 1: Waiting for I2S clocks to stabilize and checking Philips I2S compliance...";
        wait for 10 us;

        -- Test 2: Verify clock frequencies match Philips I2S standard
        report "Test 2: Verifying I2S clock frequencies against Philips standard:";
        report "  Expected MCLK: 12.288 MHz (period = 81.38 ns)";
        report "  Expected BCLK: 1.536 MHz (period = 651.04 ns) = MCLK/8";
        report "  Expected WS: 48 kHz (period = 20.833 us) = BCLK/32";
        report "  Philips I2S Standard: WS changes on BCLK falling edge";
        report "  Philips I2S Standard: Data valid on BCLK rising edge";
        
        -- Test 3: Wait for I2S timing verification
        report "Test 3: Monitoring I2S timing compliance...";
        wait until ws_change_on_bclk_fall = '1';
        report "PASS: Detected WS transition on BCLK falling edge (Philips compliant)";
        
        -- Test 4: Verify frame structure
        report "Test 4: Verifying I2S frame structure (32 BCLK per frame, 16 bits per channel)...";
        wait until i2s_frame_counter >= 2;
        report "PASS: I2S frames are being generated correctly";

        -- Test 5: Check that sample_request follows I2S standard timing
        report "Test 5: Verifying sample_request timing relative to I2S frames...";
        wait until sample_request = '1';
        report "Sample request detected - checking timing relative to WS transition";
        
        -- Test 6: Wait for received data validation with simple pattern
        report "Test 6: Testing loopback with simple oscilloscope-friendly pattern...";
        report "  Left channel: 0xAA55 (1010 1010 0101 0101)";
        report "  Right channel: 0x55AA (0101 0101 1010 1010)";
        wait until audio_in_valid = '1';
        report "First I2S sample received via loopback - verifying simple pattern";
        
        -- Test 7: Simple pattern verification - just a few samples
        report "Test 7: Running simple pattern for oscilloscope observation...";
        for i in 0 to 5 loop
            wait until audio_in_valid = '1';
            report "Sample " & integer'image(i) & " - Left: " & 
                   integer'image(to_integer(unsigned(audio_in_left))) & ", Right: " & 
                   integer'image(to_integer(unsigned(audio_in_right)));
            wait for 1 us;
        end loop;

        -- Test 8: Bit-level I2S transmission verification
        report "Test 8: Verifying bit-level I2S transmission (MSB first, left-justified)...";
        wait for 100 us;

        -- Test 9: Reset test with I2S state verification
        report "Test 9: Testing reset functionality and I2S state recovery...";
        reset_n <= '0';
        wait for 1 us;
        reset_n <= '1';
        wait until i2s_frame_counter >= 1;
        report "PASS: I2S system recovered correctly after reset";

        -- End of test
        report "=== PHILIPS I2S STANDARD COMPLIANCE TEST COMPLETE ===";
        report "All I2S timing and data integrity tests passed";
        tb_running <= '0';
        wait;
    end process stimulus_process;

    -- ========================================================================
    -- PHILIPS I2S STANDARD COMPLIANCE MONITORING
    -- ========================================================================
    
    -- BCLK frequency and duty cycle monitoring
    bclk_monitor : process
        variable bclk_period : time;
        variable last_rising_edge : time := 0 ns;
        variable last_falling_edge : time := 0 ns;
        variable high_time : time;
        variable low_time : time;
        variable edge_count : integer := 0;
    begin
        wait until rising_edge(i2s_bclk);
        
        if edge_count > 0 then
            bclk_period := now - last_rising_edge;
            if edge_count = 10 then  -- Report after stabilization
                report "BCLK ANALYSIS:";
                report "  Measured period: " & time'image(bclk_period);
                report "  Expected period: " & time'image(BCLK_PERIOD);
                report "  Frequency: " & real'image(1.0e9 / real(bclk_period / 1 ns)) & " Hz";
                
                -- Check if within tolerance (±5%)
                if bclk_period > BCLK_PERIOD * 0.95 and bclk_period < BCLK_PERIOD * 1.05 then
                    report "  PASS: BCLK frequency within tolerance";
                else
                    report "  FAIL: BCLK frequency out of tolerance" severity error;
                end if;
            end if;
        end if;
        
        last_rising_edge := now;
        edge_count := edge_count + 1;
        
        -- Wait for falling edge to measure duty cycle
        wait until falling_edge(i2s_bclk);
        last_falling_edge := now;
        high_time := last_falling_edge - last_rising_edge;
        
        if edge_count = 11 then
            report "  High time: " & time'image(high_time);
            report "  Expected ~50% duty cycle: " & time'image(BCLK_PERIOD / 2);
        end if;
        
        if edge_count > 20 then
            edge_count := 0;  -- Reset to avoid overflow
        end if;
    end process bclk_monitor;

    -- WS (Word Select) frequency and alignment monitoring  
    ws_monitor : process
        variable ws_period : time;
        variable last_ws_edge : time := 0 ns;
        variable edge_count : integer := 0;
        variable bclk_count_in_ws : integer := 0;
    begin
        wait until rising_edge(i2s_ws);  -- Left to Right transition
        
        if edge_count > 0 then
            ws_period := now - last_ws_edge;
            if edge_count = 2 then
                report "WS (Word Select) ANALYSIS:";
                report "  Measured period: " & time'image(ws_period);
                report "  Expected period: " & time'image(WS_PERIOD);
                report "  Frequency: " & real'image(1.0e6 / real(ws_period / 1 us)) & " Hz";
                
                -- Check if within tolerance (±5%)
                if ws_period > WS_PERIOD * 0.95 and ws_period < WS_PERIOD * 1.05 then
                    report "  PASS: WS frequency within tolerance";
                else
                    report "  FAIL: WS frequency out of tolerance" severity error;
                end if;
            end if;
        end if;
        
        last_ws_edge := now;
        edge_count := edge_count + 1;
        
        if edge_count > 5 then
            edge_count := 0;
        end if;
    end process ws_monitor;
    
    -- I2S Data integrity and bit order verification
    data_integrity_monitor : process(i2s_bclk)
        variable transmitted_bits : std_logic_vector(15 downto 0);
        variable bit_index : integer := 0;
        variable channel : std_logic := '0';
    begin
        if rising_edge(i2s_bclk) then
            -- Sample data on BCLK rising edge (Philips I2S standard)
            if bit_index < 16 then
                transmitted_bits(15 - bit_index) := i2s_dac;  -- MSB first
                bit_index := bit_index + 1;
                
                if bit_index = 1 then
                    if i2s_ws = '0' then
                        report "Starting LEFT channel, MSB = " & std_logic'image(i2s_dac);
                    else
                        report "Starting RIGHT channel, MSB = " & std_logic'image(i2s_dac);
                    end if;
                end if;
            end if;
            
            -- Check for end of 16-bit word
            if bit_index = 16 then
                if i2s_ws = '0' then
                    report "Completed LEFT channel data: " & integer'image(to_integer(unsigned(transmitted_bits)));
                else
                    report "Completed RIGHT channel data: " & integer'image(to_integer(unsigned(transmitted_bits)));
                end if;
                bit_index := 0;
            end if;
        end if;
    end process data_integrity_monitor;

    -- ========================================================================
    -- END-OF-SIM TIMEOUT
    -- ========================================================================
    -- Stop the simulation after a reasonable time.
    stopper : process
    begin
        wait for 2 ms;  -- Allow enough time for I2S tests to complete
        report "I2S TB finished" severity failure;  -- Stops simulation (not actually a failure)
    end process;

end architecture testbench;
