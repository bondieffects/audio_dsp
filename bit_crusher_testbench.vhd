-- Bit Crusher Testbench
-- Tests bit depth reduction and sample rate decimation
-- Author: Group 10

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

entity bit_crusher_testbench is
end entity bit_crusher_testbench;

architecture testbench of bit_crusher_testbench is
    
    -- Test parameters
    constant CLK_PERIOD : time := 81.38 ns;  -- 12.288MHz audio clock
    constant SAMPLE_PERIOD : time := 256 * CLK_PERIOD;  -- Approximate sample period
    
    -- Component under test
    component bit_crusher is
        port (
            clk             : in  std_logic;
            reset_n         : in  std_logic;
            audio_in_left   : in  std_logic_vector(15 downto 0);
            audio_in_right  : in  std_logic_vector(15 downto 0);
            audio_valid_in  : in  std_logic;
            bit_depth       : in  std_logic_vector(3 downto 0);
            decimation      : in  std_logic_vector(3 downto 0);
            mix_level       : in  std_logic_vector(7 downto 0);
            audio_out_left  : out std_logic_vector(15 downto 0);
            audio_out_right : out std_logic_vector(15 downto 0);
            audio_valid_out : out std_logic
        );
    end component;
    
    -- Test signals
    signal clk             : std_logic := '0';
    signal reset_n         : std_logic := '0';
    signal audio_in_left   : std_logic_vector(15 downto 0) := (others => '0');
    signal audio_in_right  : std_logic_vector(15 downto 0) := (others => '0');
    signal audio_valid_in  : std_logic := '0';
    signal bit_depth       : std_logic_vector(3 downto 0) := x"F";
    signal decimation      : std_logic_vector(3 downto 0) := x"0";
    signal mix_level       : std_logic_vector(7 downto 0) := x"FF";
    signal audio_out_left  : std_logic_vector(15 downto 0);
    signal audio_out_right : std_logic_vector(15 downto 0);
    signal audio_valid_out : std_logic;
    
    -- Test control
    signal test_done : boolean := false;
    signal sample_counter : integer := 0;
    
    -- Test waveform generation
    signal sine_phase : real := 0.0;
    constant SINE_FREQ : real := 1000.0;  -- 1kHz test tone
    constant SAMPLE_RATE : real := 48000.0;
    constant PHASE_INCREMENT : real := 2.0 * MATH_PI * SINE_FREQ / SAMPLE_RATE;
    
