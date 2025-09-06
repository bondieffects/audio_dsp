-- ============================================================================
-- I2S Transmitter Testbench (PROBLEMATIC VERSION - FOR DOCUMENTATION)
-- ============================================================================
-- This testbench demonstrates common timing and synchronization issues
-- encountered when verifying I2S transmitters.
--
-- KNOWN ISSUES IN THIS VERSION:
-- 1. Incorrect sampling timing (missing MSB)
-- 2. Wrong shift register direction (bit reversal)
-- 3. Poor WS transition detection
-- 4. Clock edge misalignment
-- 5. Incomplete bit collection logic
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;

entity tb_i2s_tx_problematic is
end tb_i2s_tx_problematic;

architecture sim of tb_i2s_tx_problematic is
    
    -- Component declaration
    component i2s_tx_problematic is
        Port (
            i2s_bclk     : in  std_logic;
            reset_n      : in  std_logic;
            audio_left   : in  std_logic_vector(15 downto 0);
            audio_right  : in  std_logic_vector(15 downto 0);
            tx_ready     : in  std_logic;
            i2s_ws       : in  std_logic;
            i2s_sdata    : out std_logic;
            request_sample : out std_logic
        );
    end component;
    
    -- Constants
    constant BCLK_PERIOD : time := 20.833 ns;  -- 48kHz, 32-bit frame = 1.536 MHz BCLK
    constant RESET_DELAY : time := 100 ns;
    
    -- Signals
    signal i2s_bclk     : std_logic := '0';
    signal reset_n      : std_logic := '0';
    signal audio_left   : std_logic_vector(15 downto 0) := (others => '0');
    signal audio_right  : std_logic_vector(15 downto 0) := (others => '0');
    signal tx_ready     : std_logic := '0';
    signal i2s_ws       : std_logic := '0';
    signal i2s_sdata    : std_logic;
    signal request_sample : std_logic;
    
    -- Verification signals
    signal received_left  : std_logic_vector(15 downto 0) := (others => '0');
    signal received_right : std_logic_vector(15 downto 0) := (others => '0');
    signal frame_complete : std_logic := '0';

