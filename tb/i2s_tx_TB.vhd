-- tb_i2s_tx.vhd
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;

entity tb_i2s_tx is end tb_i2s_tx;

architecture sim of tb_i2s_tx is
  -- ====== I2S params ======
  constant WORD_BITS        : natural := 16;
  constant BCLK_PERIOD      : time    := 640 ns;            -- 1.5625MHz
  constant HALF_BCLK        : time    := BCLK_PERIOD/2;

  -- Test words
  constant LEFT_WORD  : std_logic_vector(15 downto 0) := x"DEAD";
  constant RIGHT_WORD : std_logic_vector(15 downto 0) := x"BEEF";

  -- Delays
  constant RESET_DELAY : time := 200 ns;

  -- Signal declarations for I2S interface
  signal i2s_bclk       : std_logic := '0';
  signal i2s_ws         : std_logic := '0';
  signal reset_n        : std_logic := '0';
  signal i2s_sdata      : std_logic;
  signal audio_left     : std_logic_vector(15 downto 0) := LEFT_WORD;
  signal audio_right    : std_logic_vector(15 downto 0) := RIGHT_WORD;
  signal tx_ready       : std_logic := '1';
  signal sample_request : std_logic;

  -- Verification signals
  signal received_left  : std_logic_vector(15 downto 0);
  signal received_right : std_logic_vector(15 downto 0);
  signal frame_complete : std_logic := '0';