begin
    
    -- Clock generation
    clk <= not clk after CLK_PERIOD/2 when not test_done;
    
    -- Instantiate bit crusher
    u_bit_crusher : bit_crusher
        port map (
            clk             => clk,
            reset_n         => reset_n,
            audio_in_left   => audio_in_left,
            audio_in_right  => audio_in_right,
            audio_valid_in  => audio_valid_in,
            bit_depth       => bit_depth,
            decimation      => decimation,
            mix_level       => mix_level,
            audio_out_left  => audio_out_left,
            audio_out_right => audio_out_right,
            audio_valid_out => audio_valid_out
        );
    
    -- Generate test waveform (1kHz sine wave)
    waveform_generator : process(clk, reset_n)
        variable sine_val : real;
        variable sample_val : integer;
    begin
        if reset_n = '0' then
            sine_phase <= 0.0;
            audio_in_left <= (others => '0');
            audio_in_right <= (others => '0');
            
        elsif rising_edge(clk) then
            if audio_valid_in = '1' then
                -- Generate sine wave
                sine_val := sin(sine_phase) * 0.8;  -- 80% of full scale
                sample_val := integer(sine_val * 32767.0);
                
                -- Clamp to 16-bit range
                if sample_val > 32767 then
                    sample_val := 32767;
                elsif sample_val < -32768 then
                    sample_val := -32768;
                end if;
                
                audio_in_left <= std_logic_vector(to_signed(sample_val, 16));
                audio_in_right <= std_logic_vector(to_signed(sample_val, 16));
                
                -- Update phase for next sample
                sine_phase <= sine_phase + PHASE_INCREMENT;
                if sine_phase >= 2.0 * MATH_PI then
                    sine_phase <= sine_phase - 2.0 * MATH_PI;
                end if;
            end if;
        end if;
    end process;
    
    -- Sample timing generator (48kHz sample rate simulation)
    sample_timing : process(clk, reset_n)
        variable clk_count : integer := 0;
    begin
        if reset_n = '0' then
            audio_valid_in <= '0';
            clk_count := 0;
            sample_counter <= 0;
            
        elsif rising_edge(clk) then
            audio_valid_in <= '0';  -- Default
            
            clk_count := clk_count + 1;
            
            -- Generate sample valid pulse every 256 clock cycles (approximately 48kHz)
            if clk_count >= 256 then
                audio_valid_in <= '1';
                clk_count := 0;
                sample_counter <= sample_counter + 1;
            end if;
        end if;
    end process;
    
    -- Test stimulus
    test_process : process
        
        -- Procedure to wait for N samples
        procedure wait_samples(count : integer) is
        begin
            for i in 1 to count loop
                wait until rising_edge(clk) and audio_valid_in = '1';
            end loop;
        end procedure;
        
        -- Procedure to test bit depth setting
        procedure test_bit_depth(depth : integer; test_name : string) is
        begin
            report "Testing " & test_name & " (bit depth " & integer'image(depth + 1) & ")";
            bit_depth <= std_logic_vector(to_unsigned(depth, 4));
            wait_samples(100);  -- Let effect settle
        end procedure;
        
        -- Procedure to test decimation setting
        procedure test_decimation(decim : integer; test_name : string) is
        begin
            report "Testing " & test_name & " (decimation " & integer'image(decim) & ")";
            decimation <= std_logic_vector(to_unsigned(decim, 4));
            wait_samples(100);  -- Let effect settle
        end procedure;
        
    begin
        report "Starting Bit Crusher Test";
        
        -- Reset sequence
        reset_n <= '0';
        wait for 1 us;
        reset_n <= '1';
        wait for 1 us;
        
        -- Wait for initial samples to start
        wait_samples(10);
        
        -- Test 1: Bit depth reduction
        report "=== Test 1: Bit Depth Reduction ===";
        decimation <= x"0";  -- No decimation
        mix_level <= x"FF";  -- 100% wet
        
        test_bit_depth(15, "16-bit (no crushing)");
        test_bit_depth(11, "12-bit crushing");
        test_bit_depth(7, "8-bit crushing");
        test_bit_depth(3, "4-bit crushing");
        test_bit_depth(1, "2-bit crushing");
        test_bit_depth(0, "1-bit crushing");
        
        -- Test 2: Sample rate decimation
        report "=== Test 2: Sample Rate Decimation ===";
        bit_depth <= x"F";   -- No bit crushing
        
        test_decimation(0, "No decimation");
        test_decimation(1, "Light decimation");
        test_decimation(3, "Medium decimation");
        test_decimation(7, "Heavy decimation");
        test_decimation(15, "Maximum decimation");
        
        -- Test 3: Combined effects
        report "=== Test 3: Combined Effects ===";
        
        report "Testing 8-bit + medium decimation";
        bit_depth <= x"7";   -- 8-bit
        decimation <= x"3";  -- Medium decimation
        wait_samples(100);
        
        report "Testing 4-bit + heavy decimation";
        bit_depth <= x"3";   -- 4-bit
        decimation <= x"7";  -- Heavy decimation
        wait_samples(100);
        
        report "Testing extreme settings";
        bit_depth <= x"0";   -- 1-bit
        decimation <= x"F";  -- Maximum decimation
        wait_samples(100);
        
        -- Test 4: Mix level (dry/wet blend)
        report "=== Test 4: Dry/Wet Mix ===";
        bit_depth <= x"3";   -- 4-bit crushing
        decimation <= x"3";  -- Medium decimation
        
        report "Testing 0% wet (dry only)";
        mix_level <= x"00";
        wait_samples(50);
        
        report "Testing 25% wet";
        mix_level <= x"40";
        wait_samples(50);
        
        report "Testing 50% wet";
        mix_level <= x"80";
        wait_samples(50);
        
        report "Testing 75% wet";
        mix_level <= x"C0";
        wait_samples(50);
        
        report "Testing 100% wet (effect only)";
        mix_level <= x"FF";
        wait_samples(50);
        
        -- Test 5: Dynamic parameter changes
        report "=== Test 5: Dynamic Parameter Changes ===";
        
        -- Sweep bit depth
        report "Sweeping bit depth from 16-bit to 1-bit";
        for i in 15 downto 0 loop
            bit_depth <= std_logic_vector(to_unsigned(i, 4));
            wait_samples(10);
        end loop;
        
        -- Sweep decimation
        report "Sweeping decimation from 0 to 15";
        bit_depth <= x"7";   -- 8-bit
        for i in 0 to 15 loop
            decimation <= std_logic_vector(to_unsigned(i, 4));
            wait_samples(10);
        end loop;
        
        wait_samples(100);
        
        report "Bit Crusher Test Completed Successfully";
        test_done <= true;
        wait;
    end process;
    
    -- Monitor process for debugging
    monitor_process : process(clk)
        variable prev_sample : integer := 0;
        variable current_sample : integer;
    begin
        if rising_edge(clk) and audio_valid_out = '1' then
            current_sample := to_integer(signed(audio_out_left));
            
            -- Report significant changes in output
            if abs(current_sample - prev_sample) > 8192 then  -- Significant change
                report "Sample " & integer'image(sample_counter) & 
                       ": Input=" & integer'image(to_integer(signed(audio_in_left))) &
                       ", Output=" & integer'image(current_sample) &
                       ", Bit Depth=" & integer'image(to_integer(unsigned(bit_depth)) + 1) &
                       ", Decimation=" & integer'image(to_integer(unsigned(decimation)));
            end if;
            
            prev_sample := current_sample;
        end if;
    end process;
    
end architecture testbench;