begin

    -- Instantiate the I2S transmitter
    uut: i2s_tx_problematic
        port map (
            i2s_bclk     => i2s_bclk,
            reset_n      => reset_n,
            audio_left   => audio_left,
            audio_right  => audio_right,
            tx_ready     => tx_ready,
            i2s_ws       => i2s_ws,
            i2s_sdata    => i2s_sdata,
            request_sample => request_sample
        );

    -- Clock generation
    i2s_bclk <= not i2s_bclk after BCLK_PERIOD / 2;

    -- Reset generation  
    reset_n <= '0', '1' after RESET_DELAY;

    -- Report sample requests
    sample_request_monitor : process(request_sample)
    begin
        if rising_edge(request_sample) then
            report "Sample request generated at time " & time'image(now) severity note;
        end if;
    end process;

    -- Simple stopper process
    stopper : process
    begin
        wait for 128 us;
        report "TB finished" severity failure;
    end process;

    -- PROBLEMATIC: Word Select (WS) generation with timing issues
    i2s_ws_gen : process
    begin
        -- Initialise
        i2s_ws <= '0';

        -- Wait for reset release
        wait until reset_n = '1';
        wait for RESET_DELAY;

        -- ISSUE: Not properly aligned with BCLK
        wait until rising_edge(i2s_bclk);  -- Should be falling_edge

        loop
            -- LEFT CHANNEL - ISSUE: Timing not exact (should be 16 periods exactly)
            i2s_ws <= '0';
            for i in 1 to 15 loop  -- PROBLEM: Only 15 periods instead of 16
                wait until rising_edge(i2s_bclk);  -- ISSUE: Wrong edge
            end loop;

            -- RIGHT CHANNEL - ISSUE: Same timing problems
            i2s_ws <= '1';
            for i in 1 to 15 loop  -- PROBLEM: Only 15 periods instead of 16
                wait until rising_edge(i2s_bclk);  -- ISSUE: Wrong edge
            end loop;
        end loop;
    end process;

    -- Test data stimulus process
    stimulus : process
    begin
        -- Wait for reset release
        wait until reset_n = '1';
        wait for RESET_DELAY;

        -- Test pattern
        audio_left <= x"DEAD";
        audio_right <= x"BEEF";
        tx_ready <= '1';

        wait;
    end process;

    -- PROBLEMATIC: I2S Serial Data Receiver/Checker Process
    -- This demonstrates multiple timing and logic errors
    i2s_checker : process
        variable bit_count : integer := 0;
        variable left_shift_reg : std_logic_vector(15 downto 0) := (others => '0');
        variable right_shift_reg : std_logic_vector(15 downto 0) := (others => '0');
        variable channel_state : string(1 to 4) := "IDLE";
    begin
        -- Initialize
        received_left <= (others => '0');
        received_right <= (others => '0');
        
        -- Wait for reset release
        wait until reset_n = '1';
        wait for RESET_DELAY;
        
        -- ISSUE: Not enough settling time
        wait for 10 * BCLK_PERIOD;  -- Should be much longer
        
        loop
            -- PROBLEM: Using rising edge when transmitter uses falling edge
            wait until rising_edge(i2s_bclk);
            
            case channel_state is
                when "IDLE" =>
                    if i2s_ws = '0' then
                        channel_state := "LEFT";
                        bit_count := 0;  -- ISSUE: Missing MSB because we start at 0
                        left_shift_reg := (others => '0');
                        -- PROBLEM: Not capturing the MSB that's already available
                        report "Starting LEFT channel (WS=0)" severity note;
                    elsif i2s_ws = '1' then
                        channel_state := "RGHT";
                        bit_count := 0;  -- ISSUE: Missing MSB because we start at 0
                        right_shift_reg := (others => '0');
                        -- PROBLEM: Not capturing the MSB that's already available
                        report "Starting RIGHT channel (WS=1)" severity note;
                    end if;
                    
                when "LEFT" =>
                    -- PROBLEM: Wrong shift direction causes bit reversal
                    left_shift_reg := i2s_sdata & left_shift_reg(15 downto 1);
                    bit_count := bit_count + 1;
                    
                    -- ISSUE: Wrong bit count check
                    if bit_count = 15 then  -- Should be 16
                        received_left <= left_shift_reg;
                        channel_state := "IDLE";
                        report "LEFT complete: " & integer'image(to_integer(unsigned(left_shift_reg))) 
                               & " (expected 57005)" severity note;
                    end if;
                    
                when "RGHT" =>
                    -- PROBLEM: Same issues as LEFT channel
                    right_shift_reg := i2s_sdata & right_shift_reg(15 downto 1);
                    bit_count := bit_count + 1;
                    
                    if bit_count = 15 then  -- Should be 16
                        received_right <= right_shift_reg;
                        frame_complete <= '1';
                        wait for 1 ns;
                        frame_complete <= '0';
                        channel_state := "IDLE";
                        report "RIGHT complete: " & integer'image(to_integer(unsigned(right_shift_reg))) 
                               & " (expected 48879)" severity note;
                    end if;
                    
                when others =>
                    channel_state := "IDLE";
            end case;
        end loop;
    end process;

    -- PROBLEMATIC: Data verification process with incorrect logic
    checker : process
        variable sample_count : integer := 0;
    begin
        loop
            wait until rising_edge(frame_complete);
            sample_count := sample_count + 1;
            
            -- ISSUE: Incorrect value comparisons due to bit collection errors
            if received_left /= x"DEAD" then
                report "Sample " & integer'image(sample_count) 
                       & " LEFT mismatch: got " & integer'image(to_integer(unsigned(received_left))) 
                       & " (expected 57005=0xDEAD)" severity error;
            end if;
            
            if received_right /= x"BEEF" then
                report "Sample " & integer'image(sample_count) 
                       & " RIGHT mismatch: got " & integer'image(to_integer(unsigned(received_right))) 
                       & " (expected 48879=0xBEEF)" severity error;
            end if;
            
            -- PROBLEM: Premature success reporting
            if sample_count = 3 then  -- Should verify more samples
                report "Successfully verified " & integer'image(sample_count) 
                       & " transmitted samples" severity note;
                exit;
            end if;
        end loop;
        
        wait;
    end process;

end sim;