begin
  -- DUT
  uut: entity work.i2s_tx
    port map (
      i2s_bclk       => i2s_bclk,
      i2s_ws         => i2s_ws,
      reset_n        => reset_n,
      audio_left     => audio_left,
      audio_right    => audio_right,
      tx_ready       => tx_ready,
      i2s_sdata      => i2s_sdata,
      sample_request => sample_request
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

    -- Word Select (WS) generation process
    -- Philips I2S Protocol Standard:
    -- UM11732 (§3, Fig.1): “the device generating SCK and WS is the controller.”
    --      WS (Word Select): 0 = Left channel, 1 = Right channel
    --      WS changes on falling edge of BCLK
    --      Data transmission starts one BCLK period after WS change
    --      Each channel gets exactly 16 BCLK periods for data transmission
    i2s_ws_gen : process
    begin
        -- Initialise
        i2s_ws <= '0';      -- Start with left channel

        -- Wait for reset release
        wait until reset_n = '1';
        wait for RESET_DELAY;

        -- Align with BCLK falling edge
        -- UM11732 (§3.2): “WS = 0; left, WS = 1; right. WS changes one clock period before the MSB is transmitted.”
        wait until falling_edge(i2s_bclk);

        loop
            -- LEFT CHANNEL - WS = 0 for exactly 16 BCLK periods
            i2s_ws <= '0';
            for i in 1 to 16 loop               -- 16 BCLK periods for left channel
                wait until falling_edge(i2s_bclk);
            end loop;

            -- RIGHT CHANNEL - WS = 1 for exactly 16 BCLK periods  
            i2s_ws <= '1';
            for i in 1 to 16 loop               -- 16 BCLK periods for right channel
                wait until falling_edge(i2s_bclk);
            end loop;
        end loop;
    end process;

    -- Test data stimulus process
    -- Simple constant test pattern
    stimulus : process
    begin
        -- Wait for reset release
        wait until reset_n = '1';
        wait for RESET_DELAY;

        -- UM11732 §3.3:
        -- “Serial data is transmitted in two’s complement with the MSB first.”
        -- Single test pattern: Constant values
        audio_left <= x"DEAD";
        audio_right <= x"BEEF";
        tx_ready <= '1';

        wait;
    end process;

    -- I2S Serial Data Receiver/Checker Process
    -- 1. WS changes on falling edge
    -- 2. MSB appears one BCLK period after WS changes
    -- 3. Data is valid on the rising edge of BCLK (receivers sample on rising edge)
    i2s_checker : process
        variable bit_count : integer := 0;
        variable left_shift_reg : std_logic_vector(15 downto 0) := (others => '0');
        variable right_shift_reg : std_logic_vector(15 downto 0) := (others => '0');
        variable channel_state : string(1 to 4) := "IDLE";
    begin
        -- Initialise signals
        received_left <= (others => '0');
        received_right <= (others => '0');

        -- Wait for reset release
        wait until reset_n = '1';
        wait for RESET_DELAY;

        -- Wait for several WS periods to let things settle
        wait for 50 * BCLK_PERIOD;

        -- Start checking - sync with falling edges like the transmitter
        -- UM11732 §3.3:
        -- “Data is valid on the rising edge of SCK; the transmitter changes the data on the falling edge.”
        loop

            wait until rising_edge(i2s_bclk);

            case channel_state is
                when "IDLE" =>
                    if i2s_ws = '0' then
                        -- Start LEFT channel - Wait one BCLK period after WS changes before sampling MSB
                        wait until rising_edge(i2s_bclk);
                        channel_state := "LEFT";
                        bit_count := 1;
                        left_shift_reg := (others => '0');
                        left_shift_reg := left_shift_reg(14 downto 0) & i2s_sdata;  -- Standard shift register
                        report "Starting LEFT channel (WS=0)" severity note;
                    elsif i2s_ws = '1' then
                        -- Start RIGHT channel - Wait one BCLK period after WS changes before sampling MSB
                        wait until rising_edge(i2s_bclk);
                        channel_state := "RGHT";
                        bit_count := 1;
                        right_shift_reg := (others => '0');
                        right_shift_reg := right_shift_reg(14 downto 0) & i2s_sdata;  -- Standard shift register
                        report "Starting RIGHT channel (WS=1)" severity note;
                    end if;

                when "LEFT" =>
                    if bit_count < 16 then
                        -- Continue collecting bits
                        wait until rising_edge(i2s_bclk);
                        left_shift_reg := left_shift_reg(14 downto 0) & i2s_sdata;
                        bit_count := bit_count + 1;

                        if bit_count = 16 then
                            received_left <= left_shift_reg;
                            channel_state := "IDLE";
                            report "LEFT complete: " & integer'image(to_integer(unsigned(left_shift_reg))) & " (expected 57005)" severity note;
                        end if;
                    else
                        -- Should not happen, but reset if we get here
                        channel_state := "IDLE";
                    end if;

                when "RGHT" =>
                    if bit_count < 16 then
                        -- Continue collecting bits
                        wait until rising_edge(i2s_bclk);
                        right_shift_reg := right_shift_reg(14 downto 0) & i2s_sdata;
                        bit_count := bit_count + 1;

                        if bit_count = 16 then
                            received_right <= right_shift_reg;
                            frame_complete <= '1';
                            wait for 1 ns;
                            frame_complete <= '0';
                            channel_state := "IDLE";
                            report "RIGHT complete: " & integer'image(to_integer(unsigned(right_shift_reg))) & " (expected 48879)" severity note;
                        end if;
                    else
                        -- Should not happen, but reset if we get here
                        channel_state := "IDLE";
                    end if;

                when others =>
                    channel_state := "IDLE";
            end case;
        end loop;
    end process;

    -- Data verification process
    checker : process
        variable sample_count : integer := 0;
    begin
        loop
            wait until rising_edge(frame_complete);
            sample_count := sample_count + 1;

            -- Simple check: always expect the same constant values
            assert received_left = x"DEAD"
                report "Sample " & integer'image(sample_count) & " LEFT mismatch: got " & 
                       integer'image(to_integer(unsigned(received_left))) & " (expected 57005=0xDEAD)"
                severity error;

            assert received_right = x"BEEF"
                report "Sample " & integer'image(sample_count) & " RIGHT mismatch: got " &
                       integer'image(to_integer(unsigned(received_right))) & " (expected 48879=0xBEEF)"
                severity error;

            if sample_count >= 5 then
                report "Successfully verified " & integer'image(sample_count) & " transmitted samples" severity note;
                exit; -- Stop checking after 5 samples
            end if;
        end loop;
        wait; -- Process ends cleanly
    end process;

    -- Monitor sample_request signal
    sample_request_monitor : process
    begin
        loop
            wait until rising_edge(sample_request);
            report "Sample request generated at time " & time'image(now) severity note;
        end loop;
    end process;

    -- End-of-sim timeout
    stopper : process
    begin
        wait for 200 * BCLK_PERIOD;  -- Simple timeout for basic test
        report "TB finished" severity failure;  -- not actually a failure, but immediately stops sim
    end process;

end architecture;
