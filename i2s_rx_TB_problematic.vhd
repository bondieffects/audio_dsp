-- tb_i2s_rx_problematic.vhd - PROBLEMATIC VERSION
-- This file demonstrates common I2S testbench implementation errors
-- DO NOT USE - For educational purposes only
-- See i2s_rx_TB.vhd for the corrected version

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;

entity tb_i2s_rx_problematic is end tb_i2s_rx_problematic;

architecture sim of tb_i2s_rx_problematic is
  -- ====== I2S params ======
  constant WORD_BITS        : natural := 16;
  constant BCLK_PERIOD      : time    := 640 ns;    -- 1.5625MHz
  constant HALF_BCLK        : time    := BCLK_PERIOD/2;

  -- Test words
  constant LEFT_WORD  : std_logic_vector(15 downto 0) := x"DEAD";
  constant RIGHT_WORD : std_logic_vector(15 downto 0) := x"BEEF";

  -- Delays
  constant RESET_DELAY : time := 100 ns; -- PROBLEM: Too short, causes timing issues

  -- Signal declarations for I2S interface
  signal i2s_bclk   : std_logic := '0';
  signal i2s_ws     : std_logic := '0';
  signal reset_n    : std_logic := '0';
  signal i2s_sdata  : std_logic := '0';
  signal audio_left : std_logic_vector(15 downto 0);
  signal audio_right: std_logic_vector(15 downto 0);
  signal audio_valid: std_logic;

begin
  -- DUT
  uut: entity work.i2s_rx_problematic
    port map (
      i2s_bclk   => i2s_bclk,
      i2s_ws     => i2s_ws,
      reset_n    => reset_n,
      i2s_sdata  => i2s_sdata,
      audio_left => audio_left,
      audio_right=> audio_right,
      audio_valid=> audio_valid
    );

    -- Free-running 1.5625 MHz bit clock 
    i2s_bclk_proc : process
    begin
        loop
            i2s_bclk <= '0';
            wait for HALF_BCLK;
            i2s_bclk <= '1';
            wait for HALF_BCLK;
        end loop;
    end process;

    -- Reset stimulus process
    reset_proc : process
    begin
        reset_n <= '0';
        wait for RESET_DELAY;
        reset_n <= '1';
        wait;                     -- hold forever
    end process;

    -- PROBLEM: Separate WS and data processes create race conditions
    -- Word-select (WS) generator: toggle every WORD_BITS bits
    i2s_ws_proc : process
    variable bit_counter : integer := 0;
    begin
        -- Initialize WS and wait for reset release
        i2s_ws <= '0';
        wait until reset_n = '1';
        wait for RESET_DELAY;
        loop
            wait until rising_edge(i2s_bclk);  -- PROBLEM: Wrong edge for WS changes
            if bit_counter = WORD_BITS-1 then               -- every 16 bits
                i2s_ws <= not i2s_ws;                       -- toggle WS
                bit_counter := 0;                           -- reset bit counter
            else
                bit_counter := bit_counter + 1;             -- increment bit counter
            end if;
        end loop;
    end process;

    -- PROBLEM: Serial data process tries to sync with separate WS process
    serial_src_stim : process
        variable bit_counter : integer := 0;
        variable current_data : std_logic_vector(15 downto 0);
    begin
        -- Initialize
        i2s_sdata <= '0';

        -- wait for reset release  
        wait until reset_n = '1';
        wait for RESET_DELAY;
        
        -- Start with left channel data
        current_data := LEFT_WORD;
        
        loop
            wait until rising_edge(i2s_bclk);  -- PROBLEM: Wrong edge, should be falling
            
            -- PROBLEM: Complex synchronization logic prone to errors
            if bit_counter = WORD_BITS-1 then
                -- End of current word, prepare next word
                if i2s_ws = '0' then
                    current_data := RIGHT_WORD;  -- PROBLEM: Logic backwards
                else
                    current_data := LEFT_WORD;   
                end if;
                bit_counter := 0;
            else
                bit_counter := bit_counter + 1;
            end if;
            
            -- PROBLEM: Bit indexing error
            i2s_sdata <= current_data(15 - bit_counter);  -- May cause off-by-one errors
        end loop;
    end process;

  -- Check for valid data
  -- PROBLEM: Tries to use library function that may not exist
  checker : process
    variable sample_count : integer := 0;
  begin
    loop
      wait until rising_edge(audio_valid);
      sample_count := sample_count + 1;

      -- PROBLEM: Uses to_hstring which may not be available in all simulators
      assert audio_left  = LEFT_WORD
        report "Sample " & integer'image(sample_count) & " LEFT mismatch: got 0x" & 
               to_hstring(audio_left) & ", exp 0xDEAD"  -- COMPILATION ERROR!
        severity error;
      assert audio_right = RIGHT_WORD
        report "Sample " & integer'image(sample_count) & " RIGHT mismatch: got 0x" &
               to_hstring(audio_right) & ", exp 0xBEEF"  -- COMPILATION ERROR!
        severity error;

      if sample_count >= 5 then
        report "Successfully verified " & integer'image(sample_count) & " samples" severity note;
        exit; -- Stop checking after 5 samples
      end if;
    end loop;
    wait; -- Process ends cleanly
  end process;

  -- PROBLEM: Timeout too short for debugging
  stopper : process
  begin
    wait for 50 * BCLK_PERIOD;  -- PROBLEM: May timeout before any data received
    report "TB finished" severity failure;
  end process;
end architecture;

-- ============================================================================
-- PROBLEMS DEMONSTRATED IN THIS FILE:
-- ============================================================================
-- 1. RACE CONDITIONS: Separate WS and data processes get out of sync
-- 2. WRONG CLOCK EDGES: Using rising edge instead of falling for data changes
-- 3. SHORT RESET DELAY: Insufficient time for system to stabilize
-- 4. LIBRARY COMPATIBILITY: Using functions not available in all simulators
-- 5. COMPLEX SYNCHRONIZATION: Trying to sync separate processes is error-prone
-- 6. BIT INDEXING ERRORS: Off-by-one errors in data transmission
-- 7. INSUFFICIENT TIMEOUT: Simulation may end before problems are detected
-- 8. BACKWARDS LOGIC: Channel assignment logic is inverted
--
-- SYMPTOMS THESE PROBLEMS CAUSE:
-- - Compilation errors due to missing library functions
-- - Data corruption (wrong values received)
-- - Timing issues (no data received for long periods)
-- - Race conditions between WS and data
-- - Simulation timeouts before seeing results
--
-- LESSON: Keep testbenches simple and follow I2S protocol exactly
-- ============================================================================